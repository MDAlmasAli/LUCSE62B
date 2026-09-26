import '../core/routine_cells.dart';
import '../core/sheets_api.dart';

/// A course a teacher takes this semester, with the sections ("62-B").
class CTCourse {
  final String code, name;
  final List<String> sections;
  CTCourse(this.code, this.name, this.sections);
}

/// A teacher and the courses/sections they teach.
class CTTeacher {
  final String initials, name, desig;
  final List<CTCourse> courses;
  CTTeacher(this.initials, this.name, this.desig, this.courses);
}

/// A teacher reference under a course (course → teachers view).
class CTTeacherRef {
  final String initials, name, desig;
  final List<String> sections;
  CTTeacherRef(this.initials, this.name, this.desig, this.sections);
}

/// A course and the teachers/sections taking it.
class CTCourseEntry {
  final String code, name;
  final List<CTTeacherRef> teachers;
  CTCourseEntry(this.code, this.name, this.teachers);
}

class CourseTeachersData {
  final List<CTTeacher> byTeacher;
  final List<CTCourseEntry> byCourse;
  CourseTeachersData(this.byTeacher, this.byCourse);
}

/// Builds the Course Teachers maps (teacher→courses and course→teachers) by
/// scanning every section's class routine + CPG_Teachers / CPG_Courses.
/// Mirrors the website's course-teachers.js.
class CourseTeachersRepository {
  CourseTeachersRepository._();
  static final instance = CourseTeachersRepository._();

  static const _days = ['SATURDAY', 'SUNDAY', 'MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY'];
  static const _fallbackId = '1H1IrP65R_Nz2LfJ7G3KP7pPQNIYMLvka';

  final _api = SheetsApi.instance;
  CourseTeachersData? _cache;

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
    return const [_fallbackId];
  }

  static (String, String)? _parseCell(String cell) {
    final c = fixCourseCodeSpacing(cell.trim());
    if (c.isEmpty || c == '--' || c == '–') return null;
    final parts = c.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return null;
    final code = parts[0];
    final initials = parts.length >= 2 ? parts[1] : '';
    return (code, initials);
  }

  Future<CourseTeachersData> load() async {
    if (_cache != null) return _cache!;
    final ids = await _sheetIds();
    final fetched = await Future.wait([
      _api.sheet('CPG_Teachers').catchError((_) => <List<String>>[]),
      _api.sheet('CPG_Courses').catchError((_) => <List<String>>[]),
      _allDayRows(ids),
    ]);
    final tch = fetched[0] as List<List<String>>;
    final cpg = fetched[1] as List<List<String>>;
    final dayRows = fetched[2] as List<List<List<String>>>;

    // teacherInfo: initials → {name, desig}
    final teacherInfo = <String, ({String name, String desig})>{};
    for (final r in tch) {
      if (r.length < 2) continue;
      final acr = r[0].trim().toUpperCase();
      final name = r[1].trim();
      final desig = r.length > 2 ? r[2].trim() : '';
      if (acr.isEmpty || name.isEmpty) continue;
      if (RegExp(r'^(acronym|initials|name)', caseSensitive: false).hasMatch(acr)) continue;
      teacherInfo[acr] = (name: name, desig: desig);
    }

    // courseTitles: code → title
    final courseTitles = <String, String>{};
    for (final r in cpg) {
      if (r.length < 2) continue;
      final code = r[1].trim().toUpperCase();
      final title = r[0].trim();
      if (code.isEmpty || title.isEmpty) continue;
      if (RegExp(r'^(code|title|course)', caseSensitive: false).hasMatch(code)) continue;
      courseTitles[code] = title;
    }

    // Scan routine rows across all days.
    final teacherMapRaw = <String, Map<String, Set<String>>>{}; // initials → code → {batch-section}
    final courseMapRaw = <String, Map<String, Set<String>>>{}; // code → initials → {batch-section}

    for (final rows in dayRows) {
      if (rows.isEmpty) continue;
      var dataStart = 0;
      // Find where the time-header ends (first 3 rows may hold labels).
      final firstColsHaveTime = rows.isNotEmpty &&
          rows[0].length > 3 &&
          rows[0].sublist(3).any((c) => RegExp(r'\d+:\d+').hasMatch(c));
      if (!firstColsHaveTime) {
        for (var r = 0; r < rows.length && r < 3; r++) {
          if (rows[r].length > 3 && rows[r].sublist(3).any((c) => RegExp(r'\d+:\d+').hasMatch(c))) {
            dataStart = r + 1;
            break;
          }
        }
      }
      for (var r = dataStart; r < rows.length; r++) {
        final cells = rows[r];
        final batch = (cells.length > 1 ? cells[1] : '').replaceAll(RegExp(r'\.0+$'), '').trim();
        final section = (cells.length > 2 ? cells[2] : '').trim().toUpperCase();
        if (batch.isEmpty || !RegExp(r'^\d+$').hasMatch(batch)) continue;
        if (section.isEmpty || !RegExp(r'^[A-Z]$').hasMatch(section)) continue;
        final batchSec = '$batch-$section';
        for (var i = 3; i < cells.length; i++) {
          final parsed = _parseCell(cells[i]);
          if (parsed == null) continue;
          final code = parsed.$1.toUpperCase();
          final initials = parsed.$2.toUpperCase();
          if (initials.isEmpty || initials == 'BREAK') continue;
          teacherMapRaw.putIfAbsent(initials, () => {}).putIfAbsent(code, () => {}).add(batchSec);
          courseMapRaw.putIfAbsent(code, () => {}).putIfAbsent(initials, () => {}).add(batchSec);
        }
      }
    }

    final byTeacher = teacherMapRaw.entries.map((e) {
      final info = teacherInfo[e.key];
      final courses = e.value.entries
          .map((c) => CTCourse(c.key, courseTitles[c.key] ?? '', c.value.toList()..sort()))
          .toList()
        ..sort((a, b) => a.code.compareTo(b.code));
      return CTTeacher(e.key, info?.name ?? e.key, info?.desig ?? '', courses);
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final byCourse = courseMapRaw.entries.map((e) {
      final teachers = e.value.entries.map((t) {
        final info = teacherInfo[t.key];
        return CTTeacherRef(t.key, info?.name ?? t.key, info?.desig ?? '', t.value.toList()..sort());
      }).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      return CTCourseEntry(e.key, courseTitles[e.key] ?? '', teachers);
    }).toList()
      ..sort((a, b) => a.code.compareTo(b.code));

    return _cache = CourseTeachersData(byTeacher, byCourse);
  }

  Future<List<List<List<String>>>> _allDayRows(List<String> ids) async {
    final out = <List<List<String>>>[];
    for (final day in _days) {
      final tables = <SheetTable>[];
      for (final id in ids) {
        try {
          tables.add(await _api.tableById(id, tab: day));
        } catch (_) {}
      }
      out.add(mergeSectionRows(tables));
    }
    return out;
  }
}
