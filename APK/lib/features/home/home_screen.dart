import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_colors.dart';
import '../../core/name_format.dart';
import '../../core/sheets_api.dart';
import '../../data/connectivity_service.dart';
import '../../data/exam_repository.dart';
import '../../data/home_widget_service.dart';
import '../../data/routine_grid_repository.dart';
import '../../data/session.dart';
import '../../shared/app_toast.dart';
import '../../shared/avatar_badge.dart';
import '../../shared/folder_card.dart';
import '../notifications/notification_bell.dart';
import '../search/app_search.dart';

class _NavItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final String? route;
  const _NavItem(
    this.icon,
    this.title,
    this.subtitle,
    this.accent, [
    this.route,
  ]);
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();

  // Content folders shown on the home grid. The website's header pages live in
  // the slide-out drawer instead. Classwork is a content hub here that also
  // holds the Presentation / Tutorial / Lab Report / Viva / Lab Final / Project
  // categories.
  static const _items = <_NavItem>[
    _NavItem(
      Icons.assignment_rounded,
      'Classwork',
      'Tasks, categories & deadlines',
      Color(0xFF059669),
      '/classwork',
    ),
    _NavItem(
      Icons.description_rounded,
      'Cover Page',
      'Generate assignment covers',
      Color(0xFF8B5CF6),
      '/cover-page',
    ),
    _NavItem(
      Icons.menu_book_rounded,
      'Resources',
      'Lectures, notes & PDFs',
      Color(0xFFEC4899),
      '/resources',
    ),
    _NavItem(
      Icons.sports_esports_rounded,
      'Games',
      'Imposter & Draw — multiplayer',
      Color(0xFFFB923C),
      '/games',
    ),
  ];

  // The website's header/navbar pages — surfaced in the slide-out drawer.
  static const _menuPages = <({String label, IconData icon, String route})>[
    (label: 'Notice', icon: Icons.campaign_rounded, route: '/notice'),
    (label: 'Info', icon: Icons.event_note_rounded, route: '/info'),
    (label: 'Results', icon: Icons.bar_chart_rounded, route: '/results'),
    (label: 'Gallery', icon: Icons.photo_library_rounded, route: '/gallery'),
    (label: 'Students', icon: Icons.groups_rounded, route: '/students'),
    (
      label: 'Downloads',
      icon: Icons.download_done_rounded,
      route: '/downloads',
    ),
    (
      label: 'User Guide',
      icon: Icons.help_outline_rounded,
      route: '/user-guide',
    ),
  ];
}

class _HomeScreenState extends State<HomeScreen> {
  bool _homeQuickExamActive = false;

  @override
  Widget build(BuildContext context) {
    final student = Session.instance.student;
    return Scaffold(
      backgroundColor: AppColors.bg,
      drawer: _HomeDrawer(pages: HomeScreen._menuPages, student: student),
      bottomNavigationBar: _searchBar(context),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              floating: true,
              backgroundColor: AppColors.bg,
              elevation: 0,
              titleSpacing: 4,
              leading: Builder(
                builder: (ctx) => IconButton(
                  icon: const Icon(
                    Icons.menu_rounded,
                    color: AppColors.textSecondary,
                  ),
                  tooltip: 'Menu',
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                ),
              ),
              title: const Text(
                'CSE 62B · PORTAL',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: AppColors.accentBright,
                ),
              ),
              actions: [
                ListenableBuilder(
                  listenable: ConnectivityService.instance,
                  builder: (_, _) {
                    final on = ConnectivityService.instance.online;
                    return Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: Tooltip(
                        message: on ? 'Online' : 'Offline — showing saved data',
                        child: Icon(
                          on
                              ? Icons.cloud_done_rounded
                              : Icons.cloud_off_rounded,
                          size: 18,
                          color: on
                              ? const Color(0xFF34D399)
                              : const Color(0xFFFBBF24),
                        ),
                      ),
                    );
                  },
                ),
                const NotificationBell(),
                Padding(
                  padding: const EdgeInsets.only(left: 2, right: 12),
                  child: GestureDetector(
                    onTap: () => context.push('/profile'),
                    child: student == null
                        ? const Icon(
                            Icons.account_circle_outlined,
                            color: AppColors.textSecondary,
                          )
                        : AvatarBadge(name: student.name, size: 32, radius: 10),
                  ),
                ),
              ],
            ),
            SliverToBoxAdapter(
              child: ListenableBuilder(
                listenable: ConnectivityService.instance,
                builder: (_, _) => ConnectivityService.instance.online
                    ? const SizedBox.shrink()
                    : Container(
                        margin: const EdgeInsets.fromLTRB(14, 6, 14, 0),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFFFBBF24,
                          ).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(
                              0xFFFBBF24,
                            ).withValues(alpha: 0.35),
                          ),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.cloud_off_rounded,
                              size: 15,
                              color: Color(0xFFFBBF24),
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                "You're offline — showing saved data. Downloads still open.",
                                style: TextStyle(
                                  color: Color(0xFFFBBF24),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
            SliverToBoxAdapter(child: _greeting(student?.name)),
            if (student != null && !Session.instance.isDemo)
              SliverToBoxAdapter(
                child: _ClassStatusCard(
                  onExamStatusChanged: (active) {
                    if (mounted && active != _homeQuickExamActive) {
                      setState(() => _homeQuickExamActive = active);
                    }
                  },
                ),
              ),
            if (!_homeQuickExamActive)
              const SliverToBoxAdapter(child: _UpcomingExamStrip()),
            const SliverToBoxAdapter(child: _DeadlineStrip()),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 28),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.18,
                ),
                delegate: SliverChildBuilderDelegate((context, i) {
                  final it = HomeScreen._items[i];
                  final card = FolderCard(
                    icon: it.icon,
                    title: it.title,
                    subtitle: it.subtitle,
                    accent: it.accent,
                    index: i,
                    onTap: () {
                      if (it.route != null) {
                        context.push(it.route!);
                      } else {
                        AppToast.show(context, '${it.title} — coming soon');
                      }
                    },
                  );
                  // Live "running classwork" count badge on the Classwork card.
                  if (it.route == '/classwork') {
                    return Stack(
                      children: [
                        Positioned.fill(child: card),
                        const Positioned(
                          top: 8,
                          right: 8,
                          child: IgnorePointer(child: _ClassworkBadge()),
                        ),
                      ],
                    );
                  }
                  return card;
                }, childCount: HomeScreen._items.length),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _greeting(String? name) {
    final hour = DateTime.now().hour;
    final part = hour < 12
        ? 'Good morning'
        : hour < 17
        ? 'Good afternoon'
        : 'Good evening';
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            part,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            name != null ? friendlyFirstName(name) : 'Welcome',
            style: const TextStyle(
              color: AppColors.textBright,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ).animate().fadeIn(duration: 300.ms).moveY(begin: 8, end: 0),
    );
  }

  /// Bottom global-search bar — tapping opens the searchable function list
  /// (most-used by default, live-filtered as you type).
  Widget _searchBar(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
        child: Material(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          elevation: 8,
          shadowColor: Colors.black.withValues(alpha: 0.4),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => showAppSearch(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.borderAccent),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.search_rounded,
                    color: AppColors.accentBright,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Search anything in the portal…',
                      style: TextStyle(color: AppColors.muted, fontSize: 13.5),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Search',
                      style: TextStyle(
                        color: AppColors.accentBright,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Live "Now Running / Next Class" strip on the home page — mirrors the
/// website's quick-info bar. Reads today's 62B routine (from the cached grid)
/// and ticks a live clock + countdowns every second.
class _ClassStatusCard extends StatefulWidget {
  final ValueChanged<bool> onExamStatusChanged;
  const _ClassStatusCard({required this.onExamStatusChanged});

  @override
  State<_ClassStatusCard> createState() => _ClassStatusCardState();
}

class _ClassStatusCardState extends State<_ClassStatusCard> {
  RoutineGridData? _data;
  List<TodayExamItem> _todayExams = const [];
  bool _loading = true;
  bool _refreshing = false;
  DateTime? _lastLoaded;
  Timer? _ticker;
  String _lastWidgetSignature = '';
  bool? _lastReportedExamStatus;

  // Today's regular bus times (minutes-from-midnight), per direction.
  List<({String time, int t})> _toLU = const [];
  List<({String time, int t})> _fromLU = const [];

  static const _green = Color(0xFF34D399);
  static const _accent = Color(0xFF818CF8);
  static const _busColor = Color(0xFF22D3EE);

  static const Map<int, String> _weekdayName = {
    DateTime.saturday: 'SATURDAY',
    DateTime.sunday: 'SUNDAY',
    DateTime.monday: 'MONDAY',
    DateTime.tuesday: 'TUESDAY',
    DateTime.wednesday: 'WEDNESDAY',
    DateTime.thursday: 'THURSDAY',
    DateTime.friday: 'FRIDAY',
  };

  @override
  void initState() {
    super.initState();
    _load();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      final last = _lastLoaded;
      final now = DateTime.now();
      final dayChanged =
          last != null &&
          (last.year != now.year ||
              last.month != now.month ||
              last.day != now.day);
      if (!_refreshing &&
          last != null &&
          (dayChanged || now.difference(last) >= const Duration(minutes: 5))) {
        _load();
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_refreshing) return;
    _refreshing = true;
    // Routine (cached) + bus + exam-day flag, in parallel. Bus/exam checks
    // failing must not block classes.
    final repo = RoutineGridRepository.instance;
    final routine = () async {
      var data = await repo.load();
      final student = Session.instance.student;
      if (student != null && !student.isDemo) {
        final personal = await Future.wait([
          repo.loadCustomCourses(student.id),
          repo.loadEnrollmentCourses(student.id),
        ]);
        final courses = [...personal[0], ...personal[1]];
        if (courses.isNotEmpty) {
          data = repo.buildFor('62', 'B', customs: courses);
        }
      }
      return data;
    }();
    final results = await Future.wait([
      routine.then<Object?>((d) => d).catchError((_) => null),
      SheetsApi.instance.sheet('Bus').catchError((_) => <List<String>>[]),
      ExamRepository.instance
          .loadToday(batch: '62', section: 'B')
          .catchError((_) => <TodayExamItem>[]),
    ]);
    if (!mounted) {
      _refreshing = false;
      return;
    }
    setState(() {
      _data = results[0] as RoutineGridData?;
      _todayExams = results[2] as List<TodayExamItem>;
      _parseBus(
        results[1] as List<List<String>>,
        examDay: _todayExams.isNotEmpty,
      );
      _loading = false;
      _lastLoaded = DateTime.now();
      _refreshing = false;
    });
  }

  /// Parse today's bus times into To-LU / From-LU lists. On exact 62B exam
  /// dates, the Exam:* schedule rows replace the regular schedule.
  void _parseBus(List<List<String>> rows, {required bool examDay}) {
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
      final t = _toMinAmPm(r[3].trim());
      if (t < 0) continue;
      if (dir == 'From LU') {
        from.add((time: r[3].trim(), t: t));
      } else if (dir == 'To LU') {
        to.add((time: r[3].trim(), t: t));
      }
    }
    to.sort((a, b) => a.t.compareTo(b.t));
    from.sort((a, b) => a.t.compareTo(b.t));
    _toLU = to;
    _fromLU = from;
  }

  // Routine time-slot label ("8:30") → minutes (hours < 8 are afternoon).
  static int _toMin(String t) {
    final m = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(t);
    if (m == null) return 9999;
    var h = int.parse(m[1]!);
    final mi = int.parse(m[2]!);
    if (h < 8) h += 12;
    return h * 60 + mi;
  }

  // "7:30 AM" → minutes from midnight.
  static int _toMinAmPm(String s) {
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

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final clock =
        '${_pad(now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour))}:${_pad(now.minute)}:${_pad(now.second)} ${now.hour >= 12 ? 'PM' : 'AM'}';
    final dayName = _weekdayName[now.weekday] ?? '';
    final nowMin = now.hour * 60 + now.minute;

    // Include BREAK boundaries when resolving class end. Otherwise a class
    // incorrectly appears to keep running until the next class starts.
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
    final today = _data?.schedule[dayName];
    if (_todayExams.isEmpty && today != null) {
      final boundaries =
          today
              .map((s) => _toMin(s.time))
              .where((m) => m < 9999)
              .toSet()
              .toList()
            ..sort();
      for (final s in today) {
        if (s.isBreak || s.code.isEmpty) continue;
        final start = _toMin(s.time);
        final times = RegExp(
          r'(\d{1,2}):(\d{2})',
        ).allMatches(s.time).map((m) => _toMin(m.group(0)!)).toList();
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
          name: _data!.nameFor(s),
          time: s.time,
          room: s.room,
          start: start,
          end: end,
        ));
      }
      slots.sort((a, b) => a.start.compareTo(b.start));
    }

    // Resolve current + next.
    ({String code, String name, String time, String room, int start, int end})?
    current;
    ({String code, String name, String time, String room, int start, int end})?
    next;
    for (final s in slots) {
      if (s.start > nowMin && next == null) next = s;
      if (s.start <= nowMin && nowMin < s.end) {
        current = s;
      }
    }

    TodayExamItem? currentExam;
    TodayExamItem? nextExam;
    for (final item in _todayExams) {
      final start = _toMin(item.exam.time);
      if (start > nowMin && nextExam == null) nextExam = item;
      if (start <= nowMin && nowMin < start + 120) currentExam = item;
    }

    final examItem = currentExam ?? nextExam;
    final examStatusActive = examItem != null;
    if (_lastReportedExamStatus != examStatusActive) {
      _lastReportedExamStatus = examStatusActive;
      scheduleMicrotask(() {
        if (mounted) widget.onExamStatusChanged(examStatusActive);
      });
    }
    final widgetItem = current ?? next;
    final widgetLabel = currentExam != null
        ? 'EXAM RUNNING'
        : nextExam != null
        ? 'NEXT EXAM'
        : _todayExams.isNotEmpty
        ? 'EXAM DAY'
        : current != null
        ? 'NOW RUNNING'
        : next != null
        ? 'NEXT CLASS'
        : 'TODAY';
    final widgetTitle = examItem != null
        ? examItem.exam.courseName.isEmpty
              ? examItem.exam.course
              : '${examItem.exam.course} · ${examItem.exam.courseName}'
        : _todayExams.isNotEmpty
        ? 'No more exams'
        : widgetItem == null
        ? 'No more classes'
        : widgetItem.name.isEmpty
        ? widgetItem.code
        : '${widgetItem.code} · ${widgetItem.name}';
    final widgetDetails = examItem != null
        ? '${examItem.type} · ${examItem.exam.time}'
        : _todayExams.isNotEmpty
        ? '${_todayExams.first.type} · Check again tomorrow'
        : widgetItem == null
        ? '$dayName · Check again tomorrow'
        : 'Room ${widgetItem.room.isEmpty ? '—' : widgetItem.room} · ${widgetItem.time}';
    final nextTo = _toLU.where((bus) => bus.t >= nowMin).firstOrNull;
    final nextFrom = _fromLU.where((bus) => bus.t >= nowMin).firstOrNull;
    final busParts = <String>[
      if (nextTo != null) 'To LU ${nextTo.time}',
      if (nextFrom != null) 'From LU ${nextFrom.time}',
    ];
    final widgetBus = busParts.isEmpty
        ? 'No more buses today'
        : 'Next bus: ${busParts.join(' · ')}';
    final widgetSignature =
        '$widgetLabel|$widgetTitle|$widgetDetails|$widgetBus';
    if (_lastWidgetSignature != widgetSignature) {
      _lastWidgetSignature = widgetSignature;
      scheduleMicrotask(
        () => HomeWidgetService.instance.saveScheduleStatus(
          label: widgetLabel,
          title: widgetTitle,
          details: widgetDetails,
          busStatus: widgetBus,
        ),
      );
    }

    final hasClassStatus =
        currentExam != null ||
        nextExam != null ||
        current != null ||
        next != null;
    final hasBusStatus = nextTo != null || nextFrom != null;
    if (_loading || (!hasClassStatus && !hasBusStatus)) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 2, 14, 6),
      padding: const EdgeInsets.fromLTRB(15, 13, 15, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _accent.withValues(alpha: 0.10),
            _green.withValues(alpha: 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderAccent),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bolt_rounded, size: 16, color: _accent),
              const SizedBox(width: 6),
              Text(
                dayName.isEmpty ? 'TODAY' : dayName,
                style: const TextStyle(
                  color: AppColors.accentBright,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
              const Spacer(),
              Text(
                clock,
                style: const TextStyle(
                  color: AppColors.textBright,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (currentExam != null) ...[
            _statusRow(
              dot: _green,
              label: 'EXAM RUNNING',
              value: currentExam.exam.courseName.isNotEmpty
                  ? '${currentExam.exam.course} · ${currentExam.exam.courseName}'
                  : currentExam.exam.course,
              subtitle: '${currentExam.type} · ${currentExam.exam.time}',
              trailing: _fmt(
                'ends ',
                _toMin(currentExam.exam.time) + 120 - nowMin,
              ),
              muted: false,
            ),
          ] else if (current != null) ...[
            _statusRow(
              dot: _green,
              label: 'NOW RUNNING',
              value: current.name.isNotEmpty
                  ? '${current.code} · ${current.name}'
                  : current.code,
              subtitle:
                  'Room: ${current.room.isEmpty ? '—' : current.room} · ${current.time}',
              trailing: _fmt('ends ', current.end - nowMin),
              muted: false,
            ),
          ],
          if ((currentExam != null && nextExam != null) ||
              (current != null && next != null))
            const SizedBox(height: 10),
          if (nextExam != null) ...[
            _statusRow(
              dot: _accent,
              label: 'NEXT EXAM',
              value: nextExam.exam.courseName.isNotEmpty
                  ? '${nextExam.exam.course} · ${nextExam.exam.courseName}'
                  : nextExam.exam.course,
              trailing: _fmt('', _toMin(nextExam.exam.time) - nowMin),
              muted: false,
            ),
            const SizedBox(height: 9),
            Padding(
              padding: const EdgeInsets.only(left: 18),
              child: Row(
                children: [
                  _infoChip(
                    Icons.schedule_rounded,
                    'Time',
                    nextExam.exam.time,
                    _accent,
                  ),
                  const SizedBox(width: 8),
                  _infoChip(
                    Icons.description_rounded,
                    'Type',
                    nextExam.type,
                    _accent,
                  ),
                ],
              ),
            ),
          ] else if (next != null) ...[
            _statusRow(
              dot: _accent,
              label: 'NEXT CLASS',
              value: next.name.isNotEmpty
                  ? '${next.code} · ${next.name}'
                  : next.code,
              trailing: _fmt('', next.start - nowMin),
              muted: false,
            ),
            const SizedBox(height: 9),
            Padding(
              padding: const EdgeInsets.only(left: 18),
              child: Row(
                children: [
                  _infoChip(Icons.schedule_rounded, 'Time', next.time, _accent),
                  const SizedBox(width: 8),
                  _infoChip(
                    Icons.meeting_room_rounded,
                    'Room',
                    next.room.isEmpty ? '—' : next.room,
                    _accent,
                  ),
                ],
              ),
            ),
          ],
          _busSection(nowMin, showDivider: hasClassStatus),
        ],
      ),
    );
  }

  /// Next Bus — To LU / From LU with live "in Xm" countdowns, like the website.
  Widget _busSection(int nowMin, {bool showDivider = true}) {
    final nextTo = _toLU.where((b) => b.t >= nowMin).firstOrNull;
    final nextFrom = _fromLU.where((b) => b.t >= nowMin).firstOrNull;
    if (nextTo == null && nextFrom == null) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showDivider)
          const Padding(
            padding: EdgeInsets.only(top: 12, bottom: 8),
            child: Divider(height: 1, color: AppColors.border),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(
                Icons.directions_bus_rounded,
                size: 15,
                color: _busColor,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'NEXT BUS',
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
            const Spacer(),
          ],
        ),
        const SizedBox(height: 7),
        Padding(
          padding: const EdgeInsets.only(left: 25),
          child: Row(
            children: [
              if (nextTo != null)
                Expanded(child: _busCol('To LU', nextTo, nowMin)),
              if (nextTo != null && nextFrom != null)
                Container(
                  width: 1,
                  height: 30,
                  color: AppColors.border,
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                ),
              if (nextFrom != null)
                Expanded(child: _busCol('From LU', nextFrom, nowMin)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _busCol(String dir, ({String time, int t}) bus, int nowMin) {
    final cd = _fmt('', bus.t - nowMin);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          dir,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 1),
        Row(
          children: [
            Text(
              bus.time,
              style: const TextStyle(
                color: AppColors.textBright,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (cd != null) ...[
              const SizedBox(width: 6),
              Text(
                cd,
                style: const TextStyle(
                  color: _busColor,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  /// Small labelled value chip (used for Time / Room).
  Widget _infoChip(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            '$label ',
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textBright,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusRow({
    required Color dot,
    required String label,
    required String value,
    String? subtitle,
    String? trailing,
    required bool muted,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: muted ? AppColors.muted : dot,
              shape: BoxShape.circle,
              boxShadow: muted
                  ? null
                  : [
                      BoxShadow(
                        color: dot.withValues(alpha: 0.6),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  color: muted ? AppColors.textSecondary : AppColors.textBright,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11.5,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: dot.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              trailing,
              style: TextStyle(
                color: dot,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ],
    );
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');

  /// "in 1h 20m" / "ends in 25m" style countdown (minute granularity).
  static String? _fmt(String prefix, int diffMin) {
    if (diffMin <= 0) return null;
    if (diffMin < 60) return '${prefix}in ${diffMin}m';
    final h = diffMin ~/ 60, m = diffMin % 60;
    return m > 0 ? '${prefix}in ${h}h ${m}m' : '${prefix}in ${h}h';
  }
}

class _ExamHit {
  final String type;
  final Color color;
  final ExamItem exam;
  const _ExamHit(this.type, this.color, this.exam);
}

/// Compact upcoming exam strip on the home page. Mirrors the website home
/// countdown: it appears only when a mid/final exam is within 7 days.
class _UpcomingExamStrip extends StatefulWidget {
  const _UpcomingExamStrip();

  @override
  State<_UpcomingExamStrip> createState() => _UpcomingExamStripState();
}

class _UpcomingExamStripState extends State<_UpcomingExamStrip> {
  List<_ExamHit> _hits = const [];
  bool _loading = true;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final mid = await ExamRepository.instance
          .load('mid', batch: '62', section: 'B')
          .catchError((_) => <ExamItem>[]);
      final fin = await ExamRepository.instance
          .load('final', batch: '62', section: 'B')
          .catchError((_) => <ExamItem>[]);
      final today = _dateOnly(DateTime.now());
      final all =
          <_ExamHit>[
              ...mid.map(
                (e) => _ExamHit('Mid Term', const Color(0xFF34D399), e),
              ),
              ...fin.map(
                (e) => _ExamHit('Final Term', const Color(0xFFF87171), e),
              ),
            ].where((hit) {
              final d = hit.exam.dateObj;
              if (d == null) return false;
              final examDay = _dateOnly(d);
              final days = examDay.difference(today).inDays;
              return days >= 0 && days <= 7;
            }).toList()
            ..sort((a, b) {
              final da = _examDateTime(a.exam);
              final db = _examDateTime(b.exam);
              if (da == null || db == null) return 0;
              return da.compareTo(db);
            });

      if (!mounted) return;
      setState(() {
        _hits = all.take(2).toList();
        _loading = false;
      });
      if (_hits.isNotEmpty) {
        _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() {});
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _hits.isEmpty) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () => context.push('/info/exam'),
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 2, 14, 8),
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.accentBright.withValues(alpha: 0.12),
              const Color(0xFF38BDF8).withValues(alpha: 0.06),
            ],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.borderAccent),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.event_available_rounded,
                  size: 16,
                  color: AppColors.accentBright,
                ),
                SizedBox(width: 6),
                Text(
                  'UPCOMING EXAM',
                  style: TextStyle(
                    color: AppColors.accentBright,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
                Spacer(),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: AppColors.muted,
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < _hits.length; i++) ...[
              if (i > 0)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Divider(height: 1, color: AppColors.border),
                ),
              _row(_hits[i]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(_ExamHit hit) {
    final exam = hit.exam;
    final dt = _examDateTime(exam);
    final diff = dt?.difference(DateTime.now());
    final courseName = exam.courseName.trim().isNotEmpty
        ? exam.courseName.trim()
        : exam.course.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: hit.color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                hit.type,
                style: TextStyle(
                  color: hit.color,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                courseName.isEmpty ? 'Exam' : courseName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textBright,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
            ),
          ],
        ),
        if (exam.courseName.trim().isNotEmpty && exam.course.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              exam.course.trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        const SizedBox(height: 5),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.schedule_rounded, size: 13, color: hit.color),
            const SizedBox(width: 5),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: diff == null || diff.isNegative
                          ? 'Starting soon'
                          : _countdown(diff),
                      style: TextStyle(
                        color: hit.color,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    TextSpan(
                      text: '  ·  ${_fmtExamDate(exam)}',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime? _examDateTime(ExamItem exam) {
    final d = exam.dateObj;
    if (d == null) return null;
    final mins = _parseTimeMins(exam.time);
    return DateTime(d.year, d.month, d.day, mins ~/ 60, mins % 60);
  }

  static int _parseTimeMins(String value) {
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

  static String _countdown(Duration diff) {
    String two(int n) => n.toString().padLeft(2, '0');
    final d = diff.inDays;
    final h = diff.inHours % 24;
    final m = diff.inMinutes % 60;
    final s = diff.inSeconds % 60;
    if (d > 0) return '${d}d ${two(h)}h ${two(m)}m ${two(s)}s';
    if (h > 0) return '${two(h)}h ${two(m)}m ${two(s)}s';
    return '${two(m)}m ${two(s)}s';
  }

  static String _fmtExamDate(ExamItem exam) {
    final d = exam.dateObj;
    if (d == null) return exam.time;
    const mo = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final time = exam.time.trim();
    return '${mo[d.month - 1]} ${d.day}${time.isEmpty ? '' : ', $time'}';
  }
}

class _Dl {
  final String course, type, title;
  final DateTime? due;
  const _Dl(this.course, this.type, this.title, this.due);
}

/// Compact "Closest Deadline(s)" strip on the home page. Shows the soonest
/// upcoming deadline with a live countdown; if several fall on that same nearest
/// day it shows them together. Hidden entirely when nothing is upcoming.
class _DeadlineStrip extends StatefulWidget {
  const _DeadlineStrip();
  @override
  State<_DeadlineStrip> createState() => _DeadlineStripState();
}

class _DeadlineStripState extends State<_DeadlineStrip> {
  List<_Dl> _items = const [];
  bool _loading = true;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await SheetsApi.instance.botSheetRaw('Deadlines');
      final out = <_Dl>[];
      for (final r in rows) {
        String at(int n) => n < r.length ? r[n].trim() : '';
        final course = at(0), type = at(1), title = at(2);
        if (title.isEmpty) continue;
        if (course.toLowerCase() == 'course' || type.toLowerCase() == 'type') {
          continue;
        }
        out.add(_Dl(course, type, title, _parseGvizDate(at(3))));
      }
      final upcoming =
          out
              .where((item) => item.due?.isAfter(DateTime.now()) == true)
              .toList()
            ..sort((a, b) => a.due!.compareTo(b.due!));
      final dueCounts = <String, int>{};
      for (final item in upcoming) {
        final label = _deadlineTypeLabel(item.type);
        dueCounts.update(label, (count) => count + 1, ifAbsent: () => 1);
      }
      final widgetDeadline = upcoming.isEmpty
          ? 'No upcoming deadline'
          : _widgetDueSummaryNice(upcoming, dueCounts);
      await HomeWidgetService.instance.saveDeadline(widgetDeadline);
      if (!mounted) return;
      setState(() {
        _items = out;
        _loading = false;
      });
      _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } catch (_) {
      await HomeWidgetService.instance
          .saveDeadline('Deadline information unavailable')
          .catchError((_) {});
      if (mounted) setState(() => _loading = false);
    }
  }

  static DateTime? _parseGvizDate(String s) {
    final t = s.trim();
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
        .split(' ')
        .where((word) => word.isNotEmpty)
        .map(
          (word) =>
              '${word.substring(0, 1).toUpperCase()}${word.substring(1).toLowerCase()}',
        )
        .toList();
    return words.isEmpty ? 'Task' : words.join(' ');
  }

  static String _widgetDueSummaryNice(
    List<_Dl> upcoming,
    Map<String, int> counts,
  ) {
    final visibleEntries = counts.entries.take(3).toList();
    final visible = visibleEntries
        .map((entry) => '${_shortDeadlineType(entry.key)} ${entry.value}')
        .join(' · ');
    final visibleCount = visibleEntries.fold<int>(
      0,
      (total, entry) => total + entry.value,
    );
    final extra = upcoming.length - visibleCount;
    final summary = extra > 0 ? 'Due: $visible · +$extra' : 'Due: $visible';
    final nearest = upcoming.first;
    return '$summary\nNext: ${_shortDeadlineType(nearest.type)} · ${_formatWidgetDue(nearest.due!)}';
  }

  // Kept for older cached widget text migration paths; new widget text uses
  // [_widgetDueSummaryNice].
  // ignore: unused_element
  static String _widgetDueSummary(Map<String, int> counts, int total) {
    final visible = counts.entries
        .take(3)
        .map((entry) => '${_shortDeadlineType(entry.key)} ${entry.value}');
    final hiddenTypes = counts.length - 3;
    final suffix = hiddenTypes > 0 ? ' · +$hiddenTypes types' : '';
    return 'Due $total: ${visible.join(' · ')}$suffix';
  }

  static String _shortDeadlineType(String value) {
    switch (value.toLowerCase()) {
      case 'assignment':
        return 'Assign';
      case 'tutorial':
        return 'Tut';
      case 'presentation':
        return 'Pres';
      case 'lab report':
      case 'labreport':
        return 'Lab';
      default:
        return value.length > 8 ? value.substring(0, 8) : value;
    }
  }

  static String _formatWidgetDue(DateTime due) {
    final now = DateTime.now();
    final time = _formatWidgetTime(due);
    if (_sameDay(now, due)) return 'Today $time';
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    if (_sameDay(tomorrow, due)) return 'Tomorrow $time';
    return '${due.day}/${due.month} $time';
  }

  static String _formatWidgetTime(DateTime d) {
    var h = d.hour;
    final ap = h >= 12 ? 'PM' : 'AM';
    h = h % 12 == 0 ? 12 : h % 12;
    return '$h:${d.minute.toString().padLeft(2, '0')} $ap';
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    final now = DateTime.now();
    final upcoming =
        _items.where((i) => i.due != null && i.due!.isAfter(now)).toList()
          ..sort((a, b) => a.due!.compareTo(b.due!));
    if (upcoming.isEmpty) return const SizedBox.shrink();
    // The closest deadline, plus any others sharing that same (nearest) day.
    final nearest = upcoming.first.due!;
    final cluster = upcoming
        .where((i) => _sameDay(i.due!, nearest))
        .take(4)
        .toList();

    return GestureDetector(
      onTap: () => context.push('/classwork'),
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 2, 14, 8),
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFFF87171).withValues(alpha: 0.10),
              const Color(0xFFFBBF24).withValues(alpha: 0.06),
            ],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.borderAccent),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.alarm_rounded,
                  size: 16,
                  color: Color(0xFFF87171),
                ),
                const SizedBox(width: 6),
                Text(
                  cluster.length > 1 ? 'CLOSEST DEADLINES' : 'CLOSEST DEADLINE',
                  style: const TextStyle(
                    color: AppColors.accentBright,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
                const Spacer(),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: AppColors.muted,
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < cluster.length; i++) ...[
              if (i > 0)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Divider(height: 1, color: AppColors.border),
                ),
              _row(cluster[i], now),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(_Dl it, DateTime now) {
    final color = _typeColor(it.type);
    final diff = it.due!.difference(now);
    final cd = diff.inHours < 24
        ? AppColors.red
        : diff.inDays < 3
        ? const Color(0xFFFBBF24)
        : const Color(0xFF34D399);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (it.type.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  it.type,
                  style: TextStyle(
                    color: color,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 7),
            ],
            Expanded(
              child: Text(
                it.course.isEmpty ? it.title : it.course,
                style: TextStyle(
                  color: color,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          it.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.textBright,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(Icons.schedule_rounded, size: 13, color: cd),
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: _countdown(diff),
                      style: TextStyle(
                        color: cd,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    TextSpan(
                      text: '  ·  ${_fmtDue(it.due!)}',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }

  static String _countdown(Duration diff) {
    String two(int n) => n.toString().padLeft(2, '0');
    final d = diff.inDays,
        h = diff.inHours % 24,
        m = diff.inMinutes % 60,
        s = diff.inSeconds % 60;
    if (d > 0) return '${d}d ${two(h)}h ${two(m)}m ${two(s)}s';
    if (h > 0) return '${two(h)}h ${two(m)}m ${two(s)}s';
    return '${two(m)}m ${two(s)}s';
  }

  static String _fmtDue(DateTime d) {
    const mo = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ap = d.hour >= 12 ? 'PM' : 'AM';
    final timePart = (d.hour == 0 && d.minute == 0)
        ? ''
        : ', $h12:${d.minute.toString().padLeft(2, '0')} $ap';
    return '${mo[d.month - 1]} ${d.day}$timePart';
  }

  static Color _typeColor(String type) {
    final t = type.toLowerCase();
    if (t.contains('lab final') || t.contains('lab exam')) {
      return const Color(0xFFF87171);
    }
    if (t.contains('lab test')) return const Color(0xFF2DD4BF);
    if (t.contains('lab report') || t.contains('lab')) {
      return const Color(0xFF34D399);
    }
    if (t.contains('assign')) return const Color(0xFFA78BFA);
    if (t.contains('quiz') || t.contains('tutorial')) {
      return const Color(0xFF38BDF8);
    }
    if (t.contains('present')) return const Color(0xFF818CF8);
    if (t.contains('viva')) return const Color(0xFFFBBF24);
    if (t.contains('exam') || t.contains('mid') || t.contains('final')) {
      return const Color(0xFFF87171);
    }
    if (t.contains('project')) return const Color(0xFFF472B6);
    return AppColors.accentBright;
  }
}

/// Small red badge on the Classwork card showing how many classworks are
/// currently active (upcoming, not-yet-past deadlines), so users can see at a
/// glance that something is running.
class _ClassworkBadge extends StatefulWidget {
  const _ClassworkBadge();
  @override
  State<_ClassworkBadge> createState() => _ClassworkBadgeState();
}

class _ClassworkBadgeState extends State<_ClassworkBadge> {
  int _count = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await SheetsApi.instance.botSheetRaw('Deadlines');
      final now = DateTime.now();
      var n = 0;
      for (final r in rows) {
        String at(int i) => i < r.length ? r[i].trim() : '';
        final course = at(0), type = at(1), title = at(2);
        if (title.isEmpty) continue;
        if (course.toLowerCase() == 'course' || type.toLowerCase() == 'type') {
          continue;
        }
        final due = _DeadlineStripState._parseGvizDate(at(3));
        if (due != null && due.isAfter(now)) n++;
      }
      if (mounted) setState(() => _count = n);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_count <= 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      constraints: const BoxConstraints(minWidth: 18),
      decoration: BoxDecoration(
        color: const Color(0xFFF87171),
        borderRadius: BorderRadius.circular(9),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF87171).withValues(alpha: 0.5),
            blurRadius: 6,
          ),
        ],
      ),
      child: Text(
        '$_count',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// Slide-out navigation drawer (opened by the ☰ button). Holds the website's
/// header pages plus Profile and Sign Out.
class _HomeDrawer extends StatelessWidget {
  final List<({String label, IconData icon, String route})> pages;
  final dynamic student;
  const _HomeDrawer({required this.pages, required this.student});

  @override
  Widget build(BuildContext context) {
    void open(String route) {
      Scaffold.of(context).closeDrawer();
      context.push(route);
    }

    return Drawer(
      backgroundColor: AppColors.surface,
      width: 292,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: EdgeInsets.fromLTRB(
              18,
              MediaQuery.of(context).padding.top + 18,
              18,
              18,
            ),
            decoration: const BoxDecoration(gradient: AppColors.accentGradient),
            child: Row(
              children: [
                if (student != null)
                  AvatarBadge(name: student.name, size: 46, radius: 14),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        student != null ? student.name : 'CSE 62B · PORTAL',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (student != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            student.id,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (final p in pages)
                  _tile(p.icon, p.label, () => open(p.route)),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          _tile(
            Icons.person_outline_rounded,
            'Profile',
            () => open('/profile'),
          ),
          _tile(Icons.logout_rounded, 'Sign Out', () async {
            Scaffold.of(context).closeDrawer();
            await Session.instance.signOut();
            if (context.mounted) context.go('/login');
          }, danger: true),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }

  Widget _tile(
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool danger = false,
  }) {
    final color = danger ? AppColors.red : AppColors.accentBright;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                color: danger ? AppColors.red : AppColors.text,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
