import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../../core/app_colors.dart';
import '../../core/constants.dart';
import '../../core/sheets_api.dart';
import '../../core/worker_api.dart';
import '../../data/session.dart';
import '../../shared/app_toast.dart';
import '../../shared/suggest_field.dart';
import 'attendance_pdf.dart';

class _Student {
  final String id;
  final String name;
  const _Student(this.id, this.name);
}

class _CourseChoice {
  final String teacher;
  const _CourseChoice(this.teacher);
}

/// Daily attendance roll-call for the class admin. Mirrors attendance.html:
/// loads the student list + today's present set, lets the admin tap to
/// mark/unmark (optimistic), shows live stats, a course field with suggestions,
/// a copy-able text report and a formal PDF export.
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  final _course = TextEditingController();
  final _teacher = TextEditingController();
  List<_Student> _students = [];
  final Set<String> _present = {};
  List<Suggestion> _courseSuggestions = [];
  String _query = '';
  bool _loading = true;
  bool _busyPdf = false;

  bool get _isAdmin => Session.instance.student?.id == K.attendanceAdminId;

  @override
  void initState() {
    super.initState();
    if (_isAdmin) _load();
  }

  @override
  void dispose() {
    _course.dispose();
    _teacher.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    SheetsApi.instance.clearCache();
    await _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      SheetsApi.instance.sheet('Student Info'),
      WorkerApi.instance.attendancePresentIds(),
      SheetsApi.instance
          .sheet('CPG_Courses')
          .catchError((_) => <List<String>>[]),
    ]);
    final rows = results[0] as List<List<String>>;
    final present = results[1] as List<String>;
    final courses = results[2] as List<List<String>>;

    final out = <_Student>[];
    final digits = RegExp(r'^\d+$');
    for (final r in rows) {
      if (r.length < 3) continue;
      final sl = r[0].trim(), id = r[1].trim(), name = r[2].trim();
      if (!digits.hasMatch(sl) || id.isEmpty || name.isEmpty) continue;
      out.add(_Student(id, name));
    }
    _students = out;

    final seen = <String>{};
    _courseSuggestions = [];
    for (final r in courses) {
      if (r.isEmpty) continue;
      final title = r[0].trim();
      final code = r.length > 1 ? r[1].trim() : '';
      final teacher = r.length > 4 ? r[4].trim() : '';
      if (title.isEmpty || title.toLowerCase() == 'title') continue;
      if (seen.add(title.toLowerCase())) {
        _courseSuggestions.add(
          Suggestion(title, secondary: code, data: _CourseChoice(teacher)),
        );
      }
    }

    _present
      ..clear()
      ..addAll(present);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _toggle(_Student s) async {
    final willPresent = !_present.contains(s.id);
    setState(() {
      if (willPresent) {
        _present.add(s.id);
      } else {
        _present.remove(s.id);
      }
    });
    final ok = await WorkerApi.instance.attendanceSet(
      K.attendanceAdminId,
      s.id,
      s.name,
      willPresent,
    );
    if (!ok && mounted) {
      setState(() {
        if (willPresent) {
          _present.remove(s.id);
        } else {
          _present.add(s.id);
        }
      });
      AppToast.show(context, 'Save failed — reverted', error: true);
    }
  }

  Future<void> _clear() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text(
          'Clear attendance?',
          style: TextStyle(color: AppColors.textBright, fontSize: 16),
        ),
        content: const Text(
          "This clears everyone's attendance for today.",
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.muted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear', style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
    if (yes != true) return;
    final ok = await WorkerApi.instance.attendanceClear(K.attendanceAdminId);
    if (ok && mounted) {
      setState(() => _present.clear());
      AppToast.show(context, 'Attendance cleared');
    } else if (mounted) {
      AppToast.show(context, 'Could not clear', error: true);
    }
  }

  static String _nickname(String full) {
    final re = RegExp(
      r'^(md\.?|mohammad|mohammed|muhammad|muhammed|abdul|abu|al|sk\.?|sheikh|khandoker|kha\.?)\s+',
      caseSensitive: false,
    );
    var s = full.trim(), prev = '';
    while (s != prev) {
      prev = s;
      s = s.replaceFirst(re, '');
    }
    return s.split(RegExp(r'\s+')).first;
  }

  void _copyReport() {
    final now = DateTime.now();
    const mo = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final dateStr = '${now.day} ${mo[now.month - 1]} ${now.year}';
    final h12 = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final timeStr =
        '$h12:${now.minute.toString().padLeft(2, '0')} ${now.hour >= 12 ? 'PM' : 'AM'}';
    final course = _course.text.trim();
    final teacher = _teacher.text.trim();
    final present = _students.where((s) => _present.contains(s.id)).toList();
    final absent = _students.length - present.length;

    final lines = <String>[
      '🏛️ Leading University',
      '📋 CSE 62B Attendance — $dateStr, $timeStr',
      if (course.isNotEmpty) '📚 Course: $course',
      '━━━━━━━━━━━━━━━━━━━━',
      '✅ Present (${present.length}):',
      for (var i = 0; i < present.length; i++)
        '${i + 1}. ${_nickname(present[i].name)} — ${present[i].id}',
      '━━━━━━━━━━━━━━━━━━━━',
      'Total: ${_students.length}  |  Present: ${present.length}  |  Absent: $absent',
    ];
    if (teacher.isNotEmpty) {
      lines.insert(course.isNotEmpty ? 3 : 2, 'Teacher: $teacher');
    }
    Clipboard.setData(ClipboardData(text: lines.join('\n')));
    AppToast.show(context, 'Report copied to clipboard');
  }

  Future<void> _downloadPdf() async {
    if (_students.isEmpty) return;
    setState(() => _busyPdf = true);
    try {
      // Whole roster in sheet order, each tagged present/absent (one combined
      // table with a Status column, like the website).
      final roster = _students
          .map(
            (s) => (name: s.name, id: s.id, present: _present.contains(s.id)),
          )
          .toList();
      final bytes = await AttendancePdf.build(
        course: _course.text.trim(),
        teacher: _teacher.text.trim(),
        batchSection: 'Batch 62, Section B',
        students: roster,
      );
      final now = DateTime.now();
      final stamp =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'CSE62B-Attendance-$stamp.pdf',
      );
    } catch (_) {
      if (mounted) AppToast.show(context, 'Could not export PDF', error: true);
    } finally {
      if (mounted) setState(() => _busyPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAdmin) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          title: const Text('Attendance'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.canPop() ? context.pop() : context.go('/'),
          ),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'Attendance is available to the class admin only.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 14),
            ),
          ),
        ),
      );
    }

    final filtered = _query.isEmpty
        ? _students
        : _students
              .where(
                (s) =>
                    s.name.toLowerCase().contains(_query) ||
                    s.id.contains(_query),
              )
              .toList();
    final total = _students.length;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Attendance'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
        actions: [
          IconButton(
            tooltip: 'Copy report',
            icon: const Icon(Icons.copy_rounded, size: 20),
            onPressed: total == 0 ? null : _copyReport,
          ),
          IconButton(
            tooltip: 'Export PDF',
            icon: _busyPdf
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.accentBright,
                    ),
                  )
                : const Icon(Icons.picture_as_pdf_rounded, size: 21),
            onPressed: total == 0 || _busyPdf ? null : _downloadPdf,
          ),
          IconButton(
            tooltip: 'Clear all',
            icon: const Icon(Icons.delete_sweep_rounded, size: 22),
            onPressed: total == 0 ? null : _clear,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            )
          : Column(
              children: [
                _statsBar(total, _present.length),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
                  child: Column(
                    children: [
                      SuggestField(
                        controller: _course,
                        label: 'Course (for the report)',
                        hint: 'Type to search a course…',
                        suggestions: () => _courseSuggestions,
                        showAllOnFocus: true,
                        onPicked: (suggestion) {
                          final data = suggestion.data;
                          if (data is _CourseChoice) {
                            _teacher.text = data.teacher;
                          }
                        },
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _teacher,
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 13.5,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Course teacher',
                          hintText: 'Auto-selected with the course',
                          prefixIcon: Icon(
                            Icons.person_outline_rounded,
                            size: 18,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 13.5,
                        ),
                        onChanged: (v) =>
                            setState(() => _query = v.trim().toLowerCase()),
                        decoration: const InputDecoration(
                          hintText: 'Search name or ID...',
                          isDense: true,
                          prefixIcon: Icon(
                            Icons.search,
                            size: 18,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    color: AppColors.accent,
                    backgroundColor: AppColors.card,
                    onRefresh: _refresh,
                    child: filtered.isEmpty
                        ? ListView(
                            children: const [
                              Padding(
                                padding: EdgeInsets.only(top: 80),
                                child: Center(
                                  child: Text(
                                    'No students found.',
                                    style: TextStyle(color: AppColors.muted),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                            itemCount: filtered.length,
                            itemBuilder: (_, i) => _card(filtered[i], i + 1),
                          ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _statsBar(int total, int present) {
    final absent = total - present;
    Widget stat(String label, int n, Color c) => Column(
      children: [
        Text(
          '$n',
          style: TextStyle(color: c, fontSize: 19, fontWeight: FontWeight.w800),
        ),
        Text(
          label,
          style: const TextStyle(color: AppColors.muted, fontSize: 11),
        ),
      ],
    );
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          stat('Total', total, AppColors.textBright),
          stat('Present', present, const Color(0xFF34D399)),
          stat('Absent', absent, AppColors.red),
        ],
      ),
    );
  }

  Widget _card(_Student s, int serial) {
    final isPresent = _present.contains(s.id);
    const green = Color(0xFF34D399);
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: GestureDetector(
        onTap: () => _toggle(s),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
          decoration: BoxDecoration(
            color: isPresent ? green.withValues(alpha: 0.1) : AppColors.card,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: isPresent
                  ? green.withValues(alpha: 0.55)
                  : AppColors.border,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: isPresent ? green : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isPresent
                        ? green
                        : AppColors.muted.withValues(alpha: 0.5),
                  ),
                ),
                child: isPresent
                    ? const Icon(Icons.check, color: Colors.white, size: 17)
                    : Center(
                        child: Text(
                          '$serial',
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.name,
                      softWrap: true,
                      style: TextStyle(
                        color: isPresent ? green : AppColors.textBright,
                        fontSize: 14,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      s.id,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (isPresent)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Text(
                    'Present',
                    style: TextStyle(
                      color: green,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
