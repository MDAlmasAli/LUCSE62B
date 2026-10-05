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

  /// Whose routine, exams and course list to show. 62 / B unless the student
  /// came in through the Main Sheet's "Special Access" tab, in which case it
  /// is their own section. Screens read these rather than the literals.
  String get batch => _student?.batch ?? Student.homeBatch;
  String get section => _student?.section ?? Student.homeSection;

  /// A guest from another section: they get the routine, the exams and their
  /// own result, but not the parts that belong to CSE 62B alone.
  bool get isGuestSection => _student?.isGuestSection ?? false;

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
      // Opening the app counts as using it, so the expiry moves with them.
      await touch();
      dobOk = s.isDemo || prefs.getString('${K.ssDobOkPrefix}${s.id}') == '1';
    } catch (_) {
      await prefs.remove(K.ssStudent);
    }
  }

  /// Mark the session as used, so the seven-day expiry counts from the last
  /// visit rather than from signing in. Without this everybody was signed out
  /// every seventh day however often they opened the app. Throttled to an hour
  /// so it is not a disk write on every check.
  Future<void> touch() async {
    final current = _student;
    if (current == null || current.isDemo) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - current.loginTime < 3600000) return;
    final next = current.withLoginTime(now);
    _student = next;
    final prefs = await SharedPreferences.getInstance();
    // Only a kept session is on disk; a temporary one stays in memory.
    if (prefs.getString(K.ssStudent) != null) {
      await prefs.setString(K.ssStudent, jsonEncode(next.toJson()));
    }
  }

  /// Fill in the batch and section of a session that was saved before guest
  /// access existed. Does nothing once they are known, and never touches a
  /// demo session.
  Future<void> applySection(String newBatch, String newSection) async {
    final current = _student;
    if (current == null || current.isDemo) return;
    if (current.sectionKnown &&
        current.batch == newBatch &&
        current.section == newSection.toUpperCase()) {
      return;
    }
    final next = current.withSection(newBatch, newSection);
    _student = next;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(K.ssStudent) != null) {
      await prefs.setString(K.ssStudent, jsonEncode(next.toJson()));
    }
    notifyListeners();
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
