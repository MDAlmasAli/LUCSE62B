// Parsed LU result payload (from the Worker `/result` JSON, same shape the
// website's result-dashboard.html consumes).

class ResultCourse {
  final String code;
  final String title;
  final String grade;
  final double gpa;
  final double credit;
  const ResultCourse({
    required this.code,
    required this.title,
    required this.grade,
    required this.gpa,
    required this.credit,
  });
}

class ResultSemester {
  final String name;
  final String year;
  final double gpa;
  final double credit;
  final List<ResultCourse> courses;
  final int sortKey;
  const ResultSemester({
    required this.name,
    required this.year,
    required this.gpa,
    required this.credit,
    required this.courses,
    required this.sortKey,
  });
}

/// A course flagged for retake (F) or improvement (B-/C+/C/D).
class RetakeItem {
  final String code;
  final String title;
  final String grade;
  final double credit;
  const RetakeItem(this.code, this.title, this.grade, this.credit);
}

class ResultData {
  final String name;
  final String id;
  final String department;
  final String degree;
  final double cgpa;
  final double totalCredit;
  final int coursesCompleted;
  final bool imported;
  final List<ResultSemester> semesters;

  const ResultData({
    required this.name,
    required this.id,
    required this.department,
    required this.degree,
    required this.cgpa,
    required this.totalCredit,
    required this.coursesCompleted,
    required this.imported,
    required this.semesters,
  });

  /// LU 4.0 grade-point map.
  static const gradePoints = {
    'A+': 4.00, 'A': 3.75, 'A-': 3.50, 'B+': 3.25, 'B': 3.00,
    'B-': 2.75, 'C+': 2.50, 'C': 2.25, 'D': 2.00, 'F': 0.00,
  };

  /// Lenient numeric parse matching the website's `parseFloat` — pulls the
  /// number out even when the cell carries trailing text (e.g. "120.00 Cr").
  /// `double.tryParse` would reject those and yield 0, which made values like
  /// "Total Credit Completed" come out wrong.
  static double _d(Object? v) {
    if (v is num) return v.toDouble();
    final s = '$v'.trim();
    final direct = double.tryParse(s);
    if (direct != null) return direct;
    final m = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(s);
    return m != null ? (double.tryParse(m.group(0)!) ?? 0) : 0;
  }

  /// Parse the raw `/result` JSON map. Returns null if it isn't a success body.
  static ResultData? parse(Map<String, dynamic> raw) {
    if (raw['success'] != true) return null;
    final s = (raw['student'] as Map?) ?? const {};
    final rs = ((raw['row_data'] as Map?)?['student'] as Map?) ?? const {};
    const semOrder = {'Spring': 1, 'Summer': 2, 'Fall': 3};

    final out = <ResultSemester>[];
    final results = (raw['results'] as Map?) ?? const {};
    final years = results.keys.map((e) => e.toString()).toList()..sort();
    for (final year in years) {
      final yv = results[year];
      final semList = yv is List ? yv : (yv is Map ? yv.values.toList() : const []);
      for (final semRaw in semList) {
        if (semRaw is! Map) continue;
        final name = (semRaw['name'] ?? '').toString();
        final semType = semOrder.keys.firstWhere(
            (t) => name.contains(t), orElse: () => 'Fall');
        final courses = ((semRaw['courses'] as List?) ?? const [])
            .whereType<Map>()
            .map((c) => ResultCourse(
                  code: (c['course_code'] ?? '').toString().trim(),
                  title: (c['course_title'] ?? '').toString().trim(),
                  grade: (c['grade'] ?? '').toString().trim(),
                  gpa: _d(c['gpa']),
                  credit: _d(c['credit']),
                ))
            .toList();
        out.add(ResultSemester(
          name: name,
          year: year,
          gpa: _d(semRaw['gpa']),
          credit: _d(semRaw['credit']),
          courses: courses,
          sortKey: (int.tryParse(year) ?? 0) * 10 + (semOrder[semType] ?? 0),
        ));
      }
    }
    out.sort((a, b) => b.sortKey.compareTo(a.sortKey));

    // "Credit Completed" — prefer the reported value, but if it's missing or
    // garbled (parsed to 0), compute it from the passed courses (best attempt
    // per course, excluding F) so the total is never shown wrong.
    var totalCredit = _d(s['credit']);
    if (totalCredit <= 0) {
      final bestGrade = <String, String>{};
      final bestRank = <String, int>{};
      final maxCr = <String, double>{};
      for (final sem in out) {
        for (final c in sem.courses) {
          final code = _normCode(c.code);
          final rk = _rank(c.grade);
          if (code.isEmpty || rk < 0) continue;
          if (!bestRank.containsKey(code) || rk > bestRank[code]!) {
            bestRank[code] = rk;
            bestGrade[code] = c.grade.trim().toUpperCase();
          }
          if (c.credit > (maxCr[code] ?? 0)) maxCr[code] = c.credit;
        }
      }
      var sum = 0.0;
      bestGrade.forEach((code, g) {
        if (g != 'F') sum += maxCr[code] ?? 0;
      });
      totalCredit = sum;
    }

    return ResultData(
      name: (s['name'] ?? '').toString(),
      id: (s['id'] ?? '').toString(),
      department: (s['department'] ?? '').toString(),
      degree: (rs['Degree'] ?? s['degree'] ?? '').toString(),
      cgpa: _d(s['cgpa']),
      totalCredit: totalCredit,
      coursesCompleted: out.fold(0, (a, sem) => a + sem.courses.length),
      imported: raw['imported'] == true,
      semesters: out,
    );
  }

  static String _normCode(String c) {
    final s = c.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final m = RegExp(r'^([A-Z]+)(\d.*)$').firstMatch(s);
    return m != null ? '${m.group(1)}-${m.group(2)}' : s;
  }

  static int _rank(String g) =>
      const ['F', 'D', 'C', 'C+', 'B-', 'B', 'B+', 'A-', 'A', 'A+'].indexOf(g.trim());

  /// Best-attempt-per-course buckets: failed (retake) and weak (improve).
  ({List<RetakeItem> fail, List<RetakeItem> improve}) retakeImprove() {
    const improveGrades = {'B-', 'C+', 'C', 'D'};
    final best = <String, RetakeItem>{};
    final bestRank = <String, int>{};
    final maxCredit = <String, double>{};
    for (final sem in semesters) {
      for (final c in sem.courses) {
        final code = _normCode(c.code);
        final r = _rank(c.grade);
        if (code.isEmpty || r < 0) continue;
        if (c.credit > (maxCredit[code] ?? 0)) maxCredit[code] = c.credit;
        if (!bestRank.containsKey(code) || r > bestRank[code]!) {
          bestRank[code] = r;
          best[code] = RetakeItem(code, c.title, c.grade.trim().toUpperCase(), c.credit);
        }
      }
    }
    final fail = <RetakeItem>[], improve = <RetakeItem>[];
    best.forEach((code, item) {
      final cr = maxCredit[code] ?? item.credit;
      final fixed = RetakeItem(item.code, item.title, item.grade, cr);
      if (item.grade == 'F') {
        fail.add(fixed);
      } else if (improveGrades.contains(item.grade)) {
        improve.add(fixed);
      }
    });
    return (fail: fail, improve: improve);
  }

  /// Required average GPA on the remaining credits to reach [target] CGPA over a
  /// [degreeCredits]-credit degree. Returns null if no credits remain.
  double? requiredGpaFor(double target, {double degreeCredits = 160}) {
    final remaining = degreeCredits - totalCredit;
    if (remaining <= 0) return null;
    return (target * degreeCredits - cgpa * totalCredit) / remaining;
  }

  int get bestSemesterIndex {
    if (semesters.length < 2) return -1;
    var idx = 0;
    for (var i = 1; i < semesters.length; i++) {
      if (semesters[i].gpa > semesters[idx].gpa) idx = i;
    }
    return idx;
  }

  int get worstSemesterIndex {
    if (semesters.length < 2) return -1;
    var idx = 0;
    for (var i = 1; i < semesters.length; i++) {
      if (semesters[i].gpa < semesters[idx].gpa) idx = i;
    }
    return idx;
  }

  /// Grade → count across all courses (newest-to-oldest), ordered best→worst.
  Map<String, int> gradeDistribution() {
    const order = ['A+', 'A', 'A-', 'B+', 'B', 'B-', 'C+', 'C', 'D', 'F'];
    final counts = <String, int>{};
    for (final sem in semesters) {
      for (final c in sem.courses) {
        final g = c.grade.toUpperCase();
        if (order.contains(g)) counts[g] = (counts[g] ?? 0) + 1;
      }
    }
    return {
      for (final g in order)
        if ((counts[g] ?? 0) > 0) g: counts[g]!,
    };
  }
}
