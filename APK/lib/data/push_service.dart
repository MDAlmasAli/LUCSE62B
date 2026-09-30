import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/supa.dart';
import '../core/worker_api.dart';
import 'local_notifications.dart';
import 'notification_gate.dart';
import 'notification_preferences.dart';
import 'session.dart';

/// Background isolate handler — must be a top-level function.
@pragma('vm:entry-point')
Future<void> _bgHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  try {
    await Supa.init();
  } catch (_) {}
  try {
    await Session.instance.load();
  } catch (_) {}
  // Notification payloads are displayed by Android automatically. Data-only
  // messages need a local notification or users would never see them.
  if (message.notification != null) return;
  final title = message.data['title']?.toString() ?? '';
  final body = message.data['body']?.toString() ?? '';
  if (title.isEmpty && body.isEmpty) return;
  // A separate isolate, so this one needs its own plugin instance.
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
      ?.createNotificationChannel(PushService.channel);
  await local.show(
    id: PushService.notificationId(message.messageId ?? message.data),
    title: title,
    body: body,
    notificationDetails: PushService.details,
  );
}

/// Firebase Cloud Messaging integration: registers the device token (linked to
/// the logged-in student), shows foreground notifications, and keeps the token
/// fresh. The Worker sends pushes to the `fcm_tokens` table on the server side.
class PushService {
  PushService._();
  static final instance = PushService._();

  String? _token;
  bool _ready = false;
  Future<void>? _initializing;

  static const channelId = 'lu62b_default';
  static const channelName = 'Notifications';
  static const channelDescription = 'CSE 62B Portal notifications';

  static const channel = AndroidNotificationChannel(
    channelId,
    channelName,
    description: channelDescription,
    importance: Importance.high,
  );

  static const details = NotificationDetails(
    android: AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    ),
    iOS: DarwinNotificationDetails(),
  );

  /// Android notification ids are 32-bit. A Dart `hashCode` is not bounded to
  /// that, and an out-of-range id makes the platform call throw - which loses
  /// the notification with nothing to show why.
  static int notificationId(Object? seed) =>
      (seed?.hashCode ?? 0).abs() % 0x7FFFFFFF;

  Future<void> init() => _initializing ??= _init();

  Future<void> _init() async {
    try {
      FirebaseMessaging.onBackgroundMessage(_bgHandler);
      await Firebase.initializeApp();

      // Local notifications (used to display foreground messages). Shared
      // with the class and deadline reminders so there is one plugin instance
      // and one definition of this channel.
      await LocalNotifications.ensureInitialized();
      await LocalNotifications.createChannel(channel);

      // Permission (iOS + Android 13+).
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      // Then find out what the phone will really do with a push. Asking is not
      // the same as being allowed, and a refusal is silent: the message still
      // arrives and still reaches the in-app list, so without this check a
      // blocked notification panel looks exactly like a working one.
      await NotificationGate.instance.refresh();
      if (NotificationGate.instance.blocked) {
        debugPrint(
          'Push notifications will not be shown: '
          '${NotificationGate.instance.state.name}',
        );
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
      _ready = true;
      await _syncForSession();
      FirebaseMessaging.instance.onTokenRefresh.listen((t) async {
        _token = t;
        await _syncForSession();
      });
    } catch (e) {
      debugPrint('PushService init failed: $e');
    }
  }

  /// Whether this device should be on a category's broadcast topic.
  ///
  /// A guest from another section stays off two of them. Routine and exam
  /// changes are watched per section by the Worker and pushed to them
  /// individually, so listening to the topic as well would mean hearing about
  /// 62B's routine on top of their own. Classwork is the class's own and is
  /// hidden from them anyway. Notices, app updates and general news are for
  /// everyone and stay on topics.
  static const _classOnlyTopics = {'routine', 'classwork'};

  bool _wantsTopic(NotificationPreference item) {
    if (!NotificationPreferences.instance.enabled(item.id)) return false;
    if (Session.instance.isGuestSection &&
        _classOnlyTopics.contains(item.id)) {
      return false;
    }
    return true;
  }

  Future<void> _subscribeToBroadcasts() async {
    try {
      // Older APKs listen to all_users. This version uses category topics so
      // users can opt out without disabling every notification.
      // Subscribe first, and give up `all_users` only once at least one
      // category has replaced it. The old order dropped the fallback before
      // the replacement existed, so a single failed call — one network blip
      // during login was enough — left the device subscribed to nothing at
      // all. Broadcasts then reached it silently, while the in-app list went
      // on working, which makes the fault very hard to see from inside.
      var subscribed = 0;
      for (final item in NotificationPreferences.items) {
        // Each topic stands on its own: one failure must not skip the rest.
        try {
          if (_wantsTopic(item)) {
            await FirebaseMessaging.instance.subscribeToTopic(item.topic);
            subscribed++;
          } else {
            await FirebaseMessaging.instance.unsubscribeFromTopic(item.topic);
          }
        } catch (e) {
          debugPrint('FCM topic ${item.topic} failed: $e');
        }
      }

      // Older APKs listen to all_users, and the Worker still sends there, so
      // it is the safety net. Only step off it with a category in hand.
      final wantsAny = NotificationPreferences.items.any(_wantsTopic);
      if (subscribed > 0 || !wantsAny) {
        await FirebaseMessaging.instance.unsubscribeFromTopic('all_users');
      } else {
        debugPrint('No category topic took; staying on all_users');
      }
    } catch (e) {
      debugPrint('FCM topic subscription failed: $e');
    }
  }

  Future<void> _unsubscribeFromBroadcasts() async {
    try {
      for (final topic in [
        'all_users',
        ...NotificationPreferences.items.map((item) => item.topic),
      ]) {
        // One failure must not leave the rest subscribed after a logout.
        try {
          await FirebaseMessaging.instance.unsubscribeFromTopic(topic);
        } catch (e) {
          debugPrint('FCM topic $topic unsubscribe failed: $e');
        }
      }
    } catch (e) {
      debugPrint('FCM topic unsubscribe failed: $e');
    }
  }

  /// Upsert the current token with the logged-in student id (if any).
  Future<void> _register() async {
    final token = _token;
    if (token == null) return;
    final ok = await WorkerApi.instance.registerFcmToken(
      token,
      studentId: Session.instance.student?.id,
      platform: Platform.isIOS ? 'ios' : 'android',
    );
    if (!ok) debugPrint('fcm token registration failed');
  }

  Future<void> _unregister() async {
    final token = _token;
    if (token == null) return;
    await WorkerApi.instance.unregisterFcmToken(token);
  }

  Future<void> _syncForSession() async {
    if (Session.instance.isLoggedIn) {
      await _subscribeToBroadcasts();
      await _register();
    } else {
      await _unsubscribeFromBroadcasts();
      await _unregister();
    }
  }

  /// Re-link or remove the token after login/logout/access revocation.
  Future<void> onAuthChanged() async {
    if (_ready) await _syncForSession();
  }

  Future<void> syncPreferences() async {
    if (_ready && Session.instance.isLoggedIn) {
      await _subscribeToBroadcasts();
    }
  }

  void _showForeground(RemoteMessage m) {
    final n = m.notification;
    final title = n?.title ?? m.data['title']?.toString() ?? '';
    final body = n?.body ?? m.data['body']?.toString() ?? '';
    if (title.isEmpty && body.isEmpty) return;
    LocalNotifications.plugin.show(
      id: notificationId(m.messageId ?? m.data),
      title: title,
      body: body,
      notificationDetails: details,
    );
  }
}
