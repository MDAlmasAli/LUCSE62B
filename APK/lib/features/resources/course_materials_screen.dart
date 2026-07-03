import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../core/sheets_api.dart';
import 'drive_file_list_view.dart';
import 'resources_screen.dart';

/// File browser for a course's Mid / Final material folders (Google Drive),
/// with the course Mark Distribution on top. Files and sub-folders are handled
/// by [DriveFileListView].
class CourseMaterialsScreen extends StatefulWidget {
  final CourseMaterial course;
  const CourseMaterialsScreen({super.key, required this.course});

  @override
  State<CourseMaterialsScreen> createState() => _CourseMaterialsScreenState();
}

class _CourseMaterialsScreenState extends State<CourseMaterialsScreen> {
  String _tab = 'mid';
  List<({String component, String marks})> _marks = [];

  String get _folderId =>
      _tab == 'mid' ? widget.course.midFolderId : widget.course.finalFolderId;

  @override
  void initState() {
    super.initState();
    _loadMarks();
  }

  /// Mark distribution from the "Marks" sheet (CourseCode | Component | Marks).
  Future<void> _loadMarks() async {
    try {
      final rows = await SheetsApi.instance.sheet('Marks');
      final code = widget.course.code.trim().toLowerCase();
      final out = <({String component, String marks})>[];
      for (final r in rows) {
        if (r.length < 3) continue;
        final c = r[0].trim();
        if (c.isEmpty || c.toLowerCase() == 'coursecode') continue;
        if (c.toLowerCase() != code) continue;
        final comp = r[1].trim();
        if (comp.isEmpty) continue;
        out.add((component: comp, marks: r[2].trim()));
      }
      if (mounted) setState(() => _marks = out);
    } catch (_) {}
  }

  void _switch(String tab) {
    if (_tab == tab) return;
    setState(() => _tab = tab);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(widget.course.code),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
            child: Text(
              widget.course.name,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12.5,
              ),
            ),
          ),
          if (_marks.isNotEmpty) _marksSection(),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: _toggle(),
          ),
          Expanded(
            child: _folderId.isEmpty
                ? const Center(
                    child: Text(
                      'No files in this folder yet.',
                      style: TextStyle(color: AppColors.muted, fontSize: 14),
                    ),
                  )
                : DriveFileListView(
                    key: ValueKey(_folderId),
                    folderId: _folderId,
                    courseCode: widget.course.code,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _toggle() {
    Widget seg(String label, String tab) {
      final sel = _tab == tab;
      return Expanded(
        child: GestureDetector(
          onTap: () => _switch(tab),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              gradient: sel ? AppColors.accentGradient : null,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: sel ? Colors.white : AppColors.textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [seg('Mid', 'mid'), seg('Final', 'final')]),
    );
  }

  Widget _marksSection() {
    const palette = [
      Color(0xFFA78BFA),
      Color(0xFF38BDF8),
      Color(0xFF34D399),
      Color(0xFFF87171),
      Color(0xFFFBBF24),
      Color(0xFFF472B6),
      Color(0xFF22D3EE),
    ];
    final total = _marks.fold<double>(
      0,
      (s, m) => s + (double.tryParse(m.marks) ?? 0),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.pie_chart_rounded,
              size: 13,
              color: Color(0xFFFBBF24),
            ),
            const SizedBox(width: 5),
            Text(
              total > 0 ? 'Marks · ${_fmt(total)}' : 'Marks',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 7),
            Container(width: 1, height: 20, color: AppColors.border),
            const SizedBox(width: 7),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var i = 0; i < _marks.length; i++) ...[
                      if (i > 0) const SizedBox(width: 5),
                      _markPill(_marks[i], palette[i % palette.length]),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _markPill(({String component, String marks}) m, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            m.marks,
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            m.component,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}
