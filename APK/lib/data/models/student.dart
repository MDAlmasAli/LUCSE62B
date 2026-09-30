/// The logged-in student session — mirrors the web's `lu62b_student` object:
/// { id, name, batch, section, special, loginTime, isDemo, sessionId,
/// sessionIssuedAt }
class Student {
  /// The class this portal belongs to. Anyone whose [batch]/[section] differs
  /// came in through the Main Sheet's "Special Access" tab.
  static const homeBatch = '62';
  static const homeSection = 'B';

  final String id;
  final String name;

  /// Whose routine, exams and course list to show. 62 / B for the class
  /// itself; a guest's own section for anyone let in from elsewhere.
  final String batch;
  final String section;

  final int loginTime;
  final bool isDemo;
  final String sessionId;
  final int sessionIssuedAt;

  Student({
    required this.id,
    required this.name,
    required this.loginTime,
    this.batch = homeBatch,
    this.section = homeSection,
    this.isDemo = false,
    String? sessionId,
    int? sessionIssuedAt,
  }) : sessionId = (sessionId == null || sessionId.isEmpty)
           ? _newSessionId()
           : sessionId,
       sessionIssuedAt =
           sessionIssuedAt ?? DateTime.now().millisecondsSinceEpoch;

  bool get isAttendanceAdmin => id == '0182320012101068';

  /// A guest from another section. Checked on batch/section rather than on a
  /// stored flag, so a session saved before any of this existed still resolves
  /// correctly. Demo counts as one of us.
  bool get isGuestSection =>
      !isDemo && (batch != homeBatch || section != homeSection);

  static String _newSessionId() =>
      'app-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

  Student withFreshSession() => Student(
    id: id,
    name: name,
    batch: batch,
    section: section,
    loginTime: loginTime,
    isDemo: isDemo,
    sessionId: _newSessionId(),
    sessionIssuedAt: DateTime.now().millisecondsSinceEpoch,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'batch': batch,
    'section': section,
    'loginTime': loginTime,
    'isDemo': isDemo,
    'sessionId': sessionId,
    'sessionIssuedAt': sessionIssuedAt,
  };

  factory Student.fromJson(Map<String, dynamic> j) => Student(
    id: (j['id'] ?? '').toString(),
    name: (j['name'] ?? 'Student').toString(),
    // Sessions saved before guest access existed carry neither field.
    batch: (j['batch']?.toString().trim().isNotEmpty ?? false)
        ? j['batch'].toString().trim()
        : homeBatch,
    section: (j['section']?.toString().trim().isNotEmpty ?? false)
        ? j['section'].toString().trim().toUpperCase()
        : homeSection,
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

  factory Student.create(
    String id,
    String name, {
    bool isDemo = false,
    String batch = homeBatch,
    String section = homeSection,
  }) => Student(
    id: id,
    name: name,
    batch: batch,
    section: section,
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
