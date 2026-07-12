import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'routine_grid_repository.dart';

class ClassReminderService {
  ClassReminderService._();
  static final instance = ClassReminderService._();

  static const _channel = AndroidNotificationChannel(
    'lu62b_class_reminders',
    'Class reminders',
    description: 'Reminders before a class starts',
    importance: Importance.high,
  );

  static const _leadTime = Duration(minutes: 15);
  static const _payloadPrefix = 'class_reminder:';
  static const _weekdayName = {
    DateTime.saturday: 'SATURDAY',
    DateTime.sunday: 'SUNDAY',
    DateTime.monday: 'MONDAY',
    DateTime.tuesday: 'TUESDAY',
    DateTime.wednesday: 'WEDNESDAY',
    DateTime.thursday: 'THURSDAY',
    DateTime.friday: 'FRIDAY',
  };

  final _local = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _scheduling = false;

  Future<void> initialize() async {
    if (!Platform.isAndroid || _initialized) return;
    try {
      tz_data.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Asia/Dhaka'));
    } catch (_) {}
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _local.initialize(settings: settings);
    await _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_channel);
    _initialized = true;
  }

  Future<void> scheduleFromRoutine(RoutineGridData? data) async {
    if (!Platform.isAndroid || data == null || _scheduling) return;
    _scheduling = true;
    try {
      await initialize();
      await _cancelExisting();
      final now = DateTime.now();
      var scheduled = 0;

      for (var offset = 0; offset < 7; offset++) {
        final date = DateTime(now.year, now.month, now.day + offset);
        final dayName = _weekdayName[date.weekday];
        if (dayName == null) continue;
        final daySlots = data.schedule[dayName] ?? const <GridSlot>[];
        var slotIndex = 0;
        for (final slot in daySlots) {
          if (slot.isBreak || slot.code.trim().isEmpty) continue;
          final startMin = _timeToMin(slot.time);
          if (startMin >= 9999) continue;
          final classStart = DateTime(
            date.year,
            date.month,
            date.day,
            startMin ~/ 60,
            startMin % 60,
          );
          final reminderAt = classStart.subtract(_leadTime);
          if (!reminderAt.isAfter(now)) continue;
          final courseName = data.nameFor(slot).trim();
          final visibleCourse =
              courseName.isNotEmpty ? courseName : 'Your class';
          final room = slot.room.trim();
          final bodyParts = <String>[
            visibleCourse,
            if (room.isNotEmpty) 'Room $room',
            _displayTime(slot.time),
          ];
          await _local.zonedSchedule(
            id: 620000 + offset * 100 + slotIndex,
            scheduledDate: tz.TZDateTime.from(reminderAt, tz.local),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            title: 'Class starts in 15 minutes',
            body: bodyParts.join(' · '),
            payload:
                '$_payloadPrefix${date.toIso8601String()}|${slot.code}|${slot.time}',
            notificationDetails: const NotificationDetails(
              android: AndroidNotificationDetails(
                'lu62b_class_reminders',
                'Class reminders',
                channelDescription: 'Reminders before a class starts',
                importance: Importance.high,
                priority: Priority.high,
                icon: '@mipmap/ic_launcher',
              ),
              iOS: DarwinNotificationDetails(),
            ),
          );
          scheduled++;
          slotIndex++;
          if (scheduled >= 48) return;
        }
      }
    } catch (e) {
      debugPrint('Class reminder scheduling failed: $e');
    } finally {
      _scheduling = false;
    }
  }

  Future<void> _cancelExisting() async {
    final pending = await _local.pendingNotificationRequests();
    for (final item in pending) {
      if ((item.payload ?? '').startsWith(_payloadPrefix)) {
        await _local.cancel(id: item.id);
      }
    }
  }

  static int _timeToMin(String t) {
    final match = RegExp(
      r'(\d{1,2}):(\d{2})(?:\s*(AM|PM))?',
      caseSensitive: false,
    ).firstMatch(t);
    if (match == null) return 9999;
    var hour = int.parse(match[1]!);
    final minute = int.parse(match[2]!);
    final ampm = match[3]?.toUpperCase();
    if (ampm == 'PM' && hour != 12) hour += 12;
    if (ampm == 'AM' && hour == 12) hour = 0;
    if (ampm == null && hour < 8) hour += 12;
    return hour * 60 + minute;
  }

  static String _displayTime(String value) {
    final trimmed = value.trim();
    if (trimmed.length <= 24) return trimmed;
    return trimmed.substring(0, 24);
  }
}
