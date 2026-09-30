import '../core/supa.dart';
import '../core/worker_api.dart';
import 'models/student.dart';
import 'session.dart';

/// Login outcome after a student-id lookup.
enum LoginStage { password, otp, notFound, rateLimited, error }

class IdCheckResult {
  final LoginStage stage;
  final Student? student; // populated for password/otp stages
  const IdCheckResult(this.stage, [this.student]);
}

/// Implements the exact login flow from login.html:
/// 1. lookup id (worker) → 2. has-password? (rpc) → 3. verify password (rpc)
///    or OTP setup flow.
class AuthRepository {
  AuthRepository._();
  static final instance = AuthRepository._();

  final _worker = WorkerApi.instance;

  String normalizeId(String v) => v.trim().toUpperCase();

  /// Step 1 + 2: resolve the student, then decide password vs OTP path.
  Future<IdCheckResult> checkStudentId(String rawId) async {
    final sid = normalizeId(rawId);
    if (sid.isEmpty) return const IdCheckResult(LoginStage.error);

    Student student;
    if (sid == 'DEMO') {
      student = Student.create('DEMO', 'Demo Student', isDemo: true);
    } else {
      final data = await _worker.lookup(sid);
      if (data == null) return const IdCheckResult(LoginStage.error);
      if (data['_rate_limited'] == true) {
        return const IdCheckResult(LoginStage.rateLimited);
      }
      if (data['found'] != true) return const IdCheckResult(LoginStage.notFound);
      // The lookup reports which batch and section to show. It is 62 / B for
      // the class itself, and their own for anyone let in through the Main
      // Sheet's "Special Access" tab.
      student = Student.create(
        sid,
        (data['name'] ?? 'Student').toString(),
        batch: (data['batch']?.toString().trim().isNotEmpty ?? false)
            ? data['batch'].toString().trim()
            : Student.homeBatch,
        section: (data['section']?.toString().trim().isNotEmpty ?? false)
            ? data['section'].toString().trim().toUpperCase()
            : Student.homeSection,
      );
    }

    try {
      final hasPwd = await Supa.hasPassword(sid);
      if (sid == 'DEMO' && !hasPwd) return const IdCheckResult(LoginStage.error);
      return IdCheckResult(
          hasPwd ? LoginStage.password : LoginStage.otp, student);
    } catch (_) {
      return const IdCheckResult(LoginStage.error);
    }
  }

  /// Step 3a: password sign-in.
  Future<bool> loginWithPassword(Student student, String password,
      {required bool keep}) async {
    final ok = await Supa.verifyPassword(student.id, password);
    if (!ok) return false;
    await Session.instance.signIn(student, keep: student.isDemo ? false : keep);
    return true;
  }

  // ── OTP setup flow ──
  Future<Map<String, dynamic>> sendOtp(String id) => _worker.sendOtp(id);

  /// Returns { valid, pst, needsPasswordSetup }. On a verified OTP for an
  /// account that already has a password, signs in directly.
  Future<Map<String, dynamic>> verifyOtp(Student student, String otp,
      {required bool keep}) async {
    final res = await _worker.verifyOtp(student.id, otp);
    if (res['valid'] != true) return {'valid': false};
    final hasPwd = await Supa.hasPassword(student.id);
    if (hasPwd) {
      await Session.instance.signIn(student, keep: true);
      return {'valid': true, 'signedIn': true};
    }
    return {'valid': true, 'signedIn': false, 'pst': res['pst'] ?? ''};
  }

  /// Finish first-time setup: set password (worker) then sign in.
  Future<void> setPasswordAndSignIn(
      Student student, String pst, String password) async {
    await _worker.setPassword(student.id, pst, password, name: student.name);
    await Session.instance.signIn(student, keep: true);
  }
}
