import '../core/sheets_api.dart';
import '../core/supa.dart';

class ExamItem {
  final String course;
  final String courseName; // from CPG_Courses (code → title)
  final String date; // dd-mm-yyyy (normalized)
  final String time;
  final String weekday;
  final String dayLabel; // e.g. "Day-1"
  final DateTime? dateObj;
  final String source; // '' / '62b' / 'retake' / 'improve'
  final String enrolledBatch;
  final String enrolledSection;
  const ExamItem({
    required this.course,
    this.courseName = '',
    required this.date,
    required this.time,
    required this.weekday,
    this.dayLabel = '',
    this.dateObj,
    this.source = '',
    this.enrolledBatch = '',
    this.enrolledSection = '',
  });

  ExamItem copyWith({
    String? courseName,
    String? source,
    String? enrolledBatch,
    String? enrolledSection,
  }) => ExamItem(
    course: course,
    courseName: courseName ?? this.courseName,
    date: date,
    time: time,
    weekday: weekday,
    dayLabel: dayLabel,
    dateObj: dateObj,
    source: source ?? this.source,
    enrolledBatch: enrolledBatch ?? this.enrolledBatch,
    enrolledSection: enrolledSection ?? this.enrolledSection,
  );
}

class TodayExamItem {
  final ExamItem exam;
  final String type;

  const TodayExamItem({required this.exam, required this.type});
}

class _ExamEnrollment {
  final String courseCode, courseName, batch, section, type;
  const _ExamEnrollment(
    this.courseCode,
    this.courseName,
    this.batch,
    this.section,
    this.type,
  );
}

/// Parses the mid/final term exam routine. Unlike the class routine, the exam
/// sheet is a single transposed block: header rows give Day-N / date / time /
/// weekday per column, then each (batch, section) row holds the exam cell for
/// every day column. Mirrors exam.js.
class ExamRepository {
  ExamRepository._();
  static final instance = ExamRepository._();

  final _api = SheetsApi.instance;

  Future<List<String>> _ids(String keyword) async {
    try {
      final rows = await _api.sheet('Routine');
      for (final row in rows) {
        if (row.isEmpty) continue;
        if (!row[0].toLowerCase().contains(keyword.toLowerCase())) continue;
        final ids = <String>[];
        for (final cell in row) {
          final m = RegExp(r'spreadsheets/d/([a-zA-Z0-9_-]+)').firstMatch(cell);
          if (m != null && !ids.contains(m.group(1))) ids.add(m.group(1)!);
        }
        return ids;
      }
    } catch (_) {}
    return const [];
  }

  Map<String, String>? _titles;

  Future<Map<String, String>> _courseTitles() async {
    if (_titles != null) return _titles!;
    final map = <String, String>{};
    try {
      final rows = await _api.sheet('CPG_Courses');
      for (final r in rows) {
        if (r.length < 2) continue;
        final code = r[1].trim().toUpperCase();
        final title = r[0].trim();
        if (code.isEmpty ||
            ['code', 'title', 'course'].contains(r[1].trim().toLowerCase())) {
          continue;
        }
        if (title.isNotEmpty) map[code] = title;
      }
    } catch (_) {}
    return _titles = map;
  }

  /// [type] is 'mid' or 'final'.
  Future<List<ExamItem>> load(
    String type, {
    String batch = '62',
    String section = 'B',
  }) async {
    final loaded = await _loadRowsAndTitles(type);
    final allRows = loaded.rows;
    final titles = loaded.titles;
    if (allRows.isEmpty) return const [];
    return _parse(allRows, batch, section, titles);
  }

  /// Exams scheduled on today's exact date. Gap days intentionally return an
  /// empty list so regular routine and bus data remain active between exams.
  Future<List<TodayExamItem>> loadToday({
    String batch = '62',
    String section = 'B',
  }) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final loaded = await Future.wait([
      load(
        'mid',
        batch: batch,
        section: section,
      ).catchError((_) => const <ExamItem>[]),
      load(
        'final',
        batch: batch,
        section: section,
      ).catchError((_) => const <ExamItem>[]),
    ]);
    final result = <TodayExamItem>[];
    for (var i = 0; i < loaded.length; i++) {
      for (final item in loaded[i]) {
        final d = item.dateObj;
        final isToday =
            d != null &&
            d.year == today.year &&
            d.month == today.month &&
            d.day == today.day;
        if (isToday) {
          result.add(
            TodayExamItem(exam: item, type: i == 0 ? 'Mid Term' : 'Final Term'),
          );
        }
      }
    }
    result.sort(
      (a, b) =>
          _parseTimeMins(a.exam.time).compareTo(_parseTimeMins(b.exam.time)),
    );
    return result;
  }

  /// True only on exact exam dates for the given batch/section.
  Future<bool> hasExamToday({String batch = '62', String section = 'B'}) async {
    return (await loadToday(batch: batch, section: section)).isNotEmpty;
  }

  Future<List<ExamItem>> loadMine(String type, String studentId) async {
    final loaded = await _loadRowsAndTitles(type);
    final allRows = loaded.rows;
    final titles = loaded.titles;
    if (allRows.isEmpty) return const [];

    final out = <ExamItem>[];
    final seen = <String>{};
    void add(ExamItem e) {
      final key = [
        _normCourse(e.course),
        e.date,
        e.time,
        e.source,
        e.enrolledBatch,
        e.enrolledSection,
      ].join('|');
      if (seen.add(key)) out.add(e);
    }

    for (final e in _parse(allRows, '62', 'B', titles)) {
      add(e.copyWith(source: '62b'));
    }

    final enrollments = await _enrollments(studentId);
    final parsedBySection = <String, List<ExamItem>>{};
    for (final enr in enrollments) {
      if (enr.batch.isEmpty || enr.section.isEmpty || enr.courseCode.isEmpty) {
        continue;
      }
      final key = '${enr.batch}-${enr.section.toUpperCase()}';
      final sectionItems = parsedBySection.putIfAbsent(
        key,
        () => _parse(allRows, enr.batch, enr.section, titles),
      );
      final target = _normCourse(enr.courseCode);
      for (final e in sectionItems) {
        if (_normCourse(e.course) != target) continue;
        add(
          e.copyWith(
            courseName: e.courseName.isNotEmpty ? e.courseName : enr.courseName,
            source: enr.type.toLowerCase().contains('improve')
                ? 'improve'
                : 'retake',
            enrolledBatch: enr.batch,
            enrolledSection: enr.section,
          ),
        );
      }
    }

    out.sort((a, b) {
      final ad = _examDateTime(a);
      final bd = _examDateTime(b);
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return ad.compareTo(bd);
    });
    return out;
  }

  Future<({List<List<String>> rows, Map<String, String> titles})>
  _loadRowsAndTitles(String type) async {
    final keyword = type == 'final' ? 'final term' : 'mid term';
    final res = await Future.wait([_ids(keyword), _courseTitles()]);
    final ids = res[0] as List<String>;
    final titles = res[1] as Map<String, String>;
    if (ids.isEmpty) return (rows: const <List<String>>[], titles: titles);

    final allRows = <List<String>>[];
    for (final id in ids) {
      try {
        final t = await _api.tableById(id, raw: true);
        allRows.addAll(t.rows);
      } catch (_) {}
    }
    return (rows: allRows, titles: titles);
  }

  Future<List<_ExamEnrollment>> _enrollments(String studentId) async {
    try {
      final rows = await Supa.client
          .from('student_retake_enrollments')
          .select('course_code,course_name,batch,section,type')
          .eq('student_id', studentId);
      return (rows as List)
          .map(
            (r) => _ExamEnrollment(
              (r['course_code'] ?? '').toString(),
              (r['course_name'] ?? '').toString(),
              (r['batch'] ?? '').toString(),
              (r['section'] ?? '').toString(),
              (r['type'] ?? 'retake').toString(),
            ),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static String _normCourse(String c) {
    final s = c.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final m = RegExp(r'^([A-Z]+)(\d.*)$').firstMatch(s);
    return m != null ? '${m.group(1)}-${m.group(2)}' : s;
  }

  List<ExamItem> _parse(
    List<List<String>> rows,
    String batch,
    String section,
    Map<String, String> titles,
  ) {
    final targetBatch = batch
        .replaceAll(RegExp(r'\.0+$'), '')
        .replaceAll(RegExp(r'[^0-9]'), '');
    final targetSection = section.trim().toUpperCase();
    final dayRe = RegExp(r'^\s*day[\s-]*\d+\s*$', caseSensitive: false);
    final dateRe = RegExp(r'\d{1,2}[-/]\d{1,2}[-/]\d{2,4}');
    final timeRe = RegExp(r'\d{1,2}:\d{2}|am|pm', caseSensitive: false);
    final weekdayRe = RegExp(
      r'^(sun|mon|tue|wed|thu|fri|sat)',
      caseSensitive: false,
    );

    final blockStarts = <int>[];
    for (var r = 0; r < rows.length; r++) {
      if (rows[r].any(dayRe.hasMatch)) blockStarts.add(r);
    }
    if (blockStarts.isEmpty) return const [];

    var batchCol = 0;
    var sectionCol = 1;
    for (var r = 0; r < rows.length && r < 15; r++) {
      for (var c = 0; c < rows[r].length; c++) {
        final cell = rows[r][c].trim();
        if (RegExp(r'^\s*batch\s*$', caseSensitive: false).hasMatch(cell)) {
          batchCol = c;
        }
        if (RegExp(r'^\s*section\s*$', caseSensitive: false).hasMatch(cell)) {
          sectionCol = c;
        }
      }
    }

    final out = <ExamItem>[];
    for (var bi = 0; bi < blockStarts.length; bi++) {
      final dayHeaderIdx = blockStarts[bi];
      final nextBlockRow = bi + 1 < blockStarts.length
          ? blockStarts[bi + 1]
          : rows.length;
      final dayRow = rows[dayHeaderIdx];
      final dayCols = <int>[
        for (var c = 0; c < dayRow.length; c++)
          if (dayRe.hasMatch(dayRow[c])) c,
      ];
      if (dayCols.isEmpty) continue;

      var dateRowIdx = dayHeaderIdx + 1;
      var timeRowIdx = dayHeaderIdx + 2;
      var weekdayRowIdx = dayHeaderIdx + 3;
      final sampleCol = dayCols.first;
      for (var offset = 1; offset <= 5; offset++) {
        final rIdx = dayHeaderIdx + offset;
        if (rIdx >= rows.length || rIdx >= nextBlockRow) break;
        final cell = sampleCol < rows[rIdx].length
            ? rows[rIdx][sampleCol].trim()
            : '';
        if (dateRe.hasMatch(cell)) {
          dateRowIdx = rIdx;
        } else if (timeRe.hasMatch(cell)) {
          timeRowIdx = rIdx;
        } else if (weekdayRe.hasMatch(cell)) {
          weekdayRowIdx = rIdx;
        }
      }

      final dateRow = dateRowIdx < rows.length ? rows[dateRowIdx] : const [];
      final timeRow = timeRowIdx < rows.length ? rows[timeRowIdx] : const [];
      final weekdayRow = weekdayRowIdx < rows.length
          ? rows[weekdayRowIdx]
          : const [];
      final dataStart =
          [
            dayHeaderIdx,
            dateRowIdx,
            timeRowIdx,
            weekdayRowIdx,
          ].reduce((a, b) => a > b ? a : b) +
          1;

      final rowBatches = <int, String>{};
      var lastBatch = '';
      for (var r = dayHeaderIdx; r < nextBlockRow; r++) {
        final rawBatch = batchCol < rows[r].length ? rows[r][batchCol] : '';
        final normalized = rawBatch
            .replaceAll(RegExp(r'\.0+$'), '')
            .replaceAll(RegExp(r'[^0-9]'), '')
            .trim();
        if (normalized.isNotEmpty &&
            !RegExp(
              r'^(date|time|day|section)',
              caseSensitive: false,
            ).hasMatch(rawBatch.trim())) {
          lastBatch = normalized;
        }
        rowBatches[r] = lastBatch;
      }

      for (var r = dataStart; r < nextBlockRow; r++) {
        final row = rows[r];
        if (row.isEmpty) continue;
        final rowBatch = rowBatches[r] ?? '';
        final rowSection = sectionCol < row.length
            ? row[sectionCol].trim().toUpperCase()
            : '';
        if (rowBatch != targetBatch ||
            !_sectionMatches(rowSection, targetSection)) {
          continue;
        }

        for (final c in dayCols) {
          var cell = c < row.length ? row[c].trim() : '';
          cell = cell.replaceAll(RegExp(r'[\u2013\u2014]'), '-');
          if (cell.isEmpty || cell == '-' || cell == '--') {
            continue;
          }
          cell = cell.replaceAll(RegExp(r'\s*\(\d+\)\s*'), '').trim();
          if (cell.isEmpty) continue;
          final date = c < dateRow.length ? _normDate(dateRow[c]) : '';
          final weekday = c < weekdayRow.length ? weekdayRow[c].trim() : '';
          out.add(
            ExamItem(
              course: cell,
              courseName: titles[cell.toUpperCase()] ?? '',
              date: date,
              time: c < timeRow.length ? timeRow[c].trim() : '',
              weekday: weekday,
              dayLabel: dayRow[c].trim(),
              dateObj: _dateObj(date),
            ),
          );
        }
      }
    }

    out.sort((a, b) {
      final ad = _examDateTime(a);
      final bd = _examDateTime(b);
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return ad.compareTo(bd);
    });
    return out;
  }

  bool _sectionMatches(String rowSection, String targetSection) {
    final row = rowSection.trim().toUpperCase();
    final target = targetSection.trim().toUpperCase();
    if (row.isEmpty || target.isEmpty) return false;
    if (row == target) return true;
    return row
        .split(RegExp(r'[+&,]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .contains(target);
  }

  DateTime? _examDateTime(ExamItem item) {
    final d = item.dateObj;
    if (d == null) return null;
    final mins = _parseTimeMins(item.time);
    return DateTime(d.year, d.month, d.day, mins ~/ 60, mins % 60);
  }

  int _parseTimeMins(String value) {
    final m = RegExp(
      r'(\d{1,2}):(\d{2})\s*([AP]M)?',
      caseSensitive: false,
    ).firstMatch(value);
    if (m == null) return 0;
    var h = int.tryParse(m[1] ?? '') ?? 0;
    final min = int.tryParse(m[2] ?? '') ?? 0;
    final ap = (m[3] ?? '').toUpperCase();
    if (ap == 'PM' && h < 12) h += 12;
    if (ap == 'AM' && h == 12) h = 0;
    if (ap.isEmpty && h < 7) h += 12;
    return h * 60 + min;
  }

  String _normDate(String s) {
    final m = RegExp(r'(\d{1,2})[-/](\d{1,2})[-/](\d{4})').firstMatch(s);
    if (m == null) return s.trim();
    return '${m[1]!.padLeft(2, '0')}-${m[2]!.padLeft(2, '0')}-${m[3]}';
  }

  DateTime? _dateObj(String s) {
    final m = RegExp(r'(\d{1,2})-(\d{1,2})-(\d{4})').firstMatch(s);
    if (m == null) return null;
    return DateTime(int.parse(m[3]!), int.parse(m[2]!), int.parse(m[1]!));
  }
}
