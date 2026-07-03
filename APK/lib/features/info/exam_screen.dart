import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/app_colors.dart';
import '../../data/exam_repository.dart';
import '../../shared/app_toast.dart';
import 'routine_export.dart';
import 'routine_template.dart';

/// Mid / Final term exam routine — searchable by batch/section, with rich exam
/// cards (day, weekday, date, course code + title, time, Today/past states).
/// Mirrors the website's exam.js.
class ExamScreen extends StatefulWidget {
  const ExamScreen({super.key});

  @override
  State<ExamScreen> createState() => _ExamScreenState();
}

class _ExamScreenState extends State<ExamScreen> {
  String _type = 'mid';
  final _batch = TextEditingController(text: '62');
  final _section = TextEditingController(text: 'B');
  String _batchVal = '62';
  String _sectionVal = 'B';
  late Future<List<ExamItem>> _future = _load();

  Future<List<ExamItem>> _load() => ExamRepository.instance.load(
    _type,
    batch: _batchVal,
    section: _sectionVal,
  );

  @override
  void dispose() {
    _batch.dispose();
    _section.dispose();
    super.dispose();
  }

  void _switch(String type) {
    if (_type == type) return;
    setState(() {
      _type = type;
      _future = _load();
    });
  }

  void _search() {
    FocusScope.of(context).unfocus();
    final b = _batch.text.trim();
    final s = _section.text.trim().toUpperCase();
    if (b.isEmpty || s.isEmpty) return;
    setState(() {
      _batchVal = b;
      _sectionVal = s;
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Exam Schedule'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/info'),
        ),
        actions: [
          IconButton(
            tooltip: 'Download',
            icon: const Icon(Icons.download_rounded, size: 22),
            onPressed: _download,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: _toggle(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
            child: _searchRow(),
          ),
          Expanded(
            child: FutureBuilder<List<ExamItem>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.accent),
                  );
                }
                final items = snap.data ?? [];
                if (items.isEmpty) {
                  return _empty();
                }
                final upcoming = items.where((e) => !_isPast(e.dateObj)).length;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                  children: [
                    _summary(items.length, upcoming),
                    const SizedBox(height: 10),
                    ...items.map(_card),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggle() {
    Widget seg(String label, String type) {
      final sel = _type == type;
      return Expanded(
        child: GestureDetector(
          onTap: () => _switch(type),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              gradient: sel ? AppColors.accentGradient : null,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: sel ? Colors.white : AppColors.textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 13.5,
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
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [seg('Mid Term', 'mid'), seg('Final Term', 'final')],
      ),
    );
  }

  Widget _searchRow() {
    InputDecoration dec(String label) => InputDecoration(
      labelText: label,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
    return Row(
      children: [
        SizedBox(
          width: 90,
          child: TextField(
            controller: _batch,
            style: const TextStyle(color: AppColors.text, fontSize: 14),
            decoration: dec('Batch'),
            onSubmitted: (_) => _search(),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 80,
          child: TextField(
            controller: _section,
            style: const TextStyle(color: AppColors.text, fontSize: 14),
            decoration: dec('Section'),
            onSubmitted: (_) => _search(),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _search,
            icon: const Icon(Icons.search_rounded, size: 18),
            label: const Text('Search'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _summary(int total, int upcoming) {
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            color: Color(0xFF34D399),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${_type == 'final' ? 'Final Term' : 'Mid Term'}  ·  Batch $_batchVal, Section $_sectionVal',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$total exam${total == 1 ? '' : 's'}',
            style: const TextStyle(
              color: AppColors.accentBright,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  bool _isToday(DateTime? d) {
    if (d == null) return false;
    final n = DateTime.now();
    return d.year == n.year && d.month == n.month && d.day == n.day;
  }

  bool _isPast(DateTime? d) {
    if (d == null) return false;
    final n = DateTime.now();
    return DateTime(
      d.year,
      d.month,
      d.day,
    ).isBefore(DateTime(n.year, n.month, n.day));
  }

  Widget _card(ExamItem e) {
    final color = _courseColor(e.course);
    final past = _isPast(e.dateObj);
    final today = _isToday(e.dateObj);
    return Opacity(
      opacity: past ? 0.6 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: today ? color.withValues(alpha: 0.06) : AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border(
            left: BorderSide(
              color: today ? color : color.withValues(alpha: 0.55),
              width: 4,
            ),
            top: BorderSide(
              color: today ? color.withValues(alpha: 0.4) : AppColors.border,
            ),
            right: BorderSide(
              color: today ? color.withValues(alpha: 0.4) : AppColors.border,
            ),
            bottom: BorderSide(
              color: today ? color.withValues(alpha: 0.4) : AppColors.border,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Date column
              SizedBox(
                width: 58,
                child: Column(
                  children: [
                    if (e.dayLabel.isNotEmpty)
                      Text(
                        e.dayLabel.toUpperCase(),
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),
                    Text(
                      e.dateObj != null
                          ? DateFormat('dd').format(e.dateObj!)
                          : '--',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                        height: 1.1,
                      ),
                    ),
                    Text(
                      e.dateObj != null
                          ? DateFormat('MMM').format(e.dateObj!)
                          : '',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (e.weekday.isNotEmpty)
                      Text(
                        e.weekday.length > 3
                            ? e.weekday.substring(0, 3)
                            : e.weekday,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 9,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(width: 1, height: 44, color: AppColors.border),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            e.course,
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        if (today) ...[
                          const SizedBox(width: 7),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF34D399,
                              ).withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: const Text(
                              'TODAY',
                              style: TextStyle(
                                color: Color(0xFF34D399),
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (e.courseName.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        e.courseName,
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                    ],
                    if (e.time.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          const Icon(
                            Icons.schedule_rounded,
                            size: 12,
                            color: AppColors.muted,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            e.time,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _download() async {
    final items = await _future;
    if (!mounted) return;
    if (items.isEmpty) {
      AppToast.show(context, 'No exams to download.');
      return;
    }
    final rows = <List<String>>[];
    for (var i = 0; i < items.length; i++) {
      final e = items[i];
      final date = e.dateObj != null
          ? DateFormat('dd MMM yyyy').format(e.dateObj!)
          : '--';
      final wd = e.weekday.isNotEmpty ? e.weekday : e.dayLabel;
      rows.add([date, wd, e.course, e.courseName, e.time]);
    }
    final label = _type == 'final' ? 'Final Term' : 'Mid Term';
    if (!mounted) return;
    RoutineExport.showImageSheet(
      context,
      baseName: 'exam-$_type-$_batchVal-$_sectionVal',
      build: () => InfoTablePrintTemplate(
        title: '$label Exam Routine',
        subtitle:
            'Batch $_batchVal · Section $_sectionVal · ${items.length} exam${items.length == 1 ? '' : 's'}',
        headers: const ['Date', 'Day', 'Course', 'Title', 'Time'],
        rows: rows,
        columnFlex: const [1.2, 0.9, 1.0, 2.2, 1.1],
        accentColumn: 2,
      ),
    );
  }

  Widget _empty() => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.event_busy_rounded,
            color: AppColors.muted,
            size: 44,
          ),
          const SizedBox(height: 14),
          Text(
            _type == 'final'
                ? 'No final-term exams for Batch $_batchVal, Section $_sectionVal yet.'
                : 'No mid-term exams for Batch $_batchVal, Section $_sectionVal yet.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13.5,
              height: 1.5,
            ),
          ),
        ],
      ),
    ),
  );

  /// Deterministic colour from a course code (mirrors the site's courseColor).
  static Color _courseColor(String code) {
    const palette = [
      Color(0xFF7C3AED),
      Color(0xFF2563EB),
      Color(0xFF059669),
      Color(0xFFDC2626),
      Color(0xFFD97706),
      Color(0xFFDB2777),
      Color(0xFF0891B2),
      Color(0xFF9333EA),
      Color(0xFF0D9488),
      Color(0xFFE11D48),
      Color(0xFF4F46E5),
      Color(0xFFCA8A04),
    ];
    var h = 0;
    for (var i = 0; i < code.length; i++) {
      h = (h * 31 + code.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    return palette[h % palette.length];
  }
}
