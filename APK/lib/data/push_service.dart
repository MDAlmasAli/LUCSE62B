import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/supa.dart';
import 'session.dart';

/// Background isolate handler — must be a top-level function.
@pragma('vm:entry-point')
Future<void> _bgHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // Notification payloads are displayed by Android automatically. Data-only
  // messages need a local notification or users would never see them.
  if (message.notification != null) return;
  final title = message.data['title']?.toString() ?? '';
  final body = message.data['body']?.toString() ?? '';
  if (title.isEmpty && body.isEmpty) return;
  final local = FlutterLocalNotificationsPlugin();
  const settings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: DarwinInitializationSettings(),
  );
  await local.initialize(settings: settings);
  await local
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(PushService._channel);
  await local.show(
    id: message.messageId?.hashCode ?? message.data.hashCode,
    title: title,
    body: body,
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        'lu62b_default',
        'Notifications',
        channelDescription: 'CSE 62B Portal notifications',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: DarwinNotificationDetails(),
    ),
  );
}

/// Firebase Cloud Messaging integration: registers the device token (linked to
/// the logged-in student), shows foreground notifications, and keeps the token
/// fresh. The Worker sends pushes to the `fcm_tokens` table on the server side.
class PushService {
  PushService._();
  static final instance = PushService._();

  final _local = FlutterLocalNotificationsPlugin();
  String? _token;
  bool _ready = false;
  Future<void>? _initializing;

  static const _channel = AndroidNotificationChannel(
    'lu62b_default',
    'Notifications',
    description: 'CSE 62B Portal notifications',
    importance: Importance.high,
  );

  Future<void> init() => _initializing ??= _init();

  Future<void> _init() async {
    try {
      FirebaseMessaging.onBackgroundMessage(_bgHandler);
      await Firebase.initializeApp();

      // Local notifications (used to display foreground messages).
      const initSettings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      );
      await _local.initialize(settings: initSettings);
      await _local
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(_channel);

      // Permission (iOS + Android 13+).
      final permission = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (permission.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('Push notification permission denied');
      }
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
            alert: true,
            badge: true,
            sound: true,
          );

      // Show foreground messages ourselves.
      FirebaseMessaging.onMessage.listen(_showForeground);

      // Token registration + refresh.
      _token = await FirebaseMessaging.instance.getToken();
      await _register();
      FirebaseMessaging.instance.onTokenRefresh.listen((t) {
        _token = t;
        _register();
      });

      _ready = true;
    } catch (e) {
      debugPrint('PushService init failed: $e');
    }
  }

  /// Upsert the current token with the logged-in student id (if any).
  Future<void> _register() async {
    final token = _token;
    if (token == null) return;
    try {
      await Supa.client.from('fcm_tokens').upsert({
        'token': token,
        'student_id': Session.instance.student?.id,
        'platform': Platform.isIOS ? 'ios' : 'android',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      debugPrint('fcm_tokens upsert failed: $e');
    }
  }

  /// Re-link the token after a login/logout so pushes target the right student.
  Future<void> onAuthChanged() async {
    if (_ready) await _register();
  }

  void _showForeground(RemoteMessage m) {
    final n = m.notification;
    final title = n?.title ?? m.data['title']?.toString() ?? '';
    final body = n?.body ?? m.data['body']?.toString() ?? '';
    if (title.isEmpty && body.isEmpty) return;
    _local.show(
      id: m.messageId?.hashCode ?? m.data.hashCode,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'lu62b_default',
          'Notifications',
          channelDescription: 'CSE 62B Portal notifications',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }
}
