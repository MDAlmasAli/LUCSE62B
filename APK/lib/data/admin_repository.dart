import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/constants.dart';
import 'models/app_notification.dart';
import 'session.dart';

class AdminRepository {
  AdminRepository._();
  static final instance = AdminRepository._();

  String? _token;

  Map<String, String> get _baseHeaders => const {
    'Origin': K.portalOrigin,
    'Content-Type': 'application/json',
  };

  Map<String, String> get _adminHeaders => {
    ..._baseHeaders,
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  Future<bool> login(String password) async {
    final id = Session.instance.student?.id;
    if (id != K.attendanceAdminId || password.isEmpty) return false;
    try {
      final response = await http
          .post(
            Uri.parse('${K.workerUrl}/admin/login'),
            headers: _baseHeaders,
            body: jsonEncode({'student_id': id, 'password': password}),
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return false;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      _token = data['token']?.toString();
      return _token?.isNotEmpty == true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> status() => _get('/admin/status');

  Future<List<AppNotification>> notifications() async {
    final data = await _get('/admin/notifications');
    final rows = (data?['items'] as List?) ?? const [];
    return rows
        .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>?> sendAnnouncement({
    required String category,
    required String title,
    required String body,
    required String link,
  }) => _post('/admin/announcement', {
    'category': category,
    'title': title,
    'body': body,
    'link': link,
  });

  Future<bool> deleteNotification(String id) async {
    try {
      final response = await http
          .delete(
            Uri.parse('${K.workerUrl}/admin/notifications/$id'),
            headers: _adminHeaders,
          )
          .timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> runMonitor() async =>
      await _post('/admin/run-monitor', const {}) != null;

  Future<Map<String, dynamic>?> _get(String path) async {
    try {
      final response = await http
          .get(Uri.parse('${K.workerUrl}$path'), headers: _adminHeaders)
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return null;
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('${K.workerUrl}$path'),
            headers: _adminHeaders,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) return null;
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
