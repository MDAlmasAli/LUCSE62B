import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_colors.dart';
import '../../core/sheets_api.dart';
import '../../shared/glass_card.dart';

/// Classwork hub — the Presentation / Tutorial / Lab Report / Viva / Lab Final /
/// Project categories, plus the class deadlines (from the "Deadlines" sheet)
/// with a live countdown timer, matching the website.
class ClassworkScreen extends StatefulWidget {
  const ClassworkScreen({super.key});

  @override
  State<ClassworkScreen> createState() => _ClassworkScreenState();
}

class _ClassworkScreenState extends State<ClassworkScreen> {
  late Future<List<_Item>> _future = _load();
  Timer? _ticker;

  static const _categories = <({IconData icon, String label, Color color, String slug})>[
    (icon: Icons.slideshow_rounded, label: 'Presentation', color: Color(0xFF818CF8), slug: 'presentation'),
    (icon: Icons.school_rounded, label: 'Tutorial', color: Color(0xFF38BDF8), slug: 'tutorial'),
    (icon: Icons.science_rounded, label: 'Lab Report', color: Color(0xFF34D399), slug: 'lab-report'),
    (icon: Icons.biotech_rounded, label: 'Lab Test', color: Color(0xFF2DD4BF), slug: 'lab-test'),
    (icon: Icons.mic_rounded, label: 'Viva', color: Color(0xFFFBBF24), slug: 'viva'),
    (icon: Icons.local_fire_department_rounded, label: 'Lab Final', color: Color(0xFFF87171), slug: 'lab-final'),
    (icon: Icons.account_tree_rounded, label: 'Project', color: Color(0xFFF472B6), slug: 'project'),
  ];

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<List<_Item>> _load() async {
    // Raw rows keep the GVIZ Date(y,m,d,h,mi,s) sentinels so the countdown is
    // precise to the second (the formatted sheet endpoint drops the time).
    final rows = await SheetsApi.instance.botSheetRaw('Deadlines');
    final items = _parse(rows);
    // Tick every second while there are upcoming deadlines.
    _ticker?.cancel();
    if (items.any((i) => i.deadline != null && i.deadline!.isAfter(DateTime.now()))) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Classwork'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.accent,
        backgroundColor: AppColors.card,
        onRefresh: () async {
          SheetsApi.instance.clearCache();
          _future = _load();
          await _future;
          if (mounted) setState(() {});
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
          children: [
            _sectionLabel('Categories'),
            const SizedBox(height: 10),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2.5,
              children: _categories.map(_categoryCard).toList(),
            ),
            const SizedBox(height: 20),
            FutureBuilder<List<_Item>>(
              future: _future,
              builder: (context, snap) {
                final running = (snap.data ?? [])
                    .where((i) => i.deadline != null && i.deadline!.isAfter(DateTime.now()))
                    .length;
                return Row(
                  children: [
                    _sectionLabel('Deadlines'),
                    if (running > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF87171).withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFF87171).withValues(alpha: 0.45)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(color: Color(0xFFF87171), shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 6),
                            Text('$running running',
                                style: const TextStyle(
                                    color: Color(0xFFF87171), fontSize: 11.5, fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            FutureBuilder<List<_Item>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: Center(child: CircularProgressIndicator(color: AppColors.accent)),
                  );
                }
                final items = snap.data ?? [];
                if (items.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text('No deadlines posted right now.',
                          style: TextStyle(color: AppColors.muted, fontSize: 13.5)),
                    ),
                  );
                }
                return Column(children: items.map(_deadlineCard).toList());
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String s) => Text(s.toUpperCase(),
      style: const TextStyle(
          color: AppColors.accentBright, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.6));

  Widget _categoryCard(({IconData icon, String label, Color color, String slug}) c) {
    return GestureDetector(
      onTap: () => context.push('/category/${c.slug}'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: c.color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: c.color.withValues(alpha: 0.3)),
              ),
              child: Icon(c.icon, color: c.color, size: 21),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Text(c.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppColors.text, fontSize: 13.5, fontWeight: FontWeight.w700, height: 1.15)),
            ),
          ],
        ),
      ),
    );
  }

  List<_Item> _parse(List<List<String>> rows) {
    final out = <_Item>[];
    for (final r in rows) {
      String at(int n) => n < r.length ? r[n].trim() : '';
      final course = at(0), type = at(1), title = at(2);
      if (title.isEmpty) continue;
      if (course.toLowerCase() == 'course' || type.toLowerCase() == 'type') continue;
      out.add(_Item(course: course, type: type, title: title, deadline: _parseGvizDate(at(3))));
    }
    final now = DateTime.now();
    out.sort((a, b) {
      final am = a.deadline?.difference(now).inSeconds ?? 1 << 30;
      final bm = b.deadline?.difference(now).inSeconds ?? 1 << 30;
      if (am >= 0 && bm >= 0) return am - bm; // soonest upcoming first
      if (am >= 0) return -1; // upcoming before past
      if (bm >= 0) return 1;
      return bm - am; // most-recent past first
    });
    return out;
  }

  /// Parse GVIZ `Date(y,m,d[,h,mi,s])` (month is 0-based) or a plain date string.
  static DateTime? _parseGvizDate(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    final m = RegExp(r'^Date\((\d+),(\d+),(\d+)(?:,(\d+),(\d+)(?:,(\d+))?)?\)$').firstMatch(t);
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

  Widget _deadlineCard(_Item it) {
    final typeColor = _typeColor(it.type);
    final due = it.deadline;
    final diff = due?.difference(DateTime.now());
    final isPast = diff != null && diff.isNegative;
    // Countdown urgency colour (green → amber → red), grey once past.
    final Color cd = (diff == null)
        ? AppColors.muted
        : isPast
            ? AppColors.muted
            : diff.inHours < 24
                ? AppColors.red
                : diff.inDays < 3
                    ? const Color(0xFFFBBF24)
                    : const Color(0xFF34D399);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Type badge on its own row so a long course name never collides
            // with it or gets clipped.
            if (it.type.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: typeColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                  child: Text(it.type,
                      style: TextStyle(
                          color: typeColor, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.2)),
                ),
              ),
            // Full course name + code — wraps to as many lines as needed
            // (never truncated / pushed off-screen).
            if (it.course.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1.5),
                    child: Icon(Icons.menu_book_rounded, size: 14, color: typeColor),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(it.course,
                        softWrap: true,
                        style: TextStyle(
                            color: typeColor, fontWeight: FontWeight.w700, fontSize: 13, height: 1.3)),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Text(it.title,
                softWrap: true,
                style: const TextStyle(
                    color: AppColors.textBright, fontWeight: FontWeight.w600, fontSize: 14, height: 1.4)),
            if (due != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(isPast ? Icons.event_busy_rounded : Icons.schedule_rounded, size: 14, color: cd),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(_countdownText(diff!),
                        style: TextStyle(
                            color: cd,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()])),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text('Due: ${_fmtDue(due)}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
            ],
          ],
        ),
      ),
    );
  }

  /// Live "2d 04h 09m 33s" countdown (or "Past due") — matches the website.
  static String _countdownText(Duration diff) {
    if (diff.isNegative) return 'Past due';
    String two(int n) => n.toString().padLeft(2, '0');
    final d = diff.inDays;
    final h = diff.inHours % 24, m = diff.inMinutes % 60, s = diff.inSeconds % 60;
    if (d > 0) return '${d}d ${two(h)}h ${two(m)}m ${two(s)}s';
    if (h > 0) return '${two(h)}h ${two(m)}m ${two(s)}s';
    return '${two(m)}m ${two(s)}s';
  }

  static String _fmtDue(DateTime d) {
    const mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ap = d.hour >= 12 ? 'PM' : 'AM';
    final timePart = (d.hour == 0 && d.minute == 0)
        ? ''
        : ', $h12:${d.minute.toString().padLeft(2, '0')} $ap';
    return '${mo[d.month - 1]} ${d.day}, ${d.year}$timePart';
  }

  Color _typeColor(String type) {
    final t = type.toLowerCase();
    // Order matters: check the multi-word "lab …" types before bare "lab".
    if (t.contains('lab final') || t.contains('lab exam')) return const Color(0xFFF87171);
    if (t.contains('lab test')) return const Color(0xFF2DD4BF);
    if (t.contains('lab report') || t.contains('lab')) return const Color(0xFF34D399);
    if (t.contains('assign')) return const Color(0xFFA78BFA);
    if (t.contains('quiz') || t.contains('tutorial')) return const Color(0xFF38BDF8);
    if (t.contains('present')) return const Color(0xFF818CF8);
    if (t.contains('viva')) return const Color(0xFFFBBF24);
    if (t.contains('exam') || t.contains('mid') || t.contains('final')) return const Color(0xFFF87171);
    if (t.contains('project')) return const Color(0xFFF472B6);
    return AppColors.accentBright;
  }
}

class _Item {
  final String course, type, title;
  final DateTime? deadline;
  _Item({required this.course, required this.type, required this.title, this.deadline});
}
