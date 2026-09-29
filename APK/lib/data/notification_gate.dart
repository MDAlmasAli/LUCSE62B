import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'local_notifications.dart';
import 'push_service.dart';

/// Why the phone is not showing our notifications.
enum PushBlock {
  /// Nothing in the way.
  none,

  /// Notifications are switched off for the whole app — either the Android 13+
  /// permission was refused, or someone turned the app off in settings.
  appDisabled,

  /// The app may notify, but the "Notifications" channel itself is blocked.
  channelDisabled,
}

/// Finds out whether a push we deliver would actually be seen.
///
/// This exists because of a failure that looks like nothing at all: the message
/// reaches the phone, the in-app list shows it (that list reads Supabase, not
/// FCM), and the notification panel stays empty. From inside the app the two are
/// indistinguishable, so the app has to ask Android directly and say so.
class NotificationGate extends ChangeNotifier {
  NotificationGate._();
  static final instance = NotificationGate._();

  static const _platform = MethodChannel('lu62b/notifications');

  PushBlock _state = PushBlock.none;
  PushBlock get state => _state;
  bool get blocked => _state != PushBlock.none;

  /// What to tell the student. Empty when nothing is wrong.
  String get message => switch (_state) {
    PushBlock.none => '',
    PushBlock.appDisabled =>
      'Notifications are turned off for this app, so nothing reaches your '
          'notification panel. The list in here keeps working either way.',
    PushBlock.channelDisabled =>
      'The app may notify you, but its "Notifications" channel is switched '
          'off, so nothing reaches your notification panel.',
  };

  AndroidFlutterLocalNotificationsPlugin? get _android => LocalNotifications
      .plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  Future<void> refresh() async {
    final next = await _read();
    if (next == _state) return;
    _state = next;
    notifyListeners();
  }

  Future<PushBlock> _read() async {
    if (!Platform.isAndroid) return PushBlock.none;
    try {
      final android = _android;
      if (android == null) return PushBlock.none;

      if (await android.areNotificationsEnabled() == false) {
        return PushBlock.appDisabled;
      }

      // App-level permission is not the whole story: a channel can be blocked
      // on its own, which looks identical from in here.
      final channels = await android.getNotificationChannels();
      if (channels == null) return PushBlock.none;
      for (final channel in channels) {
        if (channel.id == PushService.channelId) {
          return channel.importance == Importance.none
              ? PushBlock.channelDisabled
              : PushBlock.none;
        }
      }
      return PushBlock.none;
    } catch (e) {
      debugPrint('Notification gate check failed: $e');
      return PushBlock.none; // Never nag on the strength of a failed check.
    }
  }

  /// Ask for the permission, and if Android will not ask any more, hand the
  /// student the settings page instead. Returns true once notifications are on.
  Future<bool> fix() async {
    if (!Platform.isAndroid) return true;
    if (_state == PushBlock.appDisabled) {
      try {
        if (await _android?.requestNotificationsPermission() == true) {
          await refresh();
          return !blocked;
        }
      } catch (_) {}
    }
    // A refused permission is only askable once, and a blocked channel never
    // is, so the rest is up to the student in system settings.
    await openSystemSettings();
    return false;
  }

  Future<bool> openSystemSettings() async {
    try {
      return await _platform.invokeMethod<bool>('openNotificationSettings') ??
          false;
    } catch (e) {
      debugPrint('Could not open notification settings: $e');
      return false;
    }
  }
}
