import '../core/sheets_api.dart';
import '../core/supa.dart';

/// Course metadata from CPG_Courses (name + default teacher).
class CourseInfo {
  final String name;
  final String teacher;
  final String desig;
  const CourseInfo(this.name, this.teacher, this.desig);
}

/// One cell entry in a section's day schedule.
class GridSlot {
  String time;
  final String code;
  final String initials;
  final String room;
  final bool isBreak;
  // Set for user-added custom courses (62B only). [customName] carries the
  // course name directly (custom codes aren't in CPG_Courses); [customId]
  // identifies the entry for deletion.
  final String? customName;
  final String? customId;
  GridSlot({
    required this.time,
    this.code = '',
    this.initials = '',
    this.room = '',
    this.isBreak = false,
    this.customName,
    this.customId,
  });

  bool get isCustom => customId != null;
  bool get isEnrollment => customId?.startsWith('enrollment:') ?? false;
}

/// A user-added custom course (stored in `student_custom_courses.courses`).
class CustomCourse {
  final String id, name, code, teacher, room, day, time;
  const CustomCourse({
    required this.id,
    required this.name,
    required this.code,
    required this.teacher,
    required this.room,
    required this.day,
    required this.time,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'code': code,
    'teacher': teacher,
    'room': room,
    'day': day,
    'time': time,
  };

  factory CustomCourse.fromJson(Map<String, dynamic> m) => CustomCourse(
    id: '${m['id'] ?? ''}',
    name: '${m['name'] ?? ''}',
    code: '${m['code'] ?? ''}',
    teacher: '${m['teacher'] ?? ''}',
    room: '${m['room'] ?? ''}',
    day: '${m['day'] ?? ''}',
    time: '${m['time'] ?? ''}',
  );
}

/// A set of days that share the same time-columns, rendered as one grid table.
class GridGroup {
  final List<String> days;
  final List<String> allTimes;
  final Set<String> breakTimes;
  const GridGroup(this.days, this.allTimes, this.breakTimes);
}

/// The full routine state for a selected batch/section.
class RoutineGridData {
  final List<({String batch, String section})> available;
  final Map<String, CourseInfo> courseInfo;
  final Map<String, String> teacherAcr; // acronym → full name
  final String semester;
  Map<String, List<GridSlot>> schedule; // day → slots (canonicalised times)
  List<GridGroup> groups;
  String batch;
  String section;

  RoutineGridData({
    required this.available,
    required this.courseInfo,
    required this.teacherAcr,
    required this.semester,
    required this.schedule,
    required this.groups,
    required this.batch,
    required this.section,
  });

  /// Teacher to show for a slot: routine acronym → CPG_Teachers full name, else
  /// the acronym, else the course's default teacher.
  String teacherFor(GridSlot s) {
    final acr = s.initials.trim().toUpperCase();
    if (acr.isNotEmpty && teacherAcr[acr] != null) return teacherAcr[acr]!;
    if (acr.isNotEmpty) return s.initials;
    return courseInfo[s.code.toUpperCase()]?.teacher ?? '';
  }

  String nameFor(GridSlot s) {
    if (s.customName != null && s.customName!.isNotEmpty) return s.customName!;
    return courseInfo[s.code.toUpperCase()]?.name ?? '';
  }
}

/// One class a teacher takes (a routine cell attributed to their acronym).
class TeacherClass {
  final String day, time, code, courseName, batch, section, room, acr;
  const TeacherClass({
    required this.day,
    required this.time,
    required this.code,
    required this.courseName,
    required this.batch,
    required this.section,
    required this.room,
    required this.acr,
  });
}

/// Teacher list + each teacher's full weekly schedule, built from the routine.
class TeacherRoutineData {
  final List<({String acr, String name, int classes})>
  teachers; // with classes>0
  final Map<String, List<TeacherClass>> byTeacher; // acronym → classes
  const TeacherRoutineData(this.teachers, this.byTeacher);
}

class RoutineGridRepository {
  RoutineGridRepository._();
  static final instance = RoutineGridRepository._();

  static const _days = [
    'SATURDAY',
    'SUNDAY',
    'MONDAY',
    'TUESDAY',
    'WEDNESDAY',
    'THURSDAY',
    'FRIDAY',
  ];
  static const _fallbackId = '1H1IrP65R_Nz2LfJ7G3KP7pPQNIYMLvka';

  final _api = SheetsApi.instance;
  List<SheetTable>? _allDayTables; // index aligned with _days
  Map<String, CourseInfo> _courseInfo = {};
  Map<String, String> _teacherAcr = {};
  String _semester = '';
  List<({String batch, String section})> _available = [];
  bool _loaded = false; // session cache: skip re-fetching on repeat visits
  DateTime? _loadedAt;
  static const _cacheTtl = Duration(minutes: 5);

  /// Drop the cached routine so the next [load] re-fetches (pull-to-refresh).
  void invalidate() {
    _loaded = false;
    _loadedAt = null;
    _allDayTables = null;
    SheetsApi.instance.clearCache();
  }

  static String _normCode(String code) =>
      code.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  static int _timeToMin(String t) {
    final m = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(t);
    if (m == null) return 9999;
    var h = int.parse(m[1]!);
    final min = int.parse(m[2]!);
    if (h < 8) h += 12;
    return h * 60 + min;
  }

  static (String, String, String)? _parseCell(String cell) {
    final c = cell.trim();
    if (c.isEmpty || c == '--' || c == '–') return null;
    final parts = c.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length >= 3) {
      return (parts[0], parts[1], parts.sublist(2).join(' '));
    }
    if (parts.length == 2) return (parts[0], '', parts[1]);
    if (parts.length == 1) return (parts[0], '', '');
    return null;
  }

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

  /// Full load: maps, all day tables, available sections, and the 62/B grid.
  /// Cached for the session — a second visit (or batch/section switch) rebuilds
  /// instantly from the cached day tables instead of re-fetching the sheets.
  Future<RoutineGridData> load({
    String batch = '62',
    String section = 'B',
    List<CustomCourse> customs = const [],
  }) async {
    final cacheFresh =
        _loadedAt != null && DateTime.now().difference(_loadedAt!) < _cacheTtl;
    if (_loaded && cacheFresh && _allDayTables != null) {
      return buildFor(batch, section, customs: customs);
    }
    final ids = await _sheetIds();
    final fetched = await Future.wait([
      _api.sheet('CPG_Courses').catchError((_) => <List<String>>[]),
      _api.sheet('CPG_Teachers').catchError((_) => <List<String>>[]),
      _semesterLabel(),
      _fetchAllDays(ids),
    ]);
    final cpg = fetched[0] as List<List<String>>;
    final tch = fetched[1] as List<List<String>>;
    _semester = fetched[2] as String;
    _allDayTables = fetched[3] as List<SheetTable>;

    _courseInfo = {};
    for (final r in cpg) {
      if (r.length < 2) continue;
      final code = r[1].trim().toUpperCase();
      if (code.isEmpty ||
          ['code', 'title', 'course'].contains(r[1].trim().toLowerCase())) {
        continue;
      }
      _courseInfo[code] = CourseInfo(
        r[0].trim(),
        r.length > 4 ? r[4].trim() : '',
        r.length > 5 ? r[5].trim() : '',
      );
    }

    _teacherAcr = {};
    for (final r in tch) {
      if (r.length < 2) continue;
      final acr = r[0].trim().toUpperCase();
      if (acr.isEmpty ||
          ['acronym', 'initials', 'code'].contains(r[0].trim().toLowerCase())) {
        continue;
      }
      _teacherAcr[acr] = r[1].trim();
    }

    _available = _scanSections();
    _loaded = true;
    _loadedAt = DateTime.now();

    return buildFor(batch, section, customs: customs);
  }

  /// Build the grid for any batch/section from the cached day tables. Custom
  /// courses (62B only) are merged into the schedule before grouping so they
  /// appear in the grid.
  RoutineGridData buildFor(
    String batch,
    String section, {
    List<CustomCourse> customs = const [],
  }) {
    final built = _scheduleFor(batch, section);
    if (customs.isNotEmpty && batch == '62' && section == 'B') {
      for (final c in customs) {
        if (!_days.contains(c.day) || c.time.trim().isEmpty) continue;
        built.schedule
            .putIfAbsent(c.day, () => [])
            .add(
              GridSlot(
                time: c.time,
                code: c.code.isEmpty ? 'CUSTOM' : c.code,
                initials: c.teacher,
                room: c.room,
                customName: c.name,
                customId: c.id,
              ),
            );
      }
    }
    final groups = _timeframeGroups(built.schedule, built.dayTimeframes);
    return RoutineGridData(
      available: _available,
      courseInfo: _courseInfo,
      teacherAcr: _teacherAcr,
      semester: _semester,
      schedule: built.schedule,
      groups: groups,
      batch: batch,
      section: section,
    );
  }

  /// Resolve a student's retake/improve enrollments against the current master
  /// routine. Only the chosen batch/section/course identity is stored in
  /// Supabase; time, teacher and room are rebuilt here so later routine edits
  /// automatically flow into the student's personal 62B routine.
  Future<List<CustomCourse>> loadEnrollmentCourses(String studentId) async {
    try {
      await load();
      final rows = await Supa.client
          .from('student_retake_enrollments')
          .select('course_code,batch,section,type')
          .eq('student_id', studentId);
      final out = <CustomCourse>[];
      for (final raw in (rows as List).whereType<Map>()) {
        final code = (raw['course_code'] ?? '').toString().trim();
        final batch = (raw['batch'] ?? '').toString().trim();
        final section = (raw['section'] ?? '').toString().trim().toUpperCase();
        final type = (raw['type'] ?? 'retake').toString().trim().toLowerCase();
        if (code.isEmpty || batch.isEmpty || section.isEmpty) continue;
        final selected = _scheduleFor(batch, section).schedule;
        for (final entry in selected.entries) {
          for (final slot in entry.value) {
            if (slot.isBreak || _normCode(slot.code) != _normCode(code)) {
              continue;
            }
            out.add(
              CustomCourse(
                id: 'enrollment:$type:${_normCode(code)}:${entry.key}:${slot.time}',
                name: _courseInfo[slot.code.toUpperCase()]?.name ?? code,
                code: slot.code.isEmpty ? code : slot.code,
                teacher: slot.initials,
                room: slot.room,
                day: entry.key,
                time: slot.time,
              ),
            );
          }
        }
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<List<SheetTable>> _fetchAllDays(List<String> ids) async {
    // Fetch every (day, sheet) combination concurrently — sequential awaits made
    // this the slowest part of the routine load (7 days × N sheets in series).
    final futures = <Future<SheetTable?>>[];
    for (final day in _days) {
      for (final id in ids) {
        futures.add(
          _api
              .tableById(id, tab: day)
              .then<SheetTable?>((t) => t)
              .catchError((_) => null),
        );
      }
    }
    final results = await Future.wait(futures);

    final out = <SheetTable>[];
    var k = 0;
    for (var d = 0; d < _days.length; d++) {
      final tables = <SheetTable>[];
      for (var j = 0; j < ids.length; j++) {
        final t = results[k++];
        if (t != null) tables.add(t);
      }
      final valid = tables
          .where((t) => t.rows.isNotEmpty || t.cols.isNotEmpty)
          .toList();
      if (valid.isEmpty) {
        out.add(const SheetTable(cols: [], rows: []));
        continue;
      }
      final base = valid.reduce(
        (a, b) => b.cols.length > a.cols.length ? b : a,
      );
      out.add(
        SheetTable(cols: base.cols, rows: [for (final t in valid) ...t.rows]),
      );
    }
    return out;
  }

  List<({String batch, String section})> _scanSections() {
    final seen = <String>{};
    final combos = <({String batch, String section})>[];
    for (final table in _allDayTables ?? const <SheetTable>[]) {
      var dataStart = 0;
      final cols = table.cols.length > 3 ? table.cols.sublist(3) : <String>[];
      if (!cols.any((c) => RegExp(r'\d+:\d+').hasMatch(c))) {
        for (var r = 0; r < table.rows.length && r < 3; r++) {
          if (table.rows[r].length > 3 &&
              table.rows[r]
                  .sublist(3)
                  .any((c) => RegExp(r'\d+:\d+').hasMatch(c))) {
            dataStart = r + 1;
            break;
          }
        }
      }
      for (var r = dataStart; r < table.rows.length; r++) {
        final cells = table.rows[r];
        final batch = (cells.length > 1 ? cells[1].trim() : '').replaceAll(
          RegExp(r'\.0+$'),
          '',
        );
        final section = cells.length > 2 ? cells[2].trim().toUpperCase() : '';
        if (RegExp(r'^\d+$').hasMatch(batch) &&
            RegExp(r'^[A-Z]$').hasMatch(section)) {
          final key = '$batch-$section';
          if (seen.add(key)) combos.add((batch: batch, section: section));
        }
      }
    }
    combos.sort((a, b) {
      final bd = int.parse(b.batch) - int.parse(a.batch);
      return bd != 0 ? bd : a.section.compareTo(b.section);
    });
    return combos;
  }

  ({
    Map<String, List<GridSlot>> schedule,
    Map<String, List<String>> dayTimeframes,
  })
  _scheduleFor(String batch, String section) {
    final schedule = <String, List<GridSlot>>{};
    final dayTimeframes = <String, List<String>>{};
    final tables = _allDayTables ?? const <SheetTable>[];

    for (var d = 0; d < _days.length; d++) {
      final dayName = _days[d];
      if (d >= tables.length) continue;
      final table = tables[d];
      if (table.rows.isEmpty) continue;

      var timeSlots = table.cols.length > 3
          ? table.cols.sublist(3)
          : <String>[];
      var dataStart = 0;
      if (!timeSlots.any((t) => RegExp(r'\d+:\d+').hasMatch(t))) {
        for (var r = 0; r < table.rows.length && r < 3; r++) {
          final cells = table.rows[r];
          if (cells.length > 3 &&
              cells.sublist(3).any((c) => RegExp(r'\d+:\d+').hasMatch(c))) {
            timeSlots = cells.sublist(3);
            dataStart = r + 1;
            break;
          }
        }
      }
      if (timeSlots.isEmpty) continue;

      var breakIdx = -1;
      final targetRows = <List<String>>[];
      for (var r = dataStart; r < table.rows.length; r++) {
        final cells = table.rows[r];
        for (var i = 3; i < cells.length; i++) {
          if (cells[i].toUpperCase() == 'BREAK') breakIdx = i - 3;
        }
        final rb = (cells.length > 1 ? cells[1].trim() : '').replaceAll(
          RegExp(r'\.0+$'),
          '',
        );
        final rs = cells.length > 2 ? cells[2].trim().toUpperCase() : '';
        if (rb == batch && rs == section) targetRows.add(cells);
      }
      if (targetRows.isEmpty) continue;

      // Merge target rows: first non-empty, non-BREAK per column.
      String merged(int i) {
        for (final row in targetRows) {
          final ci = i + 3;
          final v = ci < row.length ? row[ci].trim() : '';
          if (v.isNotEmpty && v.toUpperCase() != 'BREAK') return v;
        }
        return '';
      }

      final daySchedule = <GridSlot>[];
      for (var i = 0; i < timeSlots.length; i++) {
        final time = timeSlots[i].trim();
        if (time.isEmpty) continue;
        if (i == breakIdx) {
          daySchedule.add(GridSlot(time: time, isBreak: true));
          continue;
        }
        final p = _parseCell(merged(i));
        if (p != null) {
          daySchedule.add(
            GridSlot(time: time, code: p.$1, initials: p.$2, room: p.$3),
          );
        }
      }
      if (daySchedule.any((s) => !s.isBreak)) {
        schedule[dayName] = daySchedule;
        dayTimeframes[dayName] = timeSlots
            .map((t) => t.trim())
            .where((t) => RegExp(r'\d+:\d+').hasMatch(t))
            .toList();
      }
    }
    return (schedule: schedule, dayTimeframes: dayTimeframes);
  }

  List<GridGroup> _timeframeGroups(
    Map<String, List<GridSlot>> schedule,
    Map<String, List<String>> dayTimeframes,
  ) {
    final daysWithClass = _days
        .where((d) => schedule[d]?.any((s) => !s.isBreak) ?? false)
        .toList();
    if (daysWithClass.isEmpty) return [];

    List<String> frameLabels(String day) =>
        (dayTimeframes[day]?.isNotEmpty ?? false)
        ? dayTimeframes[day]!
        : (schedule[day] ?? []).map((s) => s.time).toList();

    String sigFor(String day) {
      final keys =
          frameLabels(day)
              .where((t) => RegExp(r'\d+:\d+').hasMatch(t))
              .map(_timeToMin)
              .toSet()
              .toList()
            ..sort();
      return keys.join(',');
    }

    final order = <String>[];
    final bySig = <String, List<String>>{};
    for (final day in daysWithClass) {
      final sig = sigFor(day);
      if (!bySig.containsKey(sig)) {
        bySig[sig] = [];
        order.add(sig);
      }
      bySig[sig]!.add(day);
    }

    final groups = <GridGroup>[];
    for (final sig in order) {
      final days = bySig[sig]!;
      final labelFreq = <int, Map<String, int>>{};
      final breakKeys = <int>{};
      final classKeys = <int>{};
      final breakIntervals = <List<int>>[];

      void addLabel(String label) {
        if (label.isEmpty || !RegExp(r'\d+:\d+').hasMatch(label)) return;
        final k = _timeToMin(label);
        labelFreq.putIfAbsent(k, () => {});
        labelFreq[k]![label] = (labelFreq[k]![label] ?? 0) + 1;
      }

      for (final day in days) {
        for (final l in frameLabels(day)) {
          addLabel(l);
        }
      }
      for (final day in days) {
        for (final s in schedule[day] ?? <GridSlot>[]) {
          addLabel(s.time);
          final k = _timeToMin(s.time);
          if (s.isBreak) {
            breakKeys.add(k);
            final ts = RegExp(
              r'\d{1,2}:\d{2}',
            ).allMatches(s.time).map((m) => _timeToMin(m.group(0)!)).toList();
            if (ts.length >= 2) {
              breakIntervals.add([
                ts.reduce((a, b) => a < b ? a : b),
                ts.reduce((a, b) => a > b ? a : b),
              ]);
            }
          } else {
            classKeys.add(k);
          }
        }
      }
      if (classKeys.isEmpty) {
        groups.add(GridGroup(days, const [], <String>{}));
        continue;
      }

      final usedSet = {...classKeys, ...breakKeys};
      final frameKeys = labelFreq.keys.toSet().toList()..sort();
      final keyMap = <int, String>{};
      int? prev;
      for (final k in frameKeys) {
        if (!usedSet.contains(k)) {
          if (breakIntervals.any((iv) => k > iv[0] && k < iv[1])) continue;
          if (prev != null && (k - prev) > 120) continue;
        }
        final best =
            (labelFreq[k]!.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value)))
                .first
                .key;
        keyMap[k] = best;
        prev = k;
      }
      final sortedKeys = keyMap.keys.toList()..sort();
      final allTimes = sortedKeys.map((k) => keyMap[k]!).toList();
      final breakTimes = sortedKeys
          .where(breakKeys.contains)
          .map((k) => keyMap[k]!)
          .toSet();
      // Canonicalise slot times so cells align with the headers.
      for (final day in days) {
        for (final s in schedule[day] ?? <GridSlot>[]) {
          s.time = keyMap[_timeToMin(s.time)] ?? s.time;
        }
      }
      groups.add(GridGroup(days, allTimes, breakTimes));
    }
    return groups;
  }

  /// Scan the cached routine (all sections, all days) and group every class by
  /// the teacher acronym in its cell → a per-teacher weekly routine. Reuses the
  /// session-cached day tables, so it's instant after the first routine load.
  Future<TeacherRoutineData> loadTeacherRoutine({
    String batch = '62',
    String section = 'B',
  }) async {
    await load(batch: batch, section: section); // ensures caches are populated
    final tables = _allDayTables ?? const <SheetTable>[];
    final byTeacher = <String, List<TeacherClass>>{};
    final seen = <String>{}; // dedupe acr|day|time|code|batch|section

    for (var d = 0; d < _days.length && d < tables.length; d++) {
      final table = tables[d];
      final dayName = _days[d];
      if (table.rows.isEmpty) continue;

      var timeSlots = table.cols.length > 3
          ? table.cols.sublist(3)
          : <String>[];
      var dataStart = 0;
      if (!timeSlots.any((t) => RegExp(r'\d+:\d+').hasMatch(t))) {
        for (var r = 0; r < table.rows.length && r < 3; r++) {
          final cells = table.rows[r];
          if (cells.length > 3 &&
              cells.sublist(3).any((c) => RegExp(r'\d+:\d+').hasMatch(c))) {
            timeSlots = cells.sublist(3);
            dataStart = r + 1;
            break;
          }
        }
      }
      if (timeSlots.isEmpty) continue;

      for (var r = dataStart; r < table.rows.length; r++) {
        final cells = table.rows[r];
        final rb = (cells.length > 1 ? cells[1].trim() : '').replaceAll(
          RegExp(r'\.0+$'),
          '',
        );
        final rs = cells.length > 2 ? cells[2].trim().toUpperCase() : '';
        if (rb.isEmpty || rs.isEmpty) continue;
        for (var i = 0; i < timeSlots.length; i++) {
          final time = timeSlots[i].trim();
          if (time.isEmpty || !RegExp(r'\d+:\d+').hasMatch(time)) continue;
          final ci = i + 3;
          final cell = ci < cells.length ? cells[ci].trim() : '';
          if (cell.isEmpty || cell.toUpperCase() == 'BREAK') continue;
          final p = _parseCell(cell);
          if (p == null) continue;
          final acr = p.$2.trim().toUpperCase();
          if (acr.isEmpty) continue;
          final code = p.$1.toUpperCase();
          final key = '$acr|$dayName|$time|$code|$rb|$rs';
          if (!seen.add(key)) continue;
          byTeacher
              .putIfAbsent(acr, () => [])
              .add(
                TeacherClass(
                  day: dayName,
                  time: time,
                  code: code,
                  courseName: _courseInfo[code]?.name ?? '',
                  batch: rb,
                  section: rs,
                  room: p.$3,
                  acr: acr,
                ),
              );
        }
      }
    }

    // Sort each teacher's classes by day order then time.
    for (final list in byTeacher.values) {
      list.sort((a, b) {
        final dc = _days.indexOf(a.day).compareTo(_days.indexOf(b.day));
        return dc != 0 ? dc : _timeToMin(a.time).compareTo(_timeToMin(b.time));
      });
    }

    final teachers =
        byTeacher.keys
            .map(
              (a) => (
                acr: a,
                name: _teacherAcr[a] ?? a,
                classes: byTeacher[a]!.length,
              ),
            )
            .toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
    return TeacherRoutineData(teachers, byTeacher);
  }

  Future<String> _semesterLabel() async {
    try {
      final rows = await _api.sheet('Semester');
      final first = rows.isNotEmpty && rows[0].isNotEmpty
          ? rows[0][0].toLowerCase().trim()
          : '';
      final start = first == 'semester' ? 1 : 0;
      for (var i = start; i < rows.length; i++) {
        final v = rows[i].isNotEmpty ? rows[i][0].trim() : '';
        if (v.isNotEmpty) return v;
      }
    } catch (_) {}
    return 'Current Semester';
  }

  // ── Excluded courses (My Courses) ──
  Future<Set<String>> loadExcluded(String studentId) async {
    try {
      final rows = await Supa.client
          .from('student_manual_courses')
          .select('excluded_courses')
          .eq('student_id', studentId)
          .limit(1);
      if (rows.isNotEmpty) {
        final v = (rows.first as Map)['excluded_courses'];
        if (v is List) return v.map((e) => e.toString().toUpperCase()).toSet();
      }
    } catch (_) {}
    return {};
  }

  Future<void> saveExcluded(String studentId, Iterable<String> excluded) async {
    try {
      await Supa.client.from('student_manual_courses').upsert({
        'student_id': studentId,
        'excluded_courses': excluded.toList(),
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }

  // ── Custom courses (user-added entries on the 62B routine) ──
  Future<List<CustomCourse>> loadCustomCourses(String studentId) async {
    try {
      final rows = await Supa.client
          .from('student_custom_courses')
          .select('courses')
          .eq('student_id', studentId)
          .limit(1);
      if (rows.isNotEmpty) {
        final v = (rows.first as Map)['courses'];
        if (v is List) {
          return v
              .whereType<Map>()
              .map((m) => CustomCourse.fromJson(m.cast<String, dynamic>()))
              .toList();
        }
      }
    } catch (_) {}
    return [];
  }

  Future<void> saveCustomCourses(
    String studentId,
    List<CustomCourse> courses,
  ) async {
    try {
      await Supa.client.from('student_custom_courses').upsert({
        'student_id': studentId,
        'courses': courses.map((c) => c.toJson()).toList(),
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }
}
