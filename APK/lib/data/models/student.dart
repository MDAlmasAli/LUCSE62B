/// The logged-in student session — mirrors the web's `lu62b_student` object:
/// { id, name, loginTime, isDemo, sessionId, sessionIssuedAt }
class Student {
  final String id;
  final String name;
  final int loginTime;
  final bool isDemo;
  final String sessionId;
  final int sessionIssuedAt;

  Student({
    required this.id,
    required this.name,
    required this.loginTime,
    this.isDemo = false,
    String? sessionId,
    int? sessionIssuedAt,
  }) : sessionId = (sessionId == null || sessionId.isEmpty)
           ? _newSessionId()
           : sessionId,
       sessionIssuedAt =
           sessionIssuedAt ?? DateTime.now().millisecondsSinceEpoch;

  bool get isAttendanceAdmin => id == '0182320012101068';

  static String _newSessionId() =>
      'app-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

  Student withFreshSession() => Student(
    id: id,
    name: name,
    loginTime: loginTime,
    isDemo: isDemo,
    sessionId: _newSessionId(),
    sessionIssuedAt: DateTime.now().millisecondsSinceEpoch,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'loginTime': loginTime,
    'isDemo': isDemo,
    'sessionId': sessionId,
    'sessionIssuedAt': sessionIssuedAt,
  };

  factory Student.fromJson(Map<String, dynamic> j) => Student(
    id: (j['id'] ?? '').toString(),
    name: (j['name'] ?? 'Student').toString(),
    loginTime: (j['loginTime'] is int)
        ? j['loginTime'] as int
        : int.tryParse('${j['loginTime']}') ??
              DateTime.now().millisecondsSinceEpoch,
    isDemo:
        j['isDemo'] == true ||
        (j['id'] ?? '').toString().toUpperCase() == 'DEMO',
    sessionId: (j['sessionId'] ?? '').toString(),
    sessionIssuedAt: (j['sessionIssuedAt'] is int)
        ? j['sessionIssuedAt'] as int
        : int.tryParse('${j['sessionIssuedAt']}') ??
              DateTime.now().millisecondsSinceEpoch,
  );

  factory Student.create(String id, String name, {bool isDemo = false}) =>
      Student(
        id: id,
        name: name,
        loginTime: DateTime.now().millisecondsSinceEpoch,
        isDemo: isDemo,
        sessionId: _newSessionId(),
        sessionIssuedAt: DateTime.now().millisecondsSinceEpoch,
      );

  /// Two-letter initials for avatars (mirrors login.js `initials`).
  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    return parts
        .take(2)
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
        .join();
  }
}
