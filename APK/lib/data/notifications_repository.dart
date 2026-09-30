import 'dart:convert';

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

  static const _cacheKey = 'lu62b_notif_cache';

  /// The last rows we read, so the bell and the list still have something to
  /// show with no internet. Only the 20 rows Supabase returns are kept, and
  /// they are re-filtered on read in case the preferences changed since.
  Future<List<AppNotification>> fetch() async {
    final id = Session.instance.student?.id;
    if (id == null) return [];
    List<Map<String, dynamic>> rows;
    try {
      var q = Supa.client
          .from('notifications')
          .select('id,type,title,body,link,created_at');
      // public OR personal
      q = q.or('student_id.is.null,student_id.eq.$id');
      final result = await q.order('created_at', ascending: false).limit(20);
      rows = (result as List).cast<Map<String, dynamic>>();
      await _save(id, rows);
    } catch (_) {
      rows = await _cached(id);
    }
    return rows
        .map(AppNotification.fromJson)
        .where((item) => NotificationPreferences.instance.allowsType(item.type))
        // Birthday rows are public, but they are about CSE 62B's own students,
        // so they are not for a guest from another section.
        .where(
          (item) =>
              !(Session.instance.isGuestSection &&
                  item.type.toLowerCase().contains('birthday')),
        )
        .toList();
  }

  Future<void> _save(String id, List<Map<String, dynamic>> rows) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('${_cacheKey}_$id', jsonEncode(rows));
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> _cached(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('${_cacheKey}_$id');
      if (raw == null) return [];
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<DateTime> lastSeen() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(K.ssNotifLastSeen);
    return (DateTime.tryParse(v ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0))
        .toUtc();
  }

  Future<void> markAllSeen(Iterable<AppNotification> items) async {
    final prefs = await SharedPreferences.getInstance();
    var watermark = DateTime.now().toUtc();
    for (final item in items) {
      final createdAt = item.createdAt.toUtc();
      if (createdAt.isAfter(watermark)) watermark = createdAt;
    }
    await prefs.setString(K.ssNotifLastSeen, watermark.toIso8601String());
  }

  int unreadCount(List<AppNotification> list, DateTime seen) =>
      list.where((n) => n.createdAt.toUtc().isAfter(seen.toUtc())).length;
}
