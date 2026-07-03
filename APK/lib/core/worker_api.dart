import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'constants.dart';

/// Thin client for the Cloudflare Worker REST endpoints
/// (https://lucse62b-api...workers.dev). Mirrors the calls the website makes.
class WorkerApi {
  WorkerApi._();
  static final instance = WorkerApi._();

  Uri _u(String path) => Uri.parse('${K.workerUrl}$path');

  /// The Worker gates sensitive endpoints on an allowed Origin (it's built for
  /// the website). The native app is the same portal, so we identify as it.
  static const _origin = {'Origin': K.portalOrigin};

  /// GET /lookup?id= → { found, name }
  Future<Map<String, dynamic>?> lookup(String studentId) async {
    try {
      final r = await http
          .get(_u('/lookup?id=${Uri.encodeComponent(studentId)}'), headers: _origin)
          .timeout(const Duration(seconds: 8));
      if (r.statusCode == 429) return {'_rate_limited': true};
      if (r.statusCode != 200) return null;
      return jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final r = await http
        .post(_u(path),
            headers: {'Content-Type': 'application/json', ..._origin},
            body: jsonEncode(body))
        .timeout(const Duration(seconds: 12));
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('worker ${r.statusCode}');
    }
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  /// GET /gallery?folder=&limit= → { files: [{ id, folder }] }.
  Future<List<Map<String, dynamic>>> gallery(String folderId, {int limit = 300}) async {
    try {
      final r = await http
          .get(_u('/gallery?folder=${Uri.encodeComponent(folderId)}&limit=$limit'),
              headers: _origin)
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) return [];
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      return ((data['files'] as List?) ?? const []).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  /// GET /drive?folder= → list of files { id, name, mimeType }. The listing is
  /// cached to disk so the materials browser (and its "Saved offline" files)
  /// still appears when there's no internet.
  Future<List<Map<String, dynamic>>> driveFolder(String folderId) async {
    try {
      final r = await http
          .get(_u('/drive?folder=${Uri.encodeComponent(folderId)}'), headers: _origin)
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) return _diskFolder(folderId);
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      if (data['error'] != null) return _diskFolder(folderId);
      final files = ((data['files'] as List?) ?? const []).cast<Map<String, dynamic>>();
      await _persistFolder(folderId, files);
      return files;
    } catch (_) {
      return _diskFolder(folderId);
    }
  }

  // ── Tiny on-disk cache for Drive folder listings (offline fallback) ──
  Directory? _diskDir;
  Future<Directory?> _cacheDir() async {
    if (_diskDir != null) return _diskDir;
    try {
      final base = await getApplicationDocumentsDirectory();
      final d = Directory('${base.path}/drive_cache');
      if (!await d.exists()) await d.create(recursive: true);
      return _diskDir = d;
    } catch (_) {
      return null;
    }
  }

  String _folderKey(String id) => id.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');

  Future<void> _persistFolder(String id, List<Map<String, dynamic>> files) async {
    try {
      final d = await _cacheDir();
      if (d == null) return;
      await File('${d.path}/${_folderKey(id)}.json').writeAsString(jsonEncode(files));
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> _diskFolder(String id) async {
    try {
      final d = await _cacheDir();
      if (d == null) return [];
      final f = File('${d.path}/${_folderKey(id)}.json');
      if (!await f.exists()) return [];
      final list = jsonDecode(await f.readAsString()) as List;
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  /// GET /notices → list of LU notices { title, link, date, image }.
  Future<List<Map<String, dynamic>>> notices() async {
    try {
      final r = await http
          .get(_u('/notices'), headers: _origin)
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return [];
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      return ((data['notices'] as List?) ?? const [])
          .cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>> sendOtp(String studentId) =>
      _post('/send-otp', {'student_id': studentId});

  Future<Map<String, dynamic>> verifyOtp(String studentId, String otp) =>
      _post('/verify-otp', {'student_id': studentId, 'otp': otp});

  Future<Map<String, dynamic>> setPassword(
          String studentId, String pst, String password, {String? name}) =>
      _post('/set-password',
          {'student_id': studentId, 'pst': pst, 'password': password, 'name': name});

  // The LU result fetch is the slowest call in the app (it scrapes the LU
  // portal). Profile, Results, Retake & Improve and Course List each call it
  // separately, so we memoise a successful payload per (id, dob) for the
  // session — the first screen pays the cost, the rest are instant.
  final Map<String, Map<String, dynamic>> _resultCache = {};

  /// Drop the cached LU result (pull-to-refresh).
  void clearResultCache() => _resultCache.clear();

  /// POST /result → verifies DOB against LU portal, returns results payload.
  /// Cached for the session once it succeeds.
  Future<Map<String, dynamic>> result(String studentId, String birthDate) async {
    final key = '$studentId|$birthDate';
    final cached = _resultCache[key];
    if (cached != null) return cached;
    final r = await _post('/result', {'student_id': studentId, 'birth_date': birthDate});
    if (r['success'] == true) _resultCache[key] = r;
    return r;
  }

  /// POST /result-import → store a manually-imported result (parsed client-side
  /// from the LU result page) so future /result loads serve it. The Worker gates
  /// writes to the student's own id. Returns true on success.
  Future<bool> resultImport(
      String studentId, String birthDate, Map<String, dynamic> data) async {
    try {
      final r = await http
          .post(_u('/result-import'),
              headers: {'Content-Type': 'application/json', ..._origin},
              body: jsonEncode(
                  {'student_id': studentId, 'birth_date': birthDate, 'data': data}))
          .timeout(const Duration(seconds: 15));
      if (r.statusCode < 200 || r.statusCode >= 300) return false;
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      return j['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  /// POST /my-phone → the student's own phone (DOB acts as a second factor).
  /// Lighter than /result and often works even when results are CAPTCHA-blocked.
  Future<String?> myPhone(String studentId, String birthDate) async {
    try {
      final d = await _post('/my-phone', {'student_id': studentId, 'birth_date': birthDate});
      final p = d['phone'];
      return (p is String && p.trim().isNotEmpty) ? p.trim() : null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> dobCheck(String studentId) async {
    try {
      final d = await _post('/dob-check', {'student_id': studentId});
      return d['has_dob'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<String?> dobGet(String studentId) async {
    try {
      final d = await _post('/dob-get', {'student_id': studentId});
      return d['dob'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> dobSync(String studentId, String dob) async {
    try {
      await _post('/dob-sync', {'student_id': studentId, 'dob': dob});
    } catch (_) {}
  }

  /// GET /student-phones → { studentId: phone } for the whole class. Used by the
  /// directory to render a WhatsApp button. Empty if the endpoint isn't
  /// deployed yet or the origin is blocked.
  Future<Map<String, String>> studentPhones() async {
    try {
      final r = await http
          .get(_u('/student-phones'), headers: _origin)
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return {};
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      final ph = (data['phones'] as Map?) ?? const {};
      return ph.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {
      return {};
    }
  }

  // ── Attendance (admin roll-call) ──

  /// GET /attendance → today's present student IDs.
  Future<List<String>> attendancePresentIds() async {
    try {
      final r = await http
          .get(_u('/attendance'), headers: _origin)
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return [];
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      return ((data['records'] as List?) ?? const [])
          .map((e) => (e as Map)['student_id']?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// POST /attendance → mark / unmark a student present (admin only).
  Future<bool> attendanceSet(
      String adminId, String studentId, String studentName, bool present) async {
    try {
      await _post('/attendance', {
        'action': present ? 'mark' : 'unmark',
        'admin_id': adminId,
        'student_id': studentId,
        'student_name': studentName,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// POST /attendance → clear all of today's attendance (admin only).
  Future<bool> attendanceClear(String adminId) async {
    try {
      await _post('/attendance', {'action': 'clear', 'admin_id': adminId});
      return true;
    } catch (_) {
      return false;
    }
  }
}
