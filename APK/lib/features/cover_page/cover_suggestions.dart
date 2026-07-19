import '../../core/sheets_api.dart';
import '../../core/supa.dart';
import '../../shared/suggest_field.dart';

/// Teacher payload carried on a teacher [Suggestion.data].
class TeacherInfo {
  final String designation;
  final String department;
  const TeacherInfo(this.designation, this.department);
}

/// Course payload carried on a course [Suggestion.data] — mirrors the site's
/// CPG_Courses row (code + teacher + designation + department), so picking a
/// course auto-fills the teacher block too.
class CourseInfo {
  final String code;
  final String teacher;
  final String designation;
  final String department;
  const CourseInfo(this.code, this.teacher, this.designation, this.department);
}

/// Loads autocomplete data for the cover-page fields, matching the website:
/// teachers (CPG_Teachers → name/designation/department), courses (CPG_Courses
/// → title/code/teacher/designation/department), students (Student Info →
/// name+id) and contextual topics (cover_page_topics by course/type/no).
class CoverSuggestions {
  List<Suggestion> teachers = [];
  List<Suggestion> courses = [];
  List<Suggestion> students = [];

  Future<void> load() async {
    await Future.wait([_loadTeachers(), _loadCourses(), _loadStudents()]);
  }

  /// Build a {lowercased header label → column index} map from GVIZ cols.
  static Map<String, int> _headerMap(List<String> cols) {
    final h = <String, int>{};
    for (var i = 0; i < cols.length; i++) {
      final label = cols[i].trim().toLowerCase();
      if (label.isNotEmpty) h[label] = i;
    }
    return h;
  }

  static String _at(List<String> row, int i) =>
      (i >= 0 && i < row.length) ? row[i].trim() : '';

  Future<void> _loadTeachers() async {
    try {
      final t = await SheetsApi.instance.sheetTable('CPG_Teachers');
      final h = _headerMap(t.cols);
      final nameCol = h['name'] ?? h['teacher'] ?? 1;
      final desigCol = h['designation'] ?? h['desig'] ?? 2;
      final deptCol = h['department'] ?? h['dept'] ?? 3;
      final seen = <String>{};
      for (final r in t.rows) {
        final name = _at(r, nameCol);
        if (name.isEmpty || name.toLowerCase() == 'name') continue;
        if (!seen.add(name.toLowerCase())) continue;
        final desig = _at(r, desigCol);
        final dept = _at(r, deptCol);
        teachers.add(Suggestion(name,
            secondary: desig, data: TeacherInfo(desig, dept)));
      }
    } catch (_) {}
  }

  Future<void> _loadCourses() async {
    try {
      final t = await SheetsApi.instance.sheetTable('CPG_Courses');
      final h = _headerMap(t.cols);
      final titleCol = h['title'] ?? h['course title'] ?? h['course'] ?? 0;
      final codeCol = h['code'] ?? h['course code'] ?? 1;
      final teachCol = h['teacher name'] ?? h['teacher'] ?? 2;
      final desigCol = h['designation'] ?? h['desig'] ?? 3;
      final deptCol = h['department'] ?? h['dept'] ?? 4;
      final seen = <String>{};
      for (final r in t.rows) {
        final title = _at(r, titleCol);
        if (title.isEmpty || title.toLowerCase() == 'title') continue;
        if (!seen.add(title.toLowerCase())) continue;
        final code = _at(r, codeCol);
        final teacher = _at(r, teachCol);
        final desig = _at(r, desigCol);
        final dept = _at(r, deptCol);
        courses.add(Suggestion(title,
            secondary: code, data: CourseInfo(code, teacher, desig, dept)));
      }
    } catch (_) {}
  }

  /// Student name → ID list (logged-in name autocomplete), parsed from the
  /// stacked "Student Info" sheet like the website's parseStudentNames.
  Future<void> _loadStudents() async {
    try {
      final rows = await SheetsApi.instance.sheet('Student Info');
      final groups = SheetsApi.parseGroups(rows);
      final nameRe = RegExp('name', caseSensitive: false);
      final idRe = RegExp(r'\bid\b', caseSensitive: false);
      final seen = <String>{};
      for (final g in groups) {
        final nameIdx = g.headers.indexWhere((c) => nameRe.hasMatch(c));
        final idIdx = g.headers.indexWhere((c) => idRe.hasMatch(c));
        if (nameIdx < 0) continue;
        for (final r in g.rows) {
          final name = _at(r, nameIdx);
          if (name.isEmpty) continue;
          final id = _at(r, idIdx);
          if (!seen.add('$name|$id')) continue;
          students.add(Suggestion(name, secondary: id, data: id));
        }
      }
    } catch (_) {}
  }

  /// Topics other students used for the same course/type/number — mirrors the
  /// site's "Others used:" suggestions, ordered by frequency. Logged-in only;
  /// returns [] when course code or number is missing.
  Future<List<Suggestion>> topicsFor(
      String courseCode, String docType, String docNo) async {
    if (courseCode.isEmpty || docNo.isEmpty) return [];
    try {
      final rows = await Supa.client
          .from('cover_page_topics')
          .select('topic')
          .eq('course_code', courseCode)
          .eq('doc_type', docType)
          .eq('doc_no', docNo)
          .order('created_at', ascending: false)
          .limit(80);
      final counts = <String, int>{};
      for (final row in rows as List) {
        final t = (row['topic'] ?? '').toString().trim();
        if (t.isNotEmpty) counts[t] = (counts[t] ?? 0) + 1;
      }
      final sorted = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      return sorted
          .map((e) => Suggestion(e.key,
              secondary: e.value > 1 ? '${e.value}×' : null))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// True when the CR has already bulk-generated this student's cover page for
  /// the same course + document number (written from the website's Class Mode).
  /// Caller passes already-normalised course code + number so the key matches
  /// exactly what the site stored. Returns false on any error / missing input.
  Future<bool> crAlreadyMade(
      String courseCode, String docType, String docNo, String studentId) async {
    if (courseCode.isEmpty || docNo.isEmpty || studentId.isEmpty) return false;
    try {
      final rows = await Supa.client
          .from('cr_cover_pages')
          .select('id')
          .eq('course_code', courseCode)
          .eq('doc_type', docType)
          .eq('doc_no', docNo)
          .eq('student_id', studentId)
          .limit(1);
      return (rows as List).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Record a freshly used topic so it appears as a suggestion next time.
  Future<void> saveTopic(
      String courseCode, String docType, String docNo, String topic,
      String studentId) async {
    if (courseCode.isEmpty || docNo.isEmpty || topic.isEmpty) return;
    try {
      await Supa.client.from('cover_page_topics').insert({
        'course_code': courseCode,
        'doc_type': docType,
        'doc_no': docNo,
        'topic': topic,
        'student_id': studentId,
      });
    } catch (_) {}
  }
}
