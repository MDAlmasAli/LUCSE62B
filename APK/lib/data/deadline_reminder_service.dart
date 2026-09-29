import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'deadline_repository.dart';
import 'local_notifications.dart';
import 'notification_preferences.dart';

/// Reminds the student before a classwork deadline — a day before, and again
/// two hours before. The reminders are scheduled on the phone from the
/// Deadlines sheet, so they still fire with no internet, and they are re-armed
/// on every launch and whenever the Classwork screen refreshes.
///
/// Switching off "Classwork & deadlines" in notification settings cancels them.
class DeadlineReminderService {
  DeadlineReminderService._();
  static final instance = DeadlineReminderService._();

  static const _channel = AndroidNotificationChannel(
    'lu62b_deadline_reminders',
    'Deadline reminders',
    description: 'Reminders before a classwork deadline',
    importance: Importance.high,
  );

  /// How far ahead of the deadline each reminder fires. One notification per
  /// lead time, so a deadline less than a day away only gets the two-hour one.
  static const _leads = <Duration>[Duration(hours: 24), Duration(hours: 2)];
  static const _payloadPrefix = 'deadline_reminder:';
  static const _idBase = 630000; // class reminders own 620000+
  static const _maxDeadlines = 20;

  Future<void>? _running;

  /// Load the deadlines and re-arm the reminders.
  Future<void> refresh() async {
    if (!Platform.isAndroid) return;
    try {
      await scheduleFrom(await DeadlineRepository.instance.load());
    } catch (_) {
      // A reminder that cannot be scheduled is not worth surfacing.
    }
  }

  /// Runs one at a time, but never drops a call: a toggle that arrives while a
  /// refresh is in flight has to be honoured, or switching the reminders off
  /// could leave the pending ones armed.
  Future<void> scheduleFrom(List<Deadline> deadlines) {
    if (!Platform.isAndroid) return Future.value();
    final previous = _running;
    final task = () async {
      if (previous != null) {
        try {
          await previous;
        } catch (_) {}
      }
      await _schedule(deadlines);
    }();
    _running = task;
    return task;
  }

  Future<void> _schedule(List<Deadline> deadlines) async {
    try {
      await LocalNotifications.ensureInitialized();
      await LocalNotifications.createChannel(_channel);
      await LocalNotifications.cancelWithPayloadPrefix(_payloadPrefix);
      if (!NotificationPreferences.instance.enabled('classwork')) return;

      final now = DateTime.now();
      final upcoming = deadlines
          .where((d) => d.due != null && d.due!.isAfter(now))
          .take(_maxDeadlines)
          .toList();

      for (var i = 0; i < upcoming.length; i++) {
        final item = upcoming[i];
        final due = item.due!;
        for (var lead = 0; lead < _leads.length; lead++) {
          final fireAt = due.subtract(_leads[lead]);
          if (!fireAt.isAfter(now)) continue;
          // A deadline line is long, so let Android expand it instead of
          // truncating the course and the due time off the end.
          final body = _body(item);
          await LocalNotifications.plugin.zonedSchedule(
            id: _idBase + i * _leads.length + lead,
            scheduledDate: tz.TZDateTime.from(fireAt, tz.local),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            title: _leads[lead].inHours >= 24
                ? 'Due tomorrow'
                : 'Due in 2 hours',
            body: body,
            payload: '$_payloadPrefix${due.toIso8601String()}|${item.title}',
            notificationDetails: NotificationDetails(
              android: AndroidNotificationDetails(
                'lu62b_deadline_reminders',
                'Deadline reminders',
                channelDescription: 'Reminders before a classwork deadline',
                importance: Importance.high,
                priority: Priority.high,
                icon: '@mipmap/ic_launcher',
                styleInformation: BigTextStyleInformation(body),
              ),
              iOS: const DarwinNotificationDetails(),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Deadline reminder scheduling failed: $e');
    }
  }

  static String _body(Deadline item) => <String>[
    item.title,
    if (item.course.isNotEmpty) item.course,
    if (item.type.isNotEmpty) item.type,
    _fmtDue(item.due!),
  ].join(' · ');

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
    final time = (d.hour == 0 && d.minute == 0)
        ? ''
        : ' $h12:${d.minute.toString().padLeft(2, '0')} $ap';
    return '${mo[d.month - 1]} ${d.day}$time';
  }
}
