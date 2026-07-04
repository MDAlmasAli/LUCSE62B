import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationPreference {
  final String id;
  final String label;
  final String description;
  final String topic;

  const NotificationPreference(
    this.id,
    this.label,
    this.description,
    this.topic,
  );
}

/// Local notification choices mirrored to FCM topic subscriptions.
class NotificationPreferences extends ChangeNotifier {
  NotificationPreferences._();
  static final instance = NotificationPreferences._();

  static const items = <NotificationPreference>[
    NotificationPreference(
      'notices',
      'Notices',
      'University and class announcements',
      'notif_notices',
    ),
    NotificationPreference(
      'classwork',
      'Classwork & deadlines',
      'Assignments, presentations and deadline reminders',
      'notif_classwork',
    ),
    NotificationPreference(
      'routine',
      'Routine & exams',
      'Class routine and exam schedule changes',
      'notif_routine',
    ),
    NotificationPreference(
      'updates',
      'App updates',
      'New APK versions and important fixes',
      'notif_updates',
    ),
    NotificationPreference(
      'general',
      'General',
      'Other portal announcements',
      'notif_general',
    ),
  ];

  final Map<String, bool> _enabled = {for (final item in items) item.id: true};

  bool enabled(String id) => _enabled[id] ?? true;

  Iterable<String> get enabledTopics =>
      items.where((item) => enabled(item.id)).map((item) => item.topic);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    for (final item in items) {
      _enabled[item.id] = prefs.getBool('lu62b_notif_pref_${item.id}') ?? true;
    }
  }

  Future<void> setEnabled(String id, bool value) async {
    if (!_enabled.containsKey(id)) return;
    _enabled[id] = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('lu62b_notif_pref_$id', value);
    notifyListeners();
  }

  bool allowsType(String type) => enabled(categoryForType(type));

  static String categoryForType(String type) {
    final value = type.toLowerCase();
    if (value.contains('notice')) return 'notices';
    if (value.contains('classwork') || value.contains('deadline')) {
      return 'classwork';
    }
    if (value.contains('routine') || value.contains('exam')) return 'routine';
    if (value.contains('app_update')) return 'updates';
    return 'general';
  }
}
