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
  bool _checkingPin = true;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    HomeWidgetService.instance
        .canPin()
        .then((value) {
          if (mounted) {
            setState(() {
              _pinSupported = value;
              _checkingPin = false;
            });
          }
        })
        .catchError((_) {
          if (mounted) setState(() => _checkingPin = false);
        });
  }

  Future<void> _addWidget() async {
    if (_adding) return;
    setState(() => _adding = true);
    try {
      await HomeWidgetService.instance.requestPin();
      if (!mounted) return;
      AppToast.show(
        context,
        'Confirm Add on the launcher. If it is rejected, long-press the Home '
        'screen and choose Widgets → CSE 62B Portal.',
      );
    } catch (_) {
      if (!mounted) return;
      AppToast.show(
        context,
        'Use Home screen → long-press → Widgets → CSE 62B Portal.',
      );
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _refreshWidget() async {
    try {
      await HomeWidgetService.instance.ensureDefaults();
      if (mounted) AppToast.show(context, 'Home widget refreshed.');
    } catch (_) {
      if (mounted) AppToast.show(context, 'Could not refresh the widget.');
    }
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
              onPressed: _pinSupported && !_adding ? _addWidget : null,
              icon: const Icon(Icons.add_to_home_screen_rounded),
              label: Text(
                _checkingPin
                    ? 'Checking launcher…'
                    : _adding
                    ? 'Opening launcher…'
                    : _pinSupported
                    ? 'Add to Home Screen'
                    : 'Use launcher widget picker',
              ),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _refreshWidget,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Refresh Home Widget'),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 8, 4, 4),
            child: Text(
              'Manual add: long-press an empty area on the Home screen → '
              'Widgets → CSE 62B Portal. When there is no class, bus or '
              'deadline, the widget will show a clear status instead of '
              'remaining blank.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11.5,
                height: 1.45,
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
