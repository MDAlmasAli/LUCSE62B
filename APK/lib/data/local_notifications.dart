import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// The single `FlutterLocalNotificationsPlugin` the app schedules through, and
/// the one-time plugin/timezone setup every reminder service needs.
///
/// Both the class reminders and the deadline reminders live in the same plugin
/// queue, so each one tags its notifications with a payload prefix and cancels
/// only its own — see [cancelWithPayloadPrefix].
class LocalNotifications {
  LocalNotifications._();

  static final plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static Future<void> ensureInitialized() async {
    if (!Platform.isAndroid || _ready) return;
    try {
      tz_data.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Asia/Dhaka'));
    } catch (_) {}
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await plugin.initialize(settings: settings);
    _ready = true;
  }

  static Future<void> createChannel(AndroidNotificationChannel channel) async {
    if (!Platform.isAndroid) return;
    await plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
  }

  /// Cancel every pending notification whose payload starts with [prefix].
  static Future<void> cancelWithPayloadPrefix(String prefix) async {
    final pending = await plugin.pendingNotificationRequests();
    for (final item in pending) {
      if ((item.payload ?? '').startsWith(prefix)) {
        await plugin.cancel(id: item.id);
      }
    }
  }
}
