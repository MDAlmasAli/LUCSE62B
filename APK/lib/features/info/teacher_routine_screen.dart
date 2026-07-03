import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_colors.dart';
import '../../data/routine_grid_repository.dart';
import 'routine_export.dart';
import 'routine_template.dart';

/// Teacher Class Routine — pick a teacher and see their full weekly schedule
/// across every section (built from the shared routine). Mirrors the website's
/// teacher-routine view.
class TeacherRoutineScreen extends StatefulWidget {
  const TeacherRoutineScreen({super.key});

  @override
  State<TeacherRoutineScreen> createState() => _TeacherRoutineScreenState();
}

class _TeacherRoutineScreenState extends State<TeacherRoutineScreen> {
  late Future<TeacherRoutineData> _future = RoutineGridRepository.instance
      .loadTeacherRoutine();
  String _query = '';

  static const _accent = Color(0xFF14B8A6);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Teacher Routine'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/info'),
        ),
      ),
      body: FutureBuilder<TeacherRoutineData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            );
          }
          final data = snap.data;
          if (data == null || data.teachers.isEmpty) {
            return _empty();
          }
          final teachers = _query.isEmpty
              ? data.teachers
              : data.teachers
                    .where(
                      (t) =>
                          t.name.toLowerCase().contains(_query) ||
                          t.acr.toLowerCase().contains(_query),
                    )
                    .toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                child: TextField(
                  onChanged: (v) =>
                      setState(() => _query = v.toLowerCase().trim()),
                  decoration: const InputDecoration(
                    hintText: 'Search teacher by name or initials…',
                    prefixIcon: Icon(
                      Icons.search,
                      size: 18,
                      color: AppColors.muted,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  color: AppColors.accent,
                  backgroundColor: AppColors.card,
                  onRefresh: () async {
                    RoutineGridRepository.instance.invalidate();
                    setState(
                      () => _future = RoutineGridRepository.instance
                          .loadTeacherRoutine(),
                    );
                    await _future;
                  },
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
                    itemCount: teachers.length,
                    itemBuilder: (_, i) {
                      final t = teachers[i];
                      return _teacherCard(
                        t.acr,
                        t.name,
                        t.classes,
                        data.byTeacher[t.acr] ?? const [],
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _teacherCard(
    String acr,
    String name,
    int classes,
    List<TeacherClass> list,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  _TeacherDetailScreen(name: name, acr: acr, classes: list),
            ),
          ),
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _accent.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    _initials(name, acr),
                    style: const TextStyle(
                      color: _accent,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textBright,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$acr · $classes class${classes == 1 ? '' : 'es'} / week',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.muted,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _initials(String name, String acr) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return acr.isNotEmpty ? acr.substring(0, acr.length.clamp(0, 2)) : '?';
    }
    if (parts.length == 1) {
      return parts.first
          .substring(0, parts.first.length.clamp(0, 2))
          .toUpperCase();
    }
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  Widget _empty() => Center(
    child: Padding(
      padding: const EdgeInsets.all(34),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.person_search_rounded,
            color: AppColors.muted,
            size: 40,
          ),
          const SizedBox(height: 12),
          const Text(
            'No teacher routine available right now.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: () => setState(
              () =>
                  _future = RoutineGridRepository.instance.loadTeacherRoutine(),
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    ),
  );
}

class _TeacherDetailScreen extends StatelessWidget {
  final String name, acr;
  final List<TeacherClass> classes;
  const _TeacherDetailScreen({
    required this.name,
    required this.acr,
    required this.classes,
  });

  static const _accent = Color(0xFF14B8A6);
  static const _dayOrder = [
    'SATURDAY',
    'SUNDAY',
    'MONDAY',
    'TUESDAY',
    'WEDNESDAY',
    'THURSDAY',
    'FRIDAY',
  ];

  static const _dayW = 80.0;
  static const _timeW = 122.0;

  static int _toMin(String t) {
    final m = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(t);
    if (m == null) return 9999;
    var h = int.parse(m[1]!);
    final mi = int.parse(m[2]!);
    if (h < 8) h += 12;
    return h * 60 + mi;
  }

  static String _todayName() {
    const map = {
      DateTime.saturday: 'SATURDAY',
      DateTime.sunday: 'SUNDAY',
      DateTime.monday: 'MONDAY',
      DateTime.tuesday: 'TUESDAY',
      DateTime.wednesday: 'WEDNESDAY',
      DateTime.thursday: 'THURSDAY',
      DateTime.friday: 'FRIDAY',
    };
    return map[DateTime.now().weekday] ?? '';
  }

  @override
  Widget build(BuildContext context) {
    // Build a weekly grid: rows = days with classes, columns = distinct times.
    final byDay = <String, List<TeacherClass>>{};
    for (final c in classes) {
      byDay.putIfAbsent(c.day, () => []).add(c);
    }
    final days = _dayOrder.where(byDay.containsKey).toList();
    // Distinct time columns (canonical label per time key), sorted by minute.
    final timeKey = <int, String>{};
    for (final c in classes) {
      timeKey.putIfAbsent(_toMin(c.time), () => c.time);
    }
    final times = (timeKey.keys.toList()..sort())
        .map((k) => timeKey[k]!)
        .toList();
    // day → timeLabel → classes
    final lookup = <String, Map<String, List<TeacherClass>>>{};
    for (final c in classes) {
      final tl = timeKey[_toMin(c.time)]!;
      lookup.putIfAbsent(c.day, () => {}).putIfAbsent(tl, () => []).add(c);
    }
    final today = _todayName();

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (classes.isNotEmpty)
            Builder(
              builder: (ctx) => IconButton(
                tooltip: 'Download',
                icon: const Icon(Icons.download_rounded, size: 22),
                onPressed: () => _download(ctx, days, times, lookup),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
        children: [
          _header(),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: _dayW + _timeW * times.length,
              child: Table(
                border: TableBorder.all(color: AppColors.border, width: 1),
                defaultColumnWidth: const FixedColumnWidth(_timeW),
                columnWidths: const {0: FixedColumnWidth(_dayW)},
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: [
                  TableRow(
                    decoration: const BoxDecoration(color: AppColors.surface),
                    children: [
                      _headCell('Day'),
                      for (final t in times) _headCell(t),
                    ],
                  ),
                  for (final day in days)
                    TableRow(
                      decoration: BoxDecoration(
                        color: day == today
                            ? _accent.withValues(alpha: 0.08)
                            : null,
                      ),
                      children: [
                        _dayCell(day, day == today),
                        for (final t in times)
                          _cell(lookup[day]?[t] ?? const []),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _download(
    BuildContext context,
    List<String> days,
    List<String> times,
    Map<String, Map<String, List<TeacherClass>>> lookup,
  ) {
    final printRows = <PrintRow>[];
    for (var i = 0; i < days.length; i++) {
      final day = days[i];
      final courses = <String, List<PrintCell>>{};
      for (final time in times) {
        final list = lookup[day]?[time] ?? const <TeacherClass>[];
        if (list.isEmpty) continue;
        courses[time] = [
          for (final c in list)
            PrintCell(
              title2: c.courseName.isNotEmpty ? c.courseName : c.code,
              code: c.courseName.isNotEmpty ? c.code : '',
              line2: '${c.batch}-${c.section}',
              room: c.room,
              color: printCourseColor(c.code),
            ),
        ];
      }
      printRows.add(
        PrintRow(
          dayLabel: _title(day),
          even: i.isEven,
          courses: courses,
          breaks: const {},
        ),
      );
    }
    RoutineExport.showImageSheet(
      context,
      baseName: 'teacher-routine-$acr',
      build: () => RoutinePrintTemplate(
        title: '$name ($acr)',
        subtitle:
            'Teacher Routine · ${classes.length} class${classes.length == 1 ? '' : 'es'} per week',
        groups: [
          PrintGroup(times: times, breakTimes: const {}, rows: printRows),
        ],
      ),
    );
  }

  Widget _headCell(String text) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _dayCell(String day, bool isToday) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _title(day).substring(0, 3),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isToday ? _accent : AppColors.textBright,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (isToday) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: _accent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'Today',
              style: TextStyle(
                color: Colors.white,
                fontSize: 8,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ],
    ),
  );

  Widget _cell(List<TeacherClass> list) {
    if (list.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Center(
          child: Text(
            '—',
            style: TextStyle(color: AppColors.muted, fontSize: 13),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: list.map(_courseCard).toList(),
      ),
    );
  }

  Widget _courseCard(TeacherClass c) {
    final color = _courseColor(c.code);
    return Container(
      margin: const EdgeInsets.only(bottom: 3),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Text(
            c.courseName.isNotEmpty ? c.courseName : c.code,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 9.5,
              height: 1.2,
            ),
          ),
          if (c.courseName.isNotEmpty)
            Text(
              c.code,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color.withValues(alpha: 0.7),
                fontSize: 8,
                fontWeight: FontWeight.w700,
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '${c.batch}-${c.section}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 8.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (c.room.isNotEmpty)
            Text(
              c.room,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, fontSize: 8),
            ),
        ],
      ),
    );
  }

  Color _courseColor(String code) {
    var h = 0;
    for (var i = 0; i < code.length; i++) {
      h = (h * 31 + code.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    const palette = [
      Color(0xFFA78BFA),
      Color(0xFF38BDF8),
      Color(0xFF34D399),
      Color(0xFFF87171),
      Color(0xFFFBBF24),
      Color(0xFFF472B6),
      Color(0xFF22D3EE),
      Color(0xFFC084FC),
    ];
    return palette[h % palette.length];
  }

  Widget _header() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _accent.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _accent.withValues(alpha: 0.25)),
    ),
    child: Row(
      children: [
        const Icon(Icons.calendar_month_rounded, color: _accent, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '$acr · ${classes.length} class${classes.length == 1 ? '' : 'es'} per week',
            style: const TextStyle(
              color: AppColors.textBright,
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
            ),
          ),
        ),
      ],
    ),
  );

  static String _title(String day) =>
      day.isEmpty ? day : day[0] + day.substring(1).toLowerCase();
}
