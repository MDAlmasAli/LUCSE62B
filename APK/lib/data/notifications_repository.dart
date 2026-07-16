import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';
import '../core/supa.dart';
import 'models/app_notification.dart';
import 'notification_preferences.dart';
import 'session.dart';

/// Reads notifications from Supabase. Mirrors notifications.js:
/// logged-in users get public (student_id IS NULL) + their own personal rows.
class NotificationsRepository {
  NotificationsRepository._();
  static final instance = NotificationsRepository._();

  Future<List<AppNotification>> fetch() async {
    final id = Session.instance.student?.id;
    if (id == null) return [];
    var q = Supa.client
        .from('notifications')
        .select('id,type,title,body,link,created_at');
    // public OR personal
    q = q.or('student_id.is.null,student_id.eq.$id');
    final rows = await q.order('created_at', ascending: false).limit(20);
    return (rows as List)
        .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
        .where((item) => NotificationPreferences.instance.allowsType(item.type))
        .toList();
  }

  Future<DateTime> lastSeen() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(K.ssNotifLastSeen);
    return (DateTime.tryParse(v ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0))
        .toUtc();
  }

  Future<void> markAllSeen(Iterable<AppNotification> items) async {
    final prefs = await SharedPreferences.getInstance();
    var watermark = DateTime.now().toUtc();
    for (final item in items) {
      final createdAt = item.createdAt.toUtc();
      if (createdAt.isAfter(watermark)) watermark = createdAt;
    }
    await prefs.setString(
      K.ssNotifLastSeen,
      watermark.toIso8601String(),
    );
  }

  int unreadCount(List<AppNotification> list, DateTime seen) =>
      list.where((n) => n.createdAt.toUtc().isAfter(seen.toUtc())).length;
}
