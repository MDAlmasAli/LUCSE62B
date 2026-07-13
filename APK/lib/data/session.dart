import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';
import 'models/student.dart';

/// Holds the current login session. Mirrors the web split between
/// localStorage ("keep me logged in") and sessionStorage (demo / temporary):
/// persisted sessions survive app restarts; demo sessions do not.
class Session extends ChangeNotifier {
  Session._();
  static final Session instance = Session._();

  Student? _student;
  Student? get student => _student;
  bool get isLoggedIn => _student != null;
  bool get isDemo => _student?.isDemo ?? false;

  /// Cached DOB-gate status for the current student (synchronous for routing).
  /// True for demo accounts and any student already LU-verified on this device.
  bool dobOk = false;

  /// Load any persisted (keep-me-logged-in) session at startup.
  /// Also enforces the 7-day expiry like auth.js.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(K.ssStudent);
    if (raw == null) return;
    try {
      final s = Student.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      // 7-day force-logout (matches auth.js Option A).
      if (!s.isDemo &&
          DateTime.now().millisecondsSinceEpoch - s.loginTime > K.sevenDaysMs) {
        await prefs.remove(K.ssStudent);
        return;
      }
      _student = s;
      if (!raw.contains('"sessionId"') || !raw.contains('"sessionIssuedAt"')) {
        await prefs.setString(K.ssStudent, jsonEncode(s.toJson()));
      }
      dobOk = s.isDemo || prefs.getString('${K.ssDobOkPrefix}${s.id}') == '1';
    } catch (_) {
      await prefs.remove(K.ssStudent);
    }
  }

  Future<void> signIn(Student s, {required bool keep}) async {
    final next = s.withFreshSession();
    _student = next;
    final prefs = await SharedPreferences.getInstance();
    dobOk =
        next.isDemo || prefs.getString('${K.ssDobOkPrefix}${next.id}') == '1';
    // Demo sessions are never persisted across restarts.
    if (keep && !next.isDemo) {
      await prefs.setString(K.ssStudent, jsonEncode(next.toJson()));
    } else {
      await prefs.remove(K.ssStudent);
    }
    notifyListeners();
  }

  Future<void> signOut() async {
    _student = null;
    dobOk = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(K.ssStudent);
    notifyListeners();
  }

  // ── DOB gate flags (per-student), mirrors auth.js localStorage usage ──
  Future<bool> isDobVerified(String id) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('${K.ssDobOkPrefix}$id') == '1';
  }

  Future<void> markDobVerified(String id, String dob) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('${K.ssDobOkPrefix}$id', '1');
    await prefs.setString('${K.ssDobPrefix}$id', dob);
    if (_student?.id == id) dobOk = true;
    notifyListeners();
  }

  Future<String?> storedDob(String id) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('${K.ssDobPrefix}$id');
  }
}
