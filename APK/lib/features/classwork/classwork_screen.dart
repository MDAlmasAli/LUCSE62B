import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_colors.dart';
import '../../core/sheets_api.dart';
import '../../data/calendar_service.dart';
import '../../data/deadline_reminder_service.dart';
import '../../data/deadline_repository.dart';
import '../../shared/app_toast.dart';
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
  late Future<List<Deadline>> _future = _load();
  Timer? _ticker;

  static List<({IconData icon, String label, Color color, String slug})>
  get _categories =>
      <({IconData icon, String label, Color color, String slug})>[
        (
          icon: Icons.slideshow_rounded,
          label: 'Presentation',
          color: AppColors.indigoBright,
          slug: 'presentation',
        ),
        (
          icon: Icons.school_rounded,
          label: 'Tutorial',
          color: AppColors.blueBright,
          slug: 'tutorial',
        ),
        (
          icon: Icons.science_rounded,
          label: 'Lab Report',
          color: AppColors.greenBright,
          slug: 'lab-report',
        ),
        (
          icon: Icons.biotech_rounded,
          label: 'Lab Test',
          color: AppColors.tealBright,
          slug: 'lab-test',
        ),
        (
          icon: Icons.mic_rounded,
          label: 'Viva',
          color: AppColors.amberBright,
          slug: 'viva',
        ),
        (
          icon: Icons.local_fire_department_rounded,
          label: 'Lab Final',
          color: AppColors.redBright,
          slug: 'lab-final',
        ),
        (
          icon: Icons.account_tree_rounded,
          label: 'Project',
          color: AppColors.pinkBright,
          slug: 'project',
        ),
      ];

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<List<Deadline>> _load() async {
    final items = await DeadlineRepository.instance.load();
    // The list is in hand, so re-arm the "due tomorrow" / "due in 2 hours"
    // reminders from it rather than fetching the sheet a second time.
    unawaited(DeadlineReminderService.instance.scheduleFrom(items));
    // Tick every second while there are upcoming deadlines. The screen can be
    // closed while the sheet is still loading, and a timer started after
    // dispose would never be cancelled again.
    _ticker?.cancel();
    if (mounted &&
        items.any((i) => i.due != null && i.due!.isAfter(DateTime.now()))) {
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
            FutureBuilder<List<Deadline>>(
              future: _future,
              builder: (context, snap) {
                final running = (snap.data ?? [])
                    .where(
                      (i) => i.due != null && i.due!.isAfter(DateTime.now()),
                    )
                    .length;
                return Row(
                  children: [
                    _sectionLabel('Deadlines'),
                    if (running > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFFF87171,
                          ).withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: const Color(
                              0xFFF87171,
                            ).withValues(alpha: 0.45),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: AppColors.redBright,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '$running running',
                              style: TextStyle(
                                color: AppColors.redBright,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            FutureBuilder<List<Deadline>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: Center(
                      child: CircularProgressIndicator(color: AppColors.accent),
                    ),
                  );
                }
                final items = snap.data ?? [];
                if (items.isEmpty) {
                  return Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'No deadlines posted right now.',
                        style: TextStyle(
                          color: AppColors.muted,
                          fontSize: 13.5,
                        ),
                      ),
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

  Widget _sectionLabel(String s) => Text(
    s.toUpperCase(),
    style: TextStyle(
      color: AppColors.accentBright,
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.6,
    ),
  );

  Widget _categoryCard(
    ({IconData icon, String label, Color color, String slug}) c,
  ) {
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
              child: Text(
                c.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _deadlineCard(Deadline it) {
    final typeColor = _typeColor(it.type);
    final due = it.due;
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
        ? AppColors.amberBright
        : AppColors.greenBright;

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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    it.type,
                    style: TextStyle(
                      color: typeColor,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
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
                    child: Icon(
                      Icons.menu_book_rounded,
                      size: 14,
                      color: typeColor,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      it.course,
                      softWrap: true,
                      style: TextStyle(
                        color: typeColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Text(
              it.title,
              softWrap: true,
              style: TextStyle(
                color: AppColors.textBright,
                fontWeight: FontWeight.w600,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            if (due != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    isPast ? Icons.event_busy_rounded : Icons.schedule_rounded,
                    size: 14,
                    color: cd,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _countdownText(diff!),
                      style: TextStyle(
                        color: cd,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  if (!isPast)
                    IconButton(
                      tooltip: 'Add to calendar',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        Icons.event_available_rounded,
                        color: AppColors.accentBright,
                        size: 20,
                      ),
                      onPressed: () async {
                        final ok = await CalendarService.addDeadline(
                          course: it.course,
                          type: it.type,
                          title: it.title,
                          deadline: due,
                        );
                        if (!mounted) return;
                        if (!ok) {
                          AppToast.show(
                            context,
                            'Could not open calendar.',
                            error: true,
                          );
                        }
                      },
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                'Due: ${_fmtDue(due)}',
                style: TextStyle(color: AppColors.muted, fontSize: 11.5),
              ),
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
    final h = diff.inHours % 24,
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
    return '${mo[d.month - 1]} ${d.day}, ${d.year}$timePart';
  }

  Color _typeColor(String type) {
    final t = type.toLowerCase();
    // Order matters: check the multi-word "lab …" types before bare "lab".
    if (t.contains('lab final') || t.contains('lab exam')) {
      return AppColors.redBright;
    }
    if (t.contains('lab test')) return AppColors.tealBright;
    if (t.contains('lab report') || t.contains('lab')) {
      return AppColors.greenBright;
    }
    if (t.contains('assign')) return AppColors.accentBright;
    if (t.contains('quiz') || t.contains('tutorial')) {
      return AppColors.blueBright;
    }
    if (t.contains('present')) return AppColors.indigoBright;
    if (t.contains('viva')) return AppColors.amberBright;
    if (t.contains('exam') || t.contains('mid') || t.contains('final')) {
      return AppColors.redBright;
    }
    if (t.contains('project')) return AppColors.pinkBright;
    return AppColors.accentBright;
  }
}
