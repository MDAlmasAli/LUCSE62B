import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_colors.dart';
import '../../data/home_widget_service.dart';
import '../../shared/app_toast.dart';

class CalendarWidgetScreen extends StatefulWidget {
  const CalendarWidgetScreen({super.key});

  @override
  State<CalendarWidgetScreen> createState() => _CalendarWidgetScreenState();
}

class _CalendarWidgetScreenState extends State<CalendarWidgetScreen> {
  bool _pinSupported = false;

  @override
  void initState() {
    super.initState();
    HomeWidgetService.instance.canPin().then((value) {
      if (mounted) setState(() => _pinSupported = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Calendar & Home Widget'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          _card(
            Icons.widgets_rounded,
            'Android Home Widget',
            'See your current/next class, room and nearest deadline without '
                'opening the app.',
            FilledButton.icon(
              onPressed: _pinSupported
                  ? () async {
                      await HomeWidgetService.instance.requestPin();
                      if (context.mounted) {
                        AppToast.show(
                          context,
                          'Widget request sent to launcher.',
                        );
                      }
                    }
                  : null,
              icon: const Icon(Icons.add_to_home_screen_rounded),
              label: Text(
                _pinSupported
                    ? 'Add to Home Screen'
                    : 'Use launcher widget picker',
              ),
            ),
          ),
          const SizedBox(height: 12),
          _card(
            Icons.calendar_month_rounded,
            'Calendar events',
            'Open Classwork or Exam Schedule and tap the calendar icon beside '
                'an item. Your calendar app will open with the event details '
                'already filled in.',
            OutlinedButton.icon(
              onPressed: () => context.push('/classwork'),
              icon: const Icon(Icons.assignment_rounded),
              label: const Text('Open Classwork'),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => context.push('/info/exam'),
            icon: const Icon(Icons.event_note_rounded),
            label: const Text('Open Exam Schedule'),
          ),
        ],
      ),
    );
  }

  Widget _card(IconData icon, String title, String body, Widget action) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.accentBright, size: 25),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                color: AppColors.text,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              body,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 14),
            action,
          ],
        ),
      );
}
