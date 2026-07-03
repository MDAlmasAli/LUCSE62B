import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_colors.dart';
import '../../data/routine_grid_repository.dart';
import '../../data/session.dart';
import 'routine_export.dart';
import 'routine_template.dart';

/// Class Routine — a weekly grid (days × time slots) for any batch/section,
/// with today highlighting and a "My Courses" filter. Mirrors the website's
/// routine grid.
class RoutineScreen extends StatefulWidget {
  const RoutineScreen({super.key});

  @override
  State<RoutineScreen> createState() => _RoutineScreenState();
}

class _RoutineScreenState extends State<RoutineScreen> {
  final _repo = RoutineGridRepository.instance;
  RoutineGridData? _data;
  bool _loading = true;
  String? _error;
  Set<String> _excluded = {};
  List<CustomCourse> _customs = [];
  List<CustomCourse> _enrollments = [];

  static const _dayW = 92.0;
  static const _timeW = 118.0;

  String? get _studentId {
    final s = Session.instance.student;
    return (s != null && !s.isDemo) ? s.id : null;
  }

  bool get _is62B => _data?.batch == '62' && _data?.section == 'B';
  List<CustomCourse> get _personalCourses => [..._customs, ..._enrollments];

  String get _todayName {
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
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    if (refresh) _repo.invalidate();
    try {
      var data = await _repo.load();
      final id = _studentId;
      if (id != null) _excluded = await _repo.loadExcluded(id);
      // 62B students can add custom courses — merge them into the grid.
      if (id != null && data.batch == '62' && data.section == 'B') {
        final personal = await Future.wait([
          _repo.loadCustomCourses(id),
          _repo.loadEnrollmentCourses(id),
        ]);
        _customs = personal[0];
        _enrollments = personal[1];
        if (_personalCourses.isNotEmpty) {
          data = _repo.buildFor('62', 'B', customs: _personalCourses);
        }
      }
      if (mounted) {
        setState(() {
          _data = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load the routine right now.';
        });
      }
    }
  }

  void _select(String batch, String section) {
    setState(
      () => _data = _repo.buildFor(batch, section, customs: _personalCourses),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Class Routine'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/info'),
        ),
        actions: [
          if (!_loading && _data != null)
            IconButton(
              tooltip: 'Download',
              icon: const Icon(Icons.download_rounded, size: 22),
              onPressed: _download,
            ),
          if (_studentId != null && _is62B && !_loading)
            IconButton(
              tooltip: 'Custom courses',
              icon: const Icon(Icons.add_circle_outline_rounded, size: 22),
              onPressed: _openCustomCourses,
            ),
          if (_studentId != null && _is62B && !_loading)
            IconButton(
              tooltip: 'My Courses',
              icon: const Icon(Icons.checklist_rounded, size: 22),
              onPressed: _openMyCourses,
            ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            )
          : _error != null || _data == null
          ? _errorView()
          : _body(_data!),
    );
  }

  Widget _body(RoutineGridData d) {
    return RefreshIndicator(
      color: AppColors.accent,
      backgroundColor: AppColors.card,
      onRefresh: () => _load(refresh: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        children: [
          if (d.available.length > 1) _selector(d),
          _syncBadge(d),
          const SizedBox(height: 14),
          if (d.groups.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Center(
                child: Text(
                  'No schedule found for Batch ${d.batch}, Section ${d.section}.',
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 13.5,
                  ),
                ),
              ),
            )
          else
            for (var i = 0; i < d.groups.length; i++) ...[
              if (i > 0) const SizedBox(height: 16),
              _gridTable(d, d.groups[i]),
            ],
        ],
      ),
    );
  }

  Widget _selector(RoutineGridData d) {
    final batches = {for (final c in d.available) c.batch}.toList();
    final sections = d.available
        .where((c) => c.batch == d.batch)
        .map((c) => c.section)
        .toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, size: 16, color: AppColors.accentBright),
          const SizedBox(width: 8),
          const Text(
            'Batch',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(width: 6),
          _dropdown(d.batch, batches, (v) {
            if (v == null) return;
            final secs = d.available
                .where((c) => c.batch == v)
                .map((c) => c.section)
                .toList();
            _select(
              v,
              secs.contains(d.section)
                  ? d.section
                  : (secs.isNotEmpty ? secs.first : 'A'),
            );
          }),
          const SizedBox(width: 14),
          const Text(
            'Section',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(width: 6),
          _dropdown(d.section, sections, (v) {
            if (v != null) _select(d.batch, v);
          }),
        ],
      ),
    );
  }

  Widget _dropdown(
    String value,
    List<String> items,
    ValueChanged<String?> onChanged,
  ) {
    final safe = items.contains(value)
        ? value
        : (items.isNotEmpty ? items.first : value);
    return DropdownButton<String>(
      value: safe,
      isDense: true,
      dropdownColor: AppColors.card,
      underline: const SizedBox.shrink(),
      style: const TextStyle(
        color: AppColors.text,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
      icon: const Icon(Icons.arrow_drop_down, color: AppColors.muted, size: 20),
      items: items
          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
          .toList(),
      onChanged: onChanged,
    );
  }

  Widget _syncBadge(RoutineGridData d) {
    final now = TimeOfDay.now();
    final h12 = now.hourOfPeriod == 0 ? 12 : now.hourOfPeriod;
    final t =
        '$h12:${now.minute.toString().padLeft(2, '0')} ${now.period == DayPeriod.am ? 'AM' : 'PM'}';
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            color: Color(0xFF34D399),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            'Live sync · ${d.semester} · Updated $t',
            style: const TextStyle(color: AppColors.muted, fontSize: 11.5),
          ),
        ),
      ],
    );
  }

  Widget _gridTable(RoutineGridData d, GridGroup g) {
    // day → time → slots
    final lookup = <String, Map<String, List<GridSlot>>>{};
    for (final day in g.days) {
      lookup[day] = {};
      for (final s in d.schedule[day] ?? <GridSlot>[]) {
        lookup[day]!.putIfAbsent(s.time, () => []).add(s);
      }
    }
    final visibleDays = g.days
        .where((day) => (d.schedule[day] ?? []).any((s) => !s.isBreak))
        .toList();

    final rows = <TableRow>[
      TableRow(
        decoration: const BoxDecoration(color: AppColors.surface),
        children: [
          _headCell('Day'),
          for (final time in g.allTimes)
            _headCell(time, isBreak: g.breakTimes.contains(time)),
        ],
      ),
    ];
    for (final day in visibleDays) {
      final isToday = day == _todayName;
      rows.add(
        TableRow(
          decoration: BoxDecoration(
            color: isToday ? AppColors.accent.withValues(alpha: 0.08) : null,
          ),
          children: [
            _dayCell(day, isToday),
            for (final time in g.allTimes)
              _bodyCell(
                d,
                lookup[day]?[time] ?? const [],
                g.breakTimes.contains(time),
              ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: _dayW + _timeW * g.allTimes.length,
        child: Table(
          border: TableBorder.all(color: AppColors.border, width: 1),
          defaultColumnWidth: const FixedColumnWidth(_timeW),
          columnWidths: const {0: FixedColumnWidth(_dayW)},
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: rows,
        ),
      ),
    );
  }

  Widget _headCell(String text, {bool isBreak = false}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: isBreak ? AppColors.muted : AppColors.textSecondary,
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
          _title(day),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isToday ? AppColors.accentBright : AppColors.textBright,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (isToday) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              gradient: AppColors.accentGradient,
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

  Widget _bodyCell(RoutineGridData d, List<GridSlot> slots, bool isBreakCol) {
    if (isBreakCol) {
      final isBreak = slots.any((s) => s.isBreak);
      return Padding(
        padding: const EdgeInsets.all(6),
        child: Center(
          child: Text(
            isBreak ? '☕ Break' : '',
            style: const TextStyle(color: AppColors.muted, fontSize: 10),
          ),
        ),
      );
    }
    final courses = slots.where((s) => !s.isBreak).where((s) {
      if (s.isCustom) return true; // custom courses are never filtered out
      if (_is62B && _excluded.contains(s.code.toUpperCase())) return false;
      return true;
    }).toList();
    if (courses.isEmpty) {
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
        children: courses.map((s) => _courseCard(d, s)).toList(),
      ),
    );
  }

  Widget _courseCard(RoutineGridData d, GridSlot s) {
    final color = s.isEnrollment
        ? const Color(0xFF38BDF8)
        : s.isCustom
        ? const Color(0xFF10B981)
        : _courseColor(s.code);
    final name = d.nameFor(s);
    final teacher = d.teacherFor(s);
    return Container(
      margin: const EdgeInsets.only(bottom: 3),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: color.withValues(alpha: s.isCustom ? 0.55 : 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (s.isCustom)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 5,
                    height: 5,
                    decoration: const BoxDecoration(
                      color: Color(0xFF10B981),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    s.isEnrollment ? 'ENROLLED' : 'CUSTOM',
                    style: TextStyle(
                      color: color,
                      fontSize: 6.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          Text(
            name.isNotEmpty ? name : s.code,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 9.5,
              height: 1.2,
            ),
          ),
          if (name.isNotEmpty)
            Text(
              s.code,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color.withValues(alpha: 0.7),
                fontSize: 8,
                fontWeight: FontWeight.w700,
              ),
            ),
          if (teacher.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                teacher,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 8.5,
                  height: 1.2,
                ),
              ),
            ),
          if (s.room.isNotEmpty)
            Text(
              s.room,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, fontSize: 8),
            ),
        ],
      ),
    );
  }

  Future<void> _openMyCourses() async {
    final d = _data;
    final id = _studentId;
    if (d == null || id == null) return;
    // All 62B course codes (unique) → name.
    final codes = <String, String>{};
    for (final slots in d.schedule.values) {
      for (final s in slots) {
        if (!s.isBreak && s.code.isNotEmpty) {
          codes[s.code.toUpperCase()] = d.nameFor(s);
        }
      }
    }
    final entries = codes.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final checked = {
      for (final e in entries) e.key: !_excluded.contains(e.key),
    };

    final saved = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.9,
          builder: (ctx, scroll) => Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 14, 18, 4),
                child: Text(
                  'My 62B Courses',
                  style: TextStyle(
                    color: AppColors.textBright,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 0, 18, 8),
                child: Text(
                  'Uncheck the courses you are NOT taking this semester. They’ll be hidden from your routine.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                  children: entries.map((e) {
                    return CheckboxListTile(
                      value: checked[e.key],
                      onChanged: (v) =>
                          setSheet(() => checked[e.key] = v ?? true),
                      activeColor: AppColors.accent,
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                      title: Text(
                        e.key,
                        style: const TextStyle(
                          color: AppColors.accentBright,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'monospace',
                          fontSize: 13,
                        ),
                      ),
                      subtitle: e.value.isEmpty
                          ? null
                          : Text(
                              e.value,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                    );
                  }).toList(),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  6,
                  16,
                  MediaQuery.of(ctx).padding.bottom + 14,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(ctx, true),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Save My Courses'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (saved == true) {
      final excluded = {
        for (final e in entries)
          if (checked[e.key] == false) e.key,
      };
      setState(() => _excluded = excluded);
      _repo.saveExcluded(id, excluded);
    }
  }

  static int _min(String t) {
    final m = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(t);
    if (m == null) return 9999;
    var h = int.parse(m[1]!);
    if (h < 8) h += 12;
    return h * 60 + int.parse(m[2]!);
  }

  static const _dayShort = {
    'SATURDAY': 'Sat',
    'SUNDAY': 'Sun',
    'MONDAY': 'Mon',
    'TUESDAY': 'Tue',
    'WEDNESDAY': 'Wed',
    'THURSDAY': 'Thu',
    'FRIDAY': 'Fri',
  };

  Future<void> _openCustomCourses() async {
    final id = _studentId;
    final d = _data;
    if (id == null || d == null) return;
    final times = <String>{};
    for (final g in d.groups) {
      times.addAll(g.allTimes.where((t) => RegExp(r'\d+:\d+').hasMatch(t)));
    }
    final timeList = times.toList()..sort((a, b) => _min(a).compareTo(_min(b)));
    const days = [
      'SATURDAY',
      'SUNDAY',
      'MONDAY',
      'TUESDAY',
      'WEDNESDAY',
      'THURSDAY',
      'FRIDAY',
    ];

    final nameC = TextEditingController();
    final codeC = TextEditingController();
    final teachC = TextEditingController();
    final roomC = TextEditingController();
    var day = days.first;
    String? time = timeList.isNotEmpty ? timeList.first : null;

    Future<void> persist() async {
      await _repo.saveCustomCourses(id, _customs);
      if (mounted) {
        setState(
          () => _data = _repo.buildFor('62', 'B', customs: _personalCourses),
        );
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          builder: (ctx, scroll) => Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: const [
                    Icon(
                      Icons.add_circle_outline_rounded,
                      color: Color(0xFF10B981),
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Custom Courses',
                      style: TextStyle(
                        color: AppColors.textBright,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Add a course to your 62B routine (e.g. a retake or a course not in the default schedule). Saved to your account.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                // Existing list
                if (_customs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      'No custom courses added yet.',
                      style: TextStyle(color: AppColors.muted, fontSize: 12.5),
                    ),
                  )
                else
                  ..._customs.map(
                    (c) => Container(
                      margin: const EdgeInsets.only(bottom: 7),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFF10B981),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  c.name.isEmpty ? c.code : c.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.text,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  [
                                    _dayShort[c.day] ?? c.day,
                                    c.time,
                                    if (c.teacher.isNotEmpty) c.teacher,
                                    if (c.room.isNotEmpty) c.room,
                                    if (c.code.isNotEmpty) c.code,
                                  ].join(' · '),
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              _customs = _customs
                                  .where((x) => x.id != c.id)
                                  .toList();
                              await persist();
                              setSheet(() {});
                            },
                            child: const Text(
                              'Remove',
                              style: TextStyle(
                                color: AppColors.red,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const Divider(color: AppColors.border, height: 28),
                const Text(
                  'ADD A COURSE',
                  style: TextStyle(
                    color: AppColors.accentBright,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 10),
                _field(nameC, 'Course name', 'e.g. Calculus II'),
                const SizedBox(height: 9),
                Row(
                  children: [
                    Expanded(
                      child: _field(codeC, 'Course code', 'e.g. MAT-1201'),
                    ),
                    const SizedBox(width: 9),
                    Expanded(child: _field(roomC, 'Room', 'e.g. 504')),
                  ],
                ),
                const SizedBox(height: 9),
                _field(teachC, 'Teacher', 'optional'),
                const SizedBox(height: 9),
                Row(
                  children: [
                    Expanded(
                      child: _sheetDropdown<String>(
                        label: 'Day',
                        value: day,
                        items: days,
                        itemLabel: (v) => _dayShort[v] ?? v,
                        onChanged: (v) => setSheet(() => day = v ?? day),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: _sheetDropdown<String?>(
                        label: 'Time',
                        value: time,
                        items: timeList.isEmpty ? <String?>[null] : timeList,
                        itemLabel: (v) => v ?? '—',
                        onChanged: (v) => setSheet(() => time = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final name = nameC.text.trim();
                      final code = codeC.text.trim();
                      if (name.isEmpty && code.isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text('Enter a course name or code.'),
                          ),
                        );
                        return;
                      }
                      if (time == null) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('Pick a time slot.')),
                        );
                        return;
                      }
                      _customs = [
                        ..._customs,
                        CustomCourse(
                          id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
                          name: name,
                          code: code,
                          teacher: teachC.text.trim(),
                          room: roomC.text.trim(),
                          day: day,
                          time: time!,
                        ),
                      ];
                      await persist();
                      nameC.clear();
                      codeC.clear();
                      teachC.clear();
                      roomC.clear();
                      setSheet(() {});
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add to my routine'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    nameC.dispose();
    codeC.dispose();
    teachC.dispose();
    roomC.dispose();
  }

  Widget _field(TextEditingController c, String label, String hint) =>
      TextField(
        controller: c,
        style: const TextStyle(color: AppColors.text, fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
        ),
      );

  Widget _sheetDropdown<T>({
    required String label,
    required T value,
    required List<T> items,
    required String Function(T) itemLabel,
    required ValueChanged<T?> onChanged,
  }) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          dropdownColor: AppColors.card,
          style: const TextStyle(
            color: AppColors.text,
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
          items: items
              .map(
                (e) => DropdownMenuItem<T>(value: e, child: Text(itemLabel(e))),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  void _download() {
    final d = _data;
    if (d == null) return;
    RoutineExport.showImageSheet(
      context,
      baseName: 'class-routine-${d.batch}-${d.section}',
      build: () => RoutinePrintTemplate(
        title: 'Class Routine — Batch ${d.batch}, Section ${d.section}',
        subtitle: d.semester,
        groups: _printGroups(d),
      ),
    );
  }

  static String _dayFull(String day) =>
      day.isEmpty ? day : day[0] + day.substring(1).toLowerCase();

  List<PrintGroup> _printGroups(RoutineGridData d) {
    final out = <PrintGroup>[];
    for (final g in d.groups) {
      final lookup = <String, Map<String, List<GridSlot>>>{};
      for (final day in g.days) {
        lookup[day] = {};
        for (final s in d.schedule[day] ?? <GridSlot>[]) {
          lookup[day]!.putIfAbsent(s.time, () => []).add(s);
        }
      }
      final rows = <PrintRow>[];
      for (var ri = 0; ri < g.days.length; ri++) {
        final day = g.days[ri];
        final hasClass = (d.schedule[day] ?? []).any((s) => !s.isBreak);
        if (!hasClass) continue;
        final courses = <String, List<PrintCell>>{};
        final breaks = <String>{};
        for (final time in g.allTimes) {
          final slots = lookup[day]?[time] ?? const [];
          if (g.breakTimes.contains(time)) {
            if (slots.any((s) => s.isBreak)) breaks.add(time);
            continue;
          }
          final list = slots
              .where((s) => !s.isBreak)
              .where(
                (s) =>
                    s.isCustom ||
                    !(_is62B && _excluded.contains(s.code.toUpperCase())),
              )
              .map((s) {
                final name = d.nameFor(s), teacher = d.teacherFor(s);
                return PrintCell(
                  title2: name.isNotEmpty ? name : s.code,
                  code: name.isNotEmpty ? s.code : '',
                  line2: teacher,
                  room: s.room,
                  color: printCourseColor(s.code),
                );
              })
              .toList();
          if (list.isNotEmpty) courses[time] = list;
        }
        rows.add(
          PrintRow(
            dayLabel: _dayFull(day),
            even: ri % 2 == 0,
            courses: courses,
            breaks: breaks,
          ),
        );
      }
      out.add(
        PrintGroup(times: g.allTimes, breakTimes: g.breakTimes, rows: rows),
      );
    }
    return out;
  }

  Widget _errorView() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.calendar_month_rounded,
          color: AppColors.muted,
          size: 34,
        ),
        const SizedBox(height: 12),
        Text(
          _error ?? 'Could not load the routine.',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 14),
        OutlinedButton(onPressed: _load, child: const Text('Retry')),
      ],
    ),
  );

  String _title(String day) => day[0] + day.substring(1, 3).toLowerCase();

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
}
