import '../core/routine_cells.dart';
import '../core/sheets_api.dart';
import 'session.dart';

/// One slot in a day's routine: either a class or a break.
class RoutineSlot {
  final String time;
  final bool isBreak;
  final String code;
  final String initials;
  final String room;
  const RoutineSlot.cls({
    required this.time,
    required this.code,
    required this.initials,
    required this.room,
  }) : isBreak = false;
  const RoutineSlot.brk(this.time)
      : isBreak = true,
        code = '',
        initials = '',
        room = '';
}

class RoutineDay {
  final String day;
  final List<RoutineSlot> slots; // classes only (breaks filtered for mobile)
  const RoutineDay(this.day, this.slots);
}

/// Builds the class routine for batch 62, section B from the Google Sheet
/// (one tab per day), mirroring the website's parser. Teacher acronyms are
/// resolved to full names via CPG_Teachers.
class RoutineRepository {
  RoutineRepository._();
  static final instance = RoutineRepository._();

  static const days = [
    'SATURDAY', 'SUNDAY', 'MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY'
  ];
  static const _fallbackId = '1H1IrP65R_Nz2LfJ7G3KP7pPQNIYMLvka';

  final _api = SheetsApi.instance;

  Future<List<String>> _sheetIds() async {
    try {
      final rows = await _api.sheet('Routine');
      for (final row in rows) {
        if (row.isEmpty) continue;
        if (!row[0].toLowerCase().contains('class routine')) continue;
        final ids = <String>[];
        for (final cell in row) {
          final m = RegExp(r'spreadsheets/d/([a-zA-Z0-9_-]+)').firstMatch(cell);
          if (m != null && !ids.contains(m.group(1))) ids.add(m.group(1)!);
        }
        if (ids.isNotEmpty) return ids;
      }
    } catch (_) {}
    return [_fallbackId];
  }

  Future<Map<String, String>> _teacherMap() async {
    final map = <String, String>{};
    try {
      final rows = await _api.sheet('CPG_Teachers');
      for (final r in rows) {
        if (r.length < 2) continue;
        final acr = r[0].trim().toUpperCase();
        final name = r[1].trim();
        if (acr.isEmpty || name.isEmpty) continue;
        if (RegExp(r'^(acronym|initials|name)', caseSensitive: false).hasMatch(acr)) {
          continue;
        }
        map[acr] = name;
      }
    } catch (_) {}
    return map;
  }

  /// Fetch + parse the full week for 62/B. Returns days that actually have class.
  Future<({List<RoutineDay> week, Map<String, String> teachers})> load() async {
    final ids = await _sheetIds();
    final teachers = await _teacherMap();

    // Fetch every day from every linked sheet, then merge per day.
    final week = <RoutineDay>[];
    for (final day in days) {
      final tables = <SheetTable>[];
      for (final id in ids) {
        try {
          tables.add(await _api.tableById(id, tab: day));
        } catch (_) {}
      }
      final merged = _merge(tables);
      if (merged == null) continue;
      final slots = _parseDay(merged);
      if (slots.any((s) => !s.isBreak)) week.add(RoutineDay(day, slots));
    }
    return (week: week, teachers: teachers);
  }

  SheetTable? _merge(List<SheetTable> tables) {
    final valid = tables.where((t) => t.rows.isNotEmpty || t.cols.isNotEmpty).toList();
    if (valid.isEmpty) return null;
    // Base = the table with the most columns; rows from every sheet, except a
    // batch/section an earlier sheet already lists (first link wins).
    final base = valid.reduce((a, b) => b.cols.length > a.cols.length ? b : a);
    return SheetTable(cols: base.cols, rows: mergeSectionRows(valid));
  }

  List<RoutineSlot> _parseDay(SheetTable t, {String? batch, String? section}) {
    batch ??= Session.instance.batch;
    section ??= Session.instance.section;
    // Time labels live in the column headers after the first 3 (title/batch/section).
    var timeSlots = t.cols.length > 3 ? t.cols.sublist(3) : <String>[];
    var dataStart = 0;
    final hasTimes = timeSlots.any((s) => RegExp(r'\d+:\d+').hasMatch(s));
    if (!hasTimes) {
      for (var r = 0; r < t.rows.length && r < 3; r++) {
        final cells = t.rows[r];
        if (cells.length > 3 && cells.sublist(3).any((c) => RegExp(r'\d+:\d+').hasMatch(c))) {
          timeSlots = cells.sublist(3);
          dataStart = r + 1;
          break;
        }
      }
    }
    if (timeSlots.isEmpty) return const [];

    var breakIdx = -1;
    final targetRows = <List<String>>[];
    for (var r = dataStart; r < t.rows.length; r++) {
      final cells = t.rows[r];
      for (var i = 3; i < cells.length; i++) {
        if (cells[i].toUpperCase() == 'BREAK') breakIdx = i - 3;
      }
      final rowBatch = cells.length > 1 ? cells[1].replaceAll(RegExp(r'\.0+$'), '').trim() : '';
      final rowSec = cells.length > 2 ? cells[2].trim().toUpperCase() : '';
      if (rowBatch == batch && rowSec == section) targetRows.add(cells);
    }
    if (targetRows.isEmpty) return const [];

    String cellAt(List<String> row, int timeIdx) {
      final i = timeIdx + 3;
      return i < row.length ? row[i] : '';
    }

    final out = <RoutineSlot>[];
    for (var i = 0; i < timeSlots.length; i++) {
      final time = timeSlots[i].trim();
      if (time.isEmpty) continue;
      if (i == breakIdx) {
        out.add(RoutineSlot.brk(time));
        continue;
      }
      // First non-empty, non-BREAK cell across the section's rows.
      var value = '';
      for (final row in targetRows) {
        final c = cellAt(row, i);
        if (c.isNotEmpty && c.toUpperCase() != 'BREAK') {
          value = c;
          break;
        }
      }
      final parsed = _parseCell(value);
      if (parsed != null) {
        out.add(RoutineSlot.cls(
            time: time, code: parsed.$1, initials: parsed.$2, room: parsed.$3));
      }
    }
    return out;
  }

  /// "CODE INITIALS ROOM" → (code, initials, room).
  (String, String, String)? _parseCell(String cell) {
    final c = fixCourseCodeSpacing(cell.trim());
    if (c.isEmpty || c == '--' || c == '–') return null;
    final parts = c.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length >= 3) return (parts[0], parts[1], parts.sublist(2).join(' '));
    if (parts.length == 2) return (parts[0], '', parts[1]);
    if (parts.length == 1) return (parts[0], '', '');
    return null;
  }
}
