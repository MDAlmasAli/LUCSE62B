import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_colors.dart';
import '../../shared/app_toast.dart';

class _Section {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final String? route;
  const _Section(
    this.icon,
    this.title,
    this.subtitle,
    this.accent, [
    this.route,
  ]);
}

/// Info hub — landing screen listing all the class-info sections, mirroring the
/// website's Info page. Each row opens a dedicated screen.
class InfoHubScreen extends StatelessWidget {
  const InfoHubScreen({super.key});

  static const _sections = <_Section>[
    _Section(
      Icons.calendar_month_rounded,
      'Class Routine',
      'Weekly class schedule',
      Color(0xFF7C3AED),
      '/info/routine',
    ),
    _Section(
      Icons.co_present_rounded,
      'Teacher Routine',
      "Any teacher's weekly schedule",
      Color(0xFF0EA5E9),
      '/info/teacher-routine',
    ),
    _Section(
      Icons.event_note_rounded,
      'Exam Schedule',
      'Mid & final term routine',
      Color(0xFFDC2626),
      '/info/exam',
    ),
    _Section(
      Icons.directions_bus_rounded,
      'Bus Schedule',
      'University transport times',
      Color(0xFF0891B2),
      '/info/bus',
    ),
    _Section(
      Icons.person_rounded,
      'Teachers',
      'Course teachers & contacts',
      Color(0xFF059669),
      '/info/teachers',
    ),
    _Section(
      Icons.co_present_rounded,
      'Course Teachers',
      'Who teaches what · by teacher / course',
      Color(0xFF14B8A6),
      '/info/course-teachers',
    ),
    _Section(
      Icons.format_list_bulleted_rounded,
      'Course Offer',
      'All-batch course offer',
      Color(0xFF6366F1),
      '/info/courses',
    ),
    _Section(
      Icons.replay_rounded,
      'Retake & Improve',
      'Retake/improve enrollment',
      Color(0xFFD97706),
      '/info/retake',
    ),
    _Section(
      Icons.link_rounded,
      'Group Links & Codes',
      'Class group join links',
      Color(0xFF2563EB),
      '/info/links',
    ),
    _Section(
      Icons.payments_rounded,
      'bKash Payment',
      'Fees codes & methods',
      Color(0xFFEC4899),
      '/info/bkash',
    ),
    _Section(
      Icons.school_rounded,
      'Semester Info',
      'Key academic dates',
      Color(0xFF8B5CF6),
      '/info/semester',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Info'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
        itemCount: _sections.length,
        itemBuilder: (context, i) {
          final s = _sections[i];
          return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      if (s.route != null) {
                        context.push(s.route!);
                      } else {
                        AppToast.show(context, '${s.title} — coming soon');
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: s.accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: s.accent.withValues(alpha: 0.28),
                              ),
                            ),
                            child: Icon(s.icon, color: s.accent, size: 21),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.title,
                                  style: const TextStyle(
                                    color: AppColors.textBright,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  s.subtitle,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right,
                            color: AppColors.muted,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
              .animate()
              .fadeIn(delay: (40 * i).ms, duration: 260.ms)
              .moveX(begin: 10, end: 0, curve: Curves.easeOut);
        },
      ),
    );
  }
}
