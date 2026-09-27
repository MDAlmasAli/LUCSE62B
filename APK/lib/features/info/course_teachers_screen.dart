import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_colors.dart';
import '../../data/course_teachers_repository.dart';

/// Course Teachers — "By Teacher" and "By Course" views built from the routine.
/// Mirrors the website's course-teachers.js.
class CourseTeachersScreen extends StatefulWidget {
  const CourseTeachersScreen({super.key});

  @override
  State<CourseTeachersScreen> createState() => _CourseTeachersScreenState();
}

class _CourseTeachersScreenState extends State<CourseTeachersScreen> {
  late Future<CourseTeachersData> _future = CourseTeachersRepository.instance.load();
  bool _byTeacher = true;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Course Teachers'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/info'),
        ),
      ),
      body: FutureBuilder<CourseTeachersData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: AppColors.accent));
          }
          final data = snap.data;
          if (data == null || (data.byTeacher.isEmpty && data.byCourse.isEmpty)) {
            return _error();
          }
          return Column(
            children: [
              _controls(data),
              Expanded(
                child: _byTeacher ? _teacherList(data) : _courseList(data),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _controls(CourseTeachersData data) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: Column(
        children: [
          Row(
            children: [
              _tab('By Teacher', Icons.co_present_rounded, data.byTeacher.length, _byTeacher,
                  () => setState(() => _byTeacher = true)),
              const SizedBox(width: 8),
              _tab('By Course', Icons.menu_book_rounded, data.byCourse.length, !_byTeacher,
                  () => setState(() => _byTeacher = false)),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            onChanged: (v) => setState(() => _query = v.toLowerCase().trim()),
            style: TextStyle(color: AppColors.text, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search teacher, course or code…',
              prefixIcon: Icon(Icons.search_rounded, size: 18, color: AppColors.muted),
              isDense: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tab(String label, IconData icon, int count, bool active, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            gradient: active ? AppColors.accentGradient : null,
            color: active ? null : AppColors.card,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: active ? Colors.transparent : AppColors.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: active ? Colors.white : AppColors.textSecondary),
              const SizedBox(width: 7),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: active ? Colors.white : AppColors.textSecondary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: (active ? Colors.white : AppColors.muted).withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('$count',
                    style: TextStyle(
                        color: active ? Colors.white : AppColors.textSecondary,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _teacherList(CourseTeachersData data) {
    final list = _query.isEmpty
        ? data.byTeacher
        : data.byTeacher.where((t) {
            return t.name.toLowerCase().contains(_query) ||
                t.initials.toLowerCase().contains(_query) ||
                t.desig.toLowerCase().contains(_query) ||
                t.courses.any((c) => c.code.toLowerCase().contains(_query) || c.name.toLowerCase().contains(_query));
          }).toList();
    if (list.isEmpty) return _noMatch();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final t = list[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.name,
                  style: TextStyle(color: AppColors.textBright, fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Row(
                children: [
                  _initialsChip(t.initials),
                  if (t.desig.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(t.desig,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: AppColors.accentBright, fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ],
              ),
              if (t.courses.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('COURSES THIS SEMESTER',
                    style: TextStyle(color: AppColors.muted, fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                const SizedBox(height: 7),
                ...t.courses.map((c) => _courseTile(c.code, c.name, c.sections)),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _courseList(CourseTeachersData data) {
    final list = _query.isEmpty
        ? data.byCourse
        : data.byCourse.where((c) {
            return c.code.toLowerCase().contains(_query) ||
                c.name.toLowerCase().contains(_query) ||
                c.teachers.any((t) => t.name.toLowerCase().contains(_query) || t.initials.toLowerCase().contains(_query));
          }).toList();
    if (list.isEmpty) return _noMatch();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final c = list[i];
        final color = _courseColor(c.code);
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(6)),
                child: Text(c.code,
                    style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
              ),
              const SizedBox(height: 7),
              Text(c.name.isEmpty ? c.code : c.name,
                  style: TextStyle(color: AppColors.textBright, fontSize: 14.5, fontWeight: FontWeight.w700, height: 1.3)),
              if (c.teachers.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('TEACHERS & SECTIONS',
                    style: TextStyle(color: AppColors.muted, fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                const SizedBox(height: 7),
                ...c.teachers.map((t) => _teacherTile(t.initials, t.name, t.desig, t.sections)),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _courseTile(String code, String name, List<String> sections) {
    final color = _courseColor(code);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(5)),
                child: Text(code, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
              ),
              if (name.isNotEmpty) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(name,
                      style: TextStyle(color: AppColors.text, fontSize: 12, fontWeight: FontWeight.w600, height: 1.3)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          _sectionChips(sections),
        ],
      ),
    );
  }

  Widget _teacherTile(String initials, String name, String desig, List<String> sections) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _initialsChip(initials),
              const SizedBox(width: 8),
              Expanded(
                child: Text(name,
                    style: TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              if (desig.isNotEmpty)
                Flexible(
                  child: Text(desig,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          _sectionChips(sections),
        ],
      ),
    );
  }

  Widget _initialsChip(String initials) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(initials,
            style: const TextStyle(
                color: Color(0xFFC4B5FD), fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.w700)),
      );

  Widget _sectionChips(List<String> sections) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: sections.map((s) {
        final parts = s.split('-');
        final color = _courseColor('B${parts.join()}');
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Text(parts.length == 2 ? '${parts[0]} ${parts[1]}' : s,
              style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
        );
      }).toList(),
    );
  }

  Widget _noMatch() => Center(
        child: Text('No matches found.', style: TextStyle(color: AppColors.muted, fontSize: 14)),
      );

  Widget _error() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, color: AppColors.muted, size: 34),
            const SizedBox(height: 12),
            Text('Could not load course teacher info.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: () => setState(() => _future = CourseTeachersRepository.instance.load()),
              child: const Text('Retry'),
            ),
          ],
        ),
      );

  static Color _courseColor(String code) {
    const palette = [
      Color(0xFF7C3AED), Color(0xFF2563EB), Color(0xFF059669), Color(0xFFDC2626),
      Color(0xFFD97706), Color(0xFFDB2777), Color(0xFF0891B2), Color(0xFF9333EA),
      Color(0xFF0D9488), Color(0xFFE11D48), Color(0xFF4F46E5), Color(0xFFCA8A04),
    ];
    var h = 0;
    for (var i = 0; i < code.length; i++) {
      h = (h * 31 + code.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    return palette[h % palette.length];
  }
}
