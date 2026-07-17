import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../core/sheets_api.dart';
import '../core/supa.dart';
import 'class_reminder_service.dart';
import 'exam_repository.dart';
import 'home_widget_service.dart';
import 'routine_grid_repository.dart';
import 'session.dart';

const _widgetRefreshTask = 'cse62b.homeWidgetRefresh';

@pragma('vm:entry-point')
void homeWidgetCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      await Supa.init();
    } catch (_) {}
    try {
      await Session.instance.load();
    } catch (_) {}
    await HomeWidgetRefreshService.instance.refreshNow(
      clearCache: true,
      source: 'background',
    );
    return true;
  });
}

class HomeWidgetRefreshService {
  HomeWidgetRefreshService._();
  static final instance = HomeWidgetRefreshService._();

  bool _workmanagerReady = false;
  bool _refreshing = false;

  static const Map<int, String> _weekdayName = {
    DateTime.saturday: 'SATURDAY',
    DateTime.sunday: 'SUNDAY',
    DateTime.monday: 'MONDAY',
    DateTime.tuesday: 'TUESDAY',
    DateTime.wednesday: 'WEDNESDAY',
    DateTime.thursday: 'THURSDAY',
    DateTime.friday: 'FRIDAY',
  };

  Future<void> initializeBackgroundRefresh() async {
    if (!Platform.isAndroid || _workmanagerReady) return;
    try {
      await Workmanager().initialize(homeWidgetCallbackDispatcher);
      await Workmanager().registerPeriodicTask(
        _widgetRefreshTask,
        _widgetRefreshTask,
        frequency: const Duration(minutes: 15),
        initialDelay: const Duration(minutes: 1),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
        backoffPolicy: BackoffPolicy.linear,
        backoffPolicyDelay: const Duration(minutes: 10),
      );
      _workmanagerReady = true;
    } catch (_) {}
  }

  Future<void> refreshNow({
    bool clearCache = false,
    String source = 'app',
  }) async {
    if (!Platform.isAndroid || _refreshing) return;
    _refreshing = true;
    try {
      if (clearCache) {
        SheetsApi.instance.clearCache();
        RoutineGridRepository.instance.invalidate();
      }
      await HomeWidgetService.instance.ensureDefaults();
      final results = await Future.wait([
        _loadRoutine().then<Object?>((value) => value).catchError((_) => null),
        SheetsApi.instance.sheet('Bus').catchError((_) => <List<String>>[]),
        SheetsApi.instance
            .botSheetRaw('Deadlines')
            .catchError((_) => <List<String>>[]),
        ExamRepository.instance
            .loadToday(batch: '62', section: 'B')
            .catchError((_) => <TodayExamItem>[]),
      ]);
      final routine = results[0] as RoutineGridData?;
      final busRows = results[1] as List<List<String>>;
      final deadlineRows = results[2] as List<List<String>>;
      final todayExams = results[3] as List<TodayExamItem>;
      await Future.wait([
        _saveSchedule(routine, busRows, todayExams),
        _saveDeadlines(deadlineRows),
        ClassReminderService.instance.scheduleFromRoutine(routine),
      ]);
    } finally {
      _refreshing = false;
    }
  }

  Future<RoutineGridData> _loadRoutine() async {
    final repo = RoutineGridRepository.instance;
    var data = await repo.load();
    final student = Session.instance.student;
    if (student != null && !student.isDemo) {
      final personal = await Future.wait([
        repo.loadCustomCourses(student.id).catchError((_) => <CustomCourse>[]),
        repo
            .loadEnrollmentCourses(student.id)
            .catchError((_) => <CustomCourse>[]),
      ]);
      final courses = [...personal[0], ...personal[1]];
      if (courses.isNotEmpty) {
        data = repo.buildFor('62', 'B', customs: courses);
      }
    }
    return data;
  }

  Future<void> _saveSchedule(
    RoutineGridData? data,
    List<List<String>> busRows,
    List<TodayExamItem> todayExams,
  ) async {
    final now = DateTime.now();
    final dayName = _weekdayName[now.weekday] ?? '';
    final nowMin = now.hour * 60 + now.minute;

    final slots =
        <
          ({
            String code,
            String name,
            String time,
            String room,
            int start,
            int end,
          })
        >[];
    final today = data?.schedule[dayName];
    if (todayExams.isEmpty && data != null && today != null) {
      final boundaries =
          today
              .map((s) => _timeToMin(s.time))
              .where((m) => m < 9999)
              .toSet()
              .toList()
            ..sort();
      for (final s in today) {
        if (s.isBreak || s.code.isEmpty) continue;
        final start = _timeToMin(s.time);
        final times = RegExp(
          r'(\d{1,2}):(\d{2})',
        ).allMatches(s.time).map((m) => _timeToMin(m.group(0)!)).toList();
        var end = times.length > 1 ? times[1] : start + 90;
        if (times.length < 2) {
          for (final boundary in boundaries) {
            if (boundary > start) {
              end = boundary;
              break;
            }
          }
        }
        slots.add((
          code: s.code,
          name: data.nameFor(s),
          time: s.time,
          room: s.room,
          start: start,
          end: end,
        ));
      }
      slots.sort((a, b) => a.start.compareTo(b.start));
    }

    ({String code, String name, String time, String room, int start, int end})?
    current;
    ({String code, String name, String time, String room, int start, int end})?
    next;
    for (final s in slots) {
      if (s.start > nowMin && next == null) next = s;
      if (s.start <= nowMin && nowMin < s.end) current = s;
    }

    TodayExamItem? currentExam;
    TodayExamItem? nextExam;
    for (final item in todayExams) {
      final start = _timeToMin(item.exam.time);
      if (start > nowMin && nextExam == null) nextExam = item;
      if (start <= nowMin && nowMin < start + 120) currentExam = item;
    }

    final exam = currentExam ?? nextExam;
    final item = current ?? next;
    final label = currentExam != null
        ? 'EXAM RUNNING'
        : nextExam != null
        ? 'NEXT EXAM'
        : todayExams.isNotEmpty
        ? 'EXAM DAY'
        : current != null
        ? 'NOW RUNNING'
        : next != null
        ? 'NEXT CLASS'
        : 'TODAY';
    final title = exam != null
        ? exam.exam.courseName.isEmpty
              ? exam.exam.course
              : '${exam.exam.course} · ${exam.exam.courseName}'
        : todayExams.isNotEmpty
        ? 'No more exams'
        : item == null
        ? 'No more classes'
        : item.name.isEmpty
        ? item.code
        : '${item.code} · ${item.name}';
    final details = exam != null
        ? '${exam.type} · ${exam.exam.time}'
        : todayExams.isNotEmpty
        ? '${todayExams.first.type} · Check again tomorrow'
        : item == null
        ? '$dayName · Check again tomorrow'
        : 'Room ${item.room.isEmpty ? '—' : item.room} · ${item.time}';

    final (toLu, fromLu) = _parseBus(busRows, examDay: todayExams.isNotEmpty);
    final nextTo = toLu.where((bus) => bus.t >= nowMin).firstOrNull;
    final nextFrom = fromLu.where((bus) => bus.t >= nowMin).firstOrNull;
    final busParts = <String>[
      if (nextTo != null) 'To LU ${nextTo.time}',
      if (nextFrom != null) 'From LU ${nextFrom.time}',
    ];
    final busStatus = busParts.isEmpty
        ? 'No more buses today'
        : 'Next bus: ${busParts.join(' · ')}';
    await HomeWidgetService.instance.saveScheduleStatus(
      label: label,
      title: title,
      details: details,
      busStatus: busStatus,
    );
  }

  Future<void> _saveDeadlines(List<List<String>> rows) async {
    final now = DateTime.now();
    final upcoming =
        <({String course, String type, String title, DateTime due})>[];
    for (final row in rows) {
      String at(int i) => i < row.length ? row[i].trim() : '';
      final course = at(0), type = at(1), title = at(2);
      if (title.isEmpty) continue;
      if (course.toLowerCase() == 'course' || type.toLowerCase() == 'type') {
        continue;
      }
      final due = _parseGvizDate(at(3));
      if (due == null || !due.isAfter(now)) continue;
      upcoming.add((course: course, type: type, title: title, due: due));
    }
    upcoming.sort((a, b) => a.due.compareTo(b.due));
    if (upcoming.isEmpty) {
      await HomeWidgetService.instance.saveDeadline('No upcoming deadline');
      return;
    }

    final counts = <String, int>{};
    for (final item in upcoming) {
      final label = _deadlineTypeLabel(item.type);
      counts.update(label, (count) => count + 1, ifAbsent: () => 1);
    }
    final nearest = upcoming.first;
    final countLine = counts.entries
        .take(3)
        .map((entry) => '${_shortDeadlineType(entry.key)} ${entry.value}')
        .join(' · ');
    final extra = math.max(
      0,
      upcoming.length - counts.values.take(3).fold(0, (a, b) => a + b),
    );
    final summary = extra > 0 ? 'Due: $countLine · +$extra' : 'Due: $countLine';
    final nextLine =
        'Next: ${_shortDeadlineType(nearest.type)} · ${_formatDue(nearest.due)}';
    await HomeWidgetService.instance.saveDeadline('$summary\n$nextLine');
  }

  static (List<({String time, int t})>, List<({String time, int t})>) _parseBus(
    List<List<String>> rows, {
    required bool examDay,
  }) {
    final to = <({String time, int t})>[];
    final from = <({String time, int t})>[];
    final wd = DateTime.now().weekday;
    final isFri = wd == DateTime.friday;
    final isSat = wd == DateTime.saturday;
    final start =
        (rows.isNotEmpty &&
            rows[0].isNotEmpty &&
            rows[0][0].toLowerCase().trim() == 'schedule')
        ? 1
        : 0;
    for (var i = start; i < rows.length; i++) {
      final r = rows[i];
      if (r.length < 4) continue;
      final sched = r[0].trim();
      final isWantedSchedule = examDay
          ? sched.toLowerCase().startsWith('exam:')
          : sched == 'Regular';
      if (!isWantedSchedule) continue;
      final gl = r[1].trim().toLowerCase();
      final dir = r[2].trim();
      final match =
          (isFri && gl.contains('fri')) ||
          (isSat &&
              (gl == 'saturday' ||
                  gl.contains('sat–thu') ||
                  gl.contains('sat-thu'))) ||
          (!isFri &&
              !isSat &&
              (gl.contains('sun') || gl.contains('sat') || gl.contains('mon')));
      if (!match) continue;
      final t = _timeToMinAmPm(r[3].trim());
      if (t < 0) continue;
      if (dir == 'From LU') {
        from.add((time: r[3].trim(), t: t));
      } else if (dir == 'To LU') {
        to.add((time: r[3].trim(), t: t));
      }
    }
    to.sort((a, b) => a.t.compareTo(b.t));
    from.sort((a, b) => a.t.compareTo(b.t));
    return (to, from);
  }

  static int _timeToMin(String t) {
    final m = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(t);
    if (m == null) return 9999;
    var h = int.parse(m[1]!);
    final mi = int.parse(m[2]!);
    if (h < 8) h += 12;
    return h * 60 + mi;
  }

  static int _timeToMinAmPm(String s) {
    final m = RegExp(
      r'(\d{1,2}):(\d{2})\s*(AM|PM)',
      caseSensitive: false,
    ).firstMatch(s);
    if (m == null) return -1;
    var h = int.parse(m[1]!);
    final mi = int.parse(m[2]!);
    final pm = m[3]!.toUpperCase() == 'PM';
    if (pm && h != 12) h += 12;
    if (!pm && h == 12) h = 0;
    return h * 60 + mi;
  }

  static DateTime? _parseGvizDate(String value) {
    final t = value.trim();
    if (t.isEmpty) return null;
    final m = RegExp(
      r'^Date\((\d+),(\d+),(\d+)(?:,(\d+),(\d+)(?:,(\d+))?)?\)$',
    ).firstMatch(t);
    if (m != null) {
      return DateTime(
        int.parse(m[1]!),
        int.parse(m[2]!) + 1,
        int.parse(m[3]!),
        int.parse(m[4] ?? '0'),
        int.parse(m[5] ?? '0'),
        int.parse(m[6] ?? '0'),
      );
    }
    return DateTime.tryParse(t.replaceFirst(' ', 'T'));
  }

  static String _deadlineTypeLabel(String value) {
    final words = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .map(
          (word) =>
              '${word.substring(0, 1).toUpperCase()}${word.substring(1).toLowerCase()}',
        )
        .toList();
    return words.isEmpty ? 'Task' : words.join(' ');
  }

  static String _shortDeadlineType(String value) {
    switch (value.toLowerCase()) {
      case 'assignment':
        return 'Assign';
      case 'tutorial':
        return 'Tut';
      case 'presentation':
        return 'Pres';
      case 'lab test':
      case 'labtest':
        return 'Test';
      case 'lab report':
      case 'labreport':
        return 'Lab';
      default:
        return value.length > 8 ? value.substring(0, 8) : value;
    }
  }

  static String _formatDue(DateTime due) {
    final now = DateTime.now();
    final time = _formatTime(due);
    if (_sameDay(now, due)) return 'Today $time';
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    if (_sameDay(tomorrow, due)) return 'Tomorrow $time';
    return '${due.day}/${due.month} $time';
  }

  static String _formatTime(DateTime d) {
    var h = d.hour;
    final ap = h >= 12 ? 'PM' : 'AM';
    h = h % 12 == 0 ? 12 : h % 12;
    return '$h:${d.minute.toString().padLeft(2, '0')} $ap';
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
