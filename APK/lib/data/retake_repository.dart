import '../core/sheets_api.dart';
import '../core/supa.dart';
import '../core/worker_api.dart';
import 'routine_grid_repository.dart';
import 'routine_repository.dart';

/// One slot of a course in some section's routine.
class RetakeSlot {
  final String day;
  final String time;
  final String initials;
  final String room;
  const RetakeSlot(this.day, this.time, this.initials, this.room);
}

/// A section offering a given course, with clash info vs the 62B routine.
class RetakeSection {
  final String batch;
  final String section;
  final List<RetakeSlot> slots;
  final bool hasConflict;
  final List<String> clashCourses;
  final String initials;
  const RetakeSection({
    required this.batch,
    required this.section,
    required this.slots,
    required this.hasConflict,
    required this.clashCourses,
    required this.initials,
  });
}

/// Everything the Retake & Improve screen needs.
class RetakeData {
  final Set<String> apiRetake;
  final Set<String> apiImprove;
  Set<String> manualRetake;
  Set<String> manualImprove;
  final Map<String, String> courseNameMap; // normCode → title
  final Map<String, double> creditMap; // normCode → credit
  final Map<String, Map<String, List<RetakeSlot>>>
  sectionCourseSlots; // "batch-section" → code → slots
  final Map<String, Map<String, String>> busy62B; // day → time → code
  final bool resultLive;

  RetakeData({
    required this.apiRetake,
    required this.apiImprove,
    required this.manualRetake,
    required this.manualImprove,
    required this.courseNameMap,
    required this.creditMap,
    required this.sectionCourseSlots,
    required this.busy62B,
    required this.resultLive,
  });

  List<String> get retakeList =>
      ({...apiRetake, ...manualRetake}.toList()..sort());
  List<String> get improveList =>
      ({...apiImprove, ...manualImprove}.toList()..sort());

  /// The student's off days — routine days with NO regular 62B class. Taking a
  /// retake/improve class on one of these is ideal (a free day, no clash).
  /// Mirrors the website's `offDays` set.
  Set<String> get offDays => {
    for (final d in RoutineRepository.days)
      if ((busy62B[d]?.isEmpty ?? true)) d,
  };

  bool isApi(String code, bool retake) =>
      (retake ? apiRetake : apiImprove).contains(code.toUpperCase());
  bool isManual(String code, bool retake) =>
      (retake ? manualRetake : manualImprove).contains(code.toUpperCase());

  /// All sections that offer [code], with clash detection vs the 62B routine.
  List<RetakeSection> sectionsFor(String code) {
    final codeUp = code.toUpperCase();
    final out = <RetakeSection>[];
    sectionCourseSlots.forEach((key, courses) {
      final slots = courses[codeUp];
      if (slots == null || slots.isEmpty) return;
      final dash = key.indexOf('-');
      final batch = key.substring(0, dash);
      final section = key.substring(dash + 1);

      final clashSlots = slots.where((s) {
        final busy = busy62B[s.day]?[s.time];
        return busy != null && busy != codeUp;
      }).toList();
      final clashCourses = <String>{
        for (final s in clashSlots)
          courseNameMap[busy62B[s.day]?[s.time]] ??
              (busy62B[s.day]?[s.time] ?? ''),
      }..removeWhere((e) => e.isEmpty);

      final initCount = <String, int>{};
      for (final s in slots) {
        if (s.initials.isNotEmpty) {
          initCount[s.initials] = (initCount[s.initials] ?? 0) + 1;
        }
      }
      final initials = initCount.isEmpty
          ? ''
          : (initCount.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value)))
                .first
                .key;

      out.add(
        RetakeSection(
          batch: batch,
          section: section,
          slots: slots,
          hasConflict: clashSlots.isNotEmpty,
          clashCourses: clashCourses.toList(),
          initials: initials,
        ),
      );
    });
    out.sort((a, b) {
      if (a.hasConflict != b.hasConflict) return a.hasConflict ? 1 : -1;
      if (a.batch != b.batch) return a.batch.compareTo(b.batch);
      return a.section.compareTo(b.section);
    });
    return out;
  }

  /// Course codes for the autocomplete/search (code → title).
  Map<String, String> get allCourses => courseNameMap;
}

/// One enrollment row from `student_retake_enrollments` (Profile → My Courses /
/// the website's My List & Classmates tabs).
class RetakeEnrollment {
  final String studentId,
      studentName,
      courseCode,
      courseName,
      batch,
      section,
      teacher,
      type;
  const RetakeEnrollment({
    required this.studentId,
    required this.studentName,
    required this.courseCode,
    required this.courseName,
    required this.batch,
    required this.section,
    required this.teacher,
    required this.type,
  });

  static RetakeEnrollment fromRow(Map row) => RetakeEnrollment(
    studentId: (row['student_id'] ?? '').toString(),
    studentName: (row['student_name'] ?? '').toString(),
    courseCode: (row['course_code'] ?? '').toString(),
    courseName: (row['course_name'] ?? '').toString(),
    batch: (row['batch'] ?? '').toString(),
    section: (row['section'] ?? '').toString(),
    teacher: (row['teacher'] ?? '').toString(),
    type: (row['type'] ?? 'retake').toString(),
  );

  RetakeEnrollment withFreshInfo({
    required String freshName,
    required String freshTeacher,
  }) => RetakeEnrollment(
    studentId: studentId,
    studentName: studentName,
    courseCode: courseCode,
    courseName: freshName.isEmpty ? courseName : freshName,
    batch: batch,
    section: section,
    teacher: freshTeacher.isEmpty ? teacher : freshTeacher,
    type: type,
  );
}

class RetakeRepository {
  RetakeRepository._();
  static final instance = RetakeRepository._();

  final _api = SheetsApi.instance;

  // Session caches for the heavy, student-independent fetches (all-section
  // routine + course maps) so repeat visits to Retake/Improve are instant.
  Future<_Routine>? _routineCache;
  Future<_Maps>? _mapsCache;
  DateTime? _routineCachedAt;
  DateTime? _mapsCachedAt;
  static const _cacheTtl = Duration(minutes: 5);

  static const _gradeOrder = [
    'F',
    'D',
    'C',
    'C+',
    'B-',
    'B',
    'B+',
    'A-',
    'A',
    'A+',
  ];
  static const _improveGrades = {'B-', 'C+', 'C', 'D'};

  static int _gradeRank(String g) => _gradeOrder.indexOf(g.trim());

  /// Public canonical course-code form ("GED 1262" → "GED-1262").
  static String norm(String c) => _normCode(c);

  static String _normCode(String c) {
    final s = c.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final m = RegExp(r'^([A-Z]+)(\d.*)$').firstMatch(s);
    return m != null ? '${m.group(1)}-${m.group(2)}' : s;
  }

  /// Re-fetch the cached routine/maps on the next load (used by pull-to-refresh).
  void invalidateCache() {
    _routineCache = null;
    _mapsCache = null;
    _routineCachedAt = null;
    _mapsCachedAt = null;
    RoutineGridRepository.instance.invalidate();
    SheetsApi.instance.clearCache();
    WorkerApi.instance.clearResultCache();
  }

  Future<_Routine> _freshRoutine() {
    final stale =
        _routineCachedAt == null ||
        DateTime.now().difference(_routineCachedAt!) >= _cacheTtl;
    if (_routineCache == null || stale) {
      _routineCachedAt = DateTime.now();
      _routineCache = _buildRoutine();
    }
    return _routineCache!;
  }

  Future<_Maps> _freshMaps() {
    final stale =
        _mapsCachedAt == null ||
        DateTime.now().difference(_mapsCachedAt!) >= _cacheTtl;
    if (_mapsCache == null || stale) {
      _mapsCachedAt = DateTime.now();
      _mapsCache = _courseMaps();
    }
    return _mapsCache!;
  }

  Future<RetakeData> load(String? studentId, String? dob) async {
    final results = await Future.wait([
      _bucketFromResult(studentId, dob),
      _freshRoutine(),
      _freshMaps(),
      _loadManual(studentId),
    ]);
    final graded = results[0] as _Graded;
    final routine = results[1] as _Routine;
    final maps = results[2] as _Maps;
    final manual = results[3] as _Manual;

    // API name/credit fill gaps in the sheet maps.
    graded.nameMap.forEach((k, v) {
      if (v.isNotEmpty) maps.names.putIfAbsent(k, () => v);
    });
    graded.creditMap.forEach((k, v) {
      if (v > 0 && !((maps.credits[k] ?? 0) > 0)) maps.credits[k] = v;
    });

    // Drop manually-saved courses that are now passed (best grade ≥ B).
    var manualRetake = manual.retake;
    var manualImprove = manual.improve;
    if (graded.live && graded.resolved.isNotEmpty) {
      manualRetake = manualRetake
          .where((c) => !graded.resolved.contains(_normCode(c)))
          .toSet();
      manualImprove = manualImprove
          .where((c) => !graded.resolved.contains(_normCode(c)))
          .toSet();
    }

    return RetakeData(
      apiRetake: graded.retake,
      apiImprove: graded.improve,
      manualRetake: manualRetake,
      manualImprove: manualImprove,
      courseNameMap: maps.names,
      creditMap: maps.credits,
      sectionCourseSlots: routine.sectionCourseSlots,
      busy62B: routine.busy62B,
      resultLive: graded.live,
    );
  }

  /// Persist the manual lists to Supabase (best-effort).
  Future<void> saveManual(
    String studentId,
    Iterable<String> retake,
    Iterable<String> improve,
  ) async {
    try {
      await Supa.client.from('student_manual_courses').upsert({
        'student_id': studentId,
        'retake': retake.toList(),
        'improve': improve.toList(),
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }

  // ── Enrollments (student_retake_enrollments) → My List & Classmates ──
  static const _enrollCols =
      'student_id,student_name,course_code,course_name,batch,section,teacher,type';

  Future<List<RetakeEnrollment>> myEnrollments(String studentId) async {
    try {
      final rows = await Supa.client
          .from('student_retake_enrollments')
          .select(_enrollCols)
          .eq('student_id', studentId);
      return _refreshEnrollmentInfo(
        (rows as List).map((r) => RetakeEnrollment.fromRow(r as Map)).toList(),
      );
    } catch (_) {
      return [];
    }
  }

  Future<List<RetakeEnrollment>> allEnrollments() async {
    try {
      final rows = await Supa.client
          .from('student_retake_enrollments')
          .select(_enrollCols);
      return _refreshEnrollmentInfo(
        (rows as List).map((r) => RetakeEnrollment.fromRow(r as Map)).toList(),
      );
    } catch (_) {
      return [];
    }
  }

  Future<List<RetakeEnrollment>> _refreshEnrollmentInfo(
    List<RetakeEnrollment> enrollments,
  ) async {
    if (enrollments.isEmpty) return enrollments;
    final routine = await _freshRoutine();
    final maps = await _freshMaps();
    return enrollments.map((e) {
      final key = '${e.batch}-${e.section.toUpperCase()}';
      final slots =
          routine.sectionCourseSlots[key]?[_normCode(e.courseCode)] ??
          const <RetakeSlot>[];
      final counts = <String, int>{};
      for (final slot in slots) {
        if (slot.initials.isNotEmpty) {
          counts[slot.initials] = (counts[slot.initials] ?? 0) + 1;
        }
      }
      final teacher = counts.isEmpty
          ? ''
          : (counts.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value)))
                .first
                .key;
      return e.withFreshInfo(
        freshName: maps.names[_normCode(e.courseCode)] ?? '',
        freshTeacher: teacher,
      );
    }).toList();
  }

  /// Enroll in (or move to) a section for a course. Replaces any existing
  /// enrollment for the same course (one section per course), like the site.
  Future<bool> enroll({
    required String studentId,
    required String studentName,
    required String courseCode,
    required String courseName,
    required String batch,
    required String section,
    required String teacher,
    required String type,
  }) async {
    try {
      await Supa.client
          .from('student_retake_enrollments')
          .delete()
          .eq('student_id', studentId)
          .eq('course_code', courseCode);
      await Supa.client.from('student_retake_enrollments').insert({
        'student_id': studentId,
        'student_name': studentName,
        'course_code': courseCode,
        'course_name': courseName,
        'batch': batch,
        'section': section,
        'teacher': teacher,
        'type': type,
        'enrolled_at': DateTime.now().toIso8601String(),
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> unenroll(String studentId, String courseCode) async {
    try {
      await Supa.client
          .from('student_retake_enrollments')
          .delete()
          .eq('student_id', studentId)
          .eq('course_code', courseCode);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Results → best-grade buckets ──
  Future<_Graded> _bucketFromResult(String? id, String? dob) async {
    if (id == null || dob == null || dob.isEmpty) {
      return _Graded({}, {}, {}, {}, {}, false);
    }
    try {
      final raw = await WorkerApi.instance.result(id, dob);
      if (raw['success'] != true) return _Graded({}, {}, {}, {}, {}, false);
      final best = <String, int>{}; // code → rank
      final bestGrade = <String, String>{};
      final nameMap = <String, String>{};
      final creditMap = <String, double>{};
      final results = (raw['results'] as Map?) ?? const {};
      for (final yv in results.values) {
        final sems = yv is List
            ? yv
            : (yv is Map ? yv.values.toList() : const []);
        for (final sem in sems) {
          if (sem is! Map) continue;
          for (final c
              in ((sem['courses'] as List?) ?? const []).whereType<Map>()) {
            final code = _normCode((c['course_code'] ?? '').toString());
            final grade = (c['grade'] ?? '').toString().trim();
            final rank = _gradeRank(grade);
            if (code.isEmpty || rank < 0) continue;
            if (!best.containsKey(code) || rank > best[code]!) {
              best[code] = rank;
              bestGrade[code] = grade;
            }
            final title = (c['course_title'] ?? '').toString().trim();
            if (title.isNotEmpty) nameMap.putIfAbsent(code, () => title);
            final cr = double.tryParse('${c['credit']}') ?? 0;
            if (cr > 0 && cr > (creditMap[code] ?? 0)) creditMap[code] = cr;
          }
        }
      }
      final retake = <String>{}, improve = <String>{}, resolved = <String>{};
      bestGrade.forEach((code, grade) {
        if (grade == 'F') {
          retake.add(code);
        } else if (_improveGrades.contains(grade)) {
          improve.add(code);
        } else if (_gradeRank(grade) >= _gradeRank('B')) {
          resolved.add(code);
        }
      });
      return _Graded(retake, improve, resolved, nameMap, creditMap, true);
    } catch (_) {
      return _Graded({}, {}, {}, {}, {}, false);
    }
  }

  // ── All-section routine + 62B busy map ──
  Future<_Routine> _buildRoutine() async {
    try {
      return await _buildRoutineFromGrid();
    } catch (_) {
      return _buildRoutineLegacy();
    }
  }

  /// Build retake choices from the same parsed routine used everywhere else.
  /// This keeps room, teacher and time changes consistent across every screen.
  Future<_Routine> _buildRoutineFromGrid() async {
    final sectionCourseSlots = <String, Map<String, List<RetakeSlot>>>{};
    final busy62B = <String, Map<String, String>>{};
    final repo = RoutineGridRepository.instance;
    final root = await repo.load();
    final sections = {...root.available, (batch: '62', section: 'B')};
    for (final selected in sections) {
      final data = repo.buildFor(selected.batch, selected.section);
      final key = '${selected.batch}-${selected.section}';
      for (final day in data.schedule.entries) {
        for (final slot in day.value) {
          if (slot.isBreak || slot.code.isEmpty) continue;
          final code = _normCode(slot.code);
          sectionCourseSlots.putIfAbsent(key, () => {});
          final list = sectionCourseSlots[key]!.putIfAbsent(code, () => []);
          if (!list.any((s) => s.day == day.key && s.time == slot.time)) {
            list.add(RetakeSlot(day.key, slot.time, slot.initials, slot.room));
          }
          if (selected.batch == '62' && selected.section == 'B') {
            busy62B.putIfAbsent(day.key, () => {});
            busy62B[day.key]![slot.time] = code;
          }
        }
      }
    }
    return _Routine(sectionCourseSlots, busy62B);
  }

  Future<_Routine> _buildRoutineLegacy() async {
    final sectionCourseSlots = <String, Map<String, List<RetakeSlot>>>{};
    final busy62B = <String, Map<String, String>>{};
    final ids = await _routineSheetIds();

    for (final day in RoutineRepository.days) {
      final tables = <SheetTable>[];
      for (final id in ids) {
        try {
          tables.add(await _api.tableById(id, tab: day));
        } catch (_) {}
      }
      if (tables.isEmpty) continue;
      // Merge: base cols from widest table, concat all rows.
      final valid = tables
          .where((t) => t.rows.isNotEmpty || t.cols.isNotEmpty)
          .toList();
      if (valid.isEmpty) continue;
      final base = valid.reduce(
        (a, b) => b.cols.length > a.cols.length ? b : a,
      );
      final rows = <List<String>>[for (final t in valid) ...t.rows];

      var timeSlots = base.cols.length > 3 ? base.cols.sublist(3) : <String>[];
      var dataStart = 0;
      if (!timeSlots.any((s) => RegExp(r'\d+:\d+').hasMatch(s))) {
        for (var r = 0; r < rows.length && r < 3; r++) {
          final cells = rows[r];
          if (cells.length > 3 &&
              cells.sublist(3).any((c) => RegExp(r'\d+:\d+').hasMatch(c))) {
            timeSlots = cells.sublist(3);
            dataStart = r + 1;
            break;
          }
        }
      }
      if (timeSlots.isEmpty) continue;

      for (var r = dataStart; r < rows.length; r++) {
        final cells = rows[r];
        final batch = cells.length > 1
            ? cells[1].replaceAll(RegExp(r'\.0+$'), '').trim()
            : '';
        final section = cells.length > 2 ? cells[2].trim().toUpperCase() : '';
        if (batch.isEmpty || section.isEmpty) continue;
        final key = '$batch-$section';

        for (var i = 0; i < timeSlots.length; i++) {
          final time = timeSlots[i].trim();
          if (time.isEmpty || !RegExp(r'\d+:\d+').hasMatch(time)) continue;
          final ci = i + 3;
          final cell = ci < cells.length ? cells[ci].trim() : '';
          if (cell.isEmpty ||
              RegExp(r'break', caseSensitive: false).hasMatch(cell)) {
            continue;
          }
          final parsed = _parseCell(cell);
          if (parsed == null) continue;
          final code = _normCode(parsed.$1);

          sectionCourseSlots.putIfAbsent(key, () => {});
          final list = sectionCourseSlots[key]!.putIfAbsent(code, () => []);
          if (!list.any((s) => s.day == day && s.time == time)) {
            list.add(RetakeSlot(day, time, parsed.$2, parsed.$3));
          }

          if (batch == '62' && section == 'B') {
            busy62B.putIfAbsent(day, () => {});
            busy62B[day]![time] = code;
          }
        }
      }
    }
    return _Routine(sectionCourseSlots, busy62B);
  }

  Future<List<String>> _routineSheetIds() async {
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
    return const ['1H1IrP65R_Nz2LfJ7G3KP7pPQNIYMLvka'];
  }

  (String, String, String)? _parseCell(String cell) {
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

  // ── Course name + credit maps (CPG_Courses + LU_Course_Offer) ──
  Future<_Maps> _courseMaps() async {
    final names = <String, String>{};
    final credits = <String, double>{};
    final res = await Future.wait([
      _api.sheet('CPG_Courses').catchError((_) => <List<String>>[]),
      _api.sheet('LU_Course_Offer').catchError((_) => <List<String>>[]),
    ]);
    // CPG_Courses: title col0, code col1
    for (final r in res[0]) {
      if (r.length < 2) continue;
      final title = r[0].trim();
      final code = _normCode(r[1].trim());
      if (code.isEmpty ||
          ['code', 'title', 'course'].contains(r[1].trim().toLowerCase())) {
        continue;
      }
      if (title.isNotEmpty) names[code] = title;
    }
    // LU_Course_Offer: code col1, title col2, credit col3
    for (final r in res[1]) {
      if (r.length < 2) continue;
      final first = r[0].trim().toLowerCase();
      if (first == 'batch' || first == 'semester') continue;
      final code = _normCode(r[1].trim());
      if (code.isEmpty) continue;
      final title = r.length > 2 ? r[2].trim() : '';
      if (title.isNotEmpty) names[code] = title;
      final double cr = r.length > 3
          ? (double.tryParse(r[3].trim()) ?? 0.0)
          : 0.0;
      if (cr > 0) credits[code] = cr;
    }
    return _Maps(names, credits);
  }

  // ── Manual courses from Supabase ──
  Future<_Manual> _loadManual(String? id) async {
    if (id == null) return _Manual({}, {});
    try {
      final rows = await Supa.client
          .from('student_manual_courses')
          .select('retake,improve')
          .eq('student_id', id)
          .limit(1);
      if (rows.isNotEmpty) {
        final row = rows.first as Map;
        Set<String> toSet(Object? v) => v is List
            ? v.map((e) => e.toString().toUpperCase()).toSet()
            : <String>{};
        return _Manual(toSet(row['retake']), toSet(row['improve']));
      }
    } catch (_) {}
    return _Manual({}, {});
  }
}

class _Graded {
  final Set<String> retake, improve, resolved;
  final Map<String, String> nameMap;
  final Map<String, double> creditMap;
  final bool live;
  _Graded(
    this.retake,
    this.improve,
    this.resolved,
    this.nameMap,
    this.creditMap,
    this.live,
  );
}

class _Routine {
  final Map<String, Map<String, List<RetakeSlot>>> sectionCourseSlots;
  final Map<String, Map<String, String>> busy62B;
  _Routine(this.sectionCourseSlots, this.busy62B);
}

class _Maps {
  final Map<String, String> names;
  final Map<String, double> credits;
  _Maps(this.names, this.credits);
}

class _Manual {
  final Set<String> retake, improve;
  _Manual(this.retake, this.improve);
}
