import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_colors.dart';
import '../../core/sheets_api.dart';
import '../../core/worker_api.dart';
import '../../data/session.dart';
import '../results/results_model.dart';

class _Course {
  final String code, title, credit, section, prereq;
  _Course(this.code, this.title, this.credit, this.section, this.prereq);
}

/// Course Offer — the all-batch course offer (LU_Course_Offer), per batch, with
/// the student's retake (F) / improve (C/D/B-) courses highlighted. Mirrors the
/// website's all-course.js.
class CourseListScreen extends StatefulWidget {
  const CourseListScreen({super.key});

  @override
  State<CourseListScreen> createState() => _CourseListScreenState();
}

class _CourseListScreenState extends State<CourseListScreen> {
  late final Future<Map<String, List<_Course>>> _future = _load();
  String? _activeBatch;
  Set<String> _retake = {};
  Set<String> _improve = {};

  static const _retakeColor = Color(0xFFF43F5E);
  static const _improveColor = Color(0xFFFB923C);

  @override
  void initState() {
    super.initState();
    _loadMyCodes();
  }

  Future<Map<String, List<_Course>>> _load() async {
    final rows = await SheetsApi.instance.sheet('LU_Course_Offer');
    final batches = <String, List<_Course>>{};
    if (rows.isEmpty) return batches;
    final first = rows[0].isNotEmpty ? rows[0][0].toLowerCase().trim() : '';
    final start = (first == 'batch' || first == 'semester') ? 1 : 0;
    for (var i = start; i < rows.length; i++) {
      final r = rows[i];
      String at(int n) => n < r.length ? r[n].trim() : '';
      final batch = at(0);
      if (batch.isEmpty || at(1).isEmpty) continue;
      batches
          .putIfAbsent(batch, () => [])
          .add(_Course(at(1), at(2), at(3), at(4), at(5)));
    }
    return batches;
  }

  Future<void> _loadMyCodes() async {
    final s = Session.instance.student;
    if (s == null || s.isDemo) return;
    final dob = await Session.instance.storedDob(s.id);
    if (dob == null || dob.isEmpty) return;
    try {
      final raw = await WorkerApi.instance.result(s.id, dob);
      final data = ResultData.parse(raw);
      if (data == null) return;
      final ri = data.retakeImprove();
      if (mounted) {
        setState(() {
          _retake = ri.fail.map((e) => e.code.toUpperCase()).toSet();
          _improve = ri.improve.map((e) => e.code.toUpperCase()).toSet();
        });
      }
    } catch (_) {}
  }

  static String _norm(String c) {
    final s = c.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final m = RegExp(r'^([A-Z]+)(\d.*)$').firstMatch(s);
    return m != null ? '${m.group(1)}-${m.group(2)}' : s;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Course Offer'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/info'),
        ),
      ),
      body: FutureBuilder<Map<String, List<_Course>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            );
          }
          final batches = snap.data ?? {};
          if (batches.isEmpty) {
            return const Center(
              child: Text(
                'No course data found.',
                style: TextStyle(color: AppColors.muted, fontSize: 14),
              ),
            );
          }
          final order = batches.keys.toList();
          final active =
              _activeBatch ?? (order.contains('62') ? '62' : order.first);
          final courses = batches[active] ?? [];
          final totalCr = courses.fold<double>(
            0,
            (s, c) => s + (double.tryParse(c.credit) ?? 0),
          );
          final myRetake = courses
              .where((c) => _retake.contains(_norm(c.code)))
              .length;
          final myImprove = courses
              .where((c) => _improve.contains(_norm(c.code)))
              .length;

          return Column(
            children: [
              // batch chips
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
                  children: [
                    for (final b in order)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () => setState(() => _activeBatch = b),
                          child: Container(
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(horizontal: 15),
                            decoration: BoxDecoration(
                              gradient: b == active
                                  ? AppColors.accentGradient
                                  : null,
                              color: b == active ? null : AppColors.card,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: b == active
                                    ? Colors.transparent
                                    : AppColors.border,
                              ),
                            ),
                            child: Text(
                              'Batch $b',
                              style: TextStyle(
                                color: b == active
                                    ? Colors.white
                                    : AppColors.textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // summary
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '${courses.length} courses · ${totalCr.toStringAsFixed(totalCr % 1 == 0 ? 0 : 1)} credits',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (myRetake > 0)
                      _miniBadge('$myRetake Retake', _retakeColor),
                    if (myImprove > 0)
                      _miniBadge('$myImprove Improve', _improveColor),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 2, 14, 24),
                  itemCount: courses.length,
                  itemBuilder: (_, i) => _courseCard(i + 1, courses[i]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _miniBadge(String label, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.13),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: c.withValues(alpha: 0.3)),
    ),
    child: Text(
      label,
      style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w700),
    ),
  );

  Widget _courseCard(int num, _Course c) {
    final norm = _norm(c.code);
    final isRetake = _retake.contains(norm);
    final isImprove = _improve.contains(norm);
    final accent = isRetake
        ? _retakeColor
        : isImprove
        ? _improveColor
        : null;
    final codeColor = _courseColor(c.code);

    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      decoration: BoxDecoration(
        color: accent != null ? accent.withValues(alpha: 0.05) : AppColors.card,
        borderRadius: BorderRadius.circular(13),
        border: Border(
          left: BorderSide(
            color: accent ?? AppColors.border,
            width: accent != null ? 3 : 1,
          ),
          top: BorderSide(
            color: accent?.withValues(alpha: 0.3) ?? AppColors.border,
          ),
          right: BorderSide(
            color: accent?.withValues(alpha: 0.3) ?? AppColors.border,
          ),
          bottom: BorderSide(
            color: accent?.withValues(alpha: 0.3) ?? AppColors.border,
          ),
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '$num',
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 9),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: codeColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  c.code,
                  style: TextStyle(
                    color: codeColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              if (isRetake) _miniBadge('Retake', _retakeColor),
              if (isImprove) _miniBadge('Improve', _improveColor),
            ],
          ),
          if (c.title.isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(
              c.title,
              style: const TextStyle(
                color: AppColors.textBright,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 5,
            children: [
              if (c.credit.isNotEmpty)
                _infoChip(Icons.star_outline_rounded, '${c.credit} cr'),
              if (c.section.isNotEmpty)
                _infoChip(Icons.grid_view_rounded, 'Sec ${c.section}'),
              if (c.prereq.isNotEmpty)
                _infoChip(Icons.lock_outline_rounded, 'Pre: ${c.prereq}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoChip(IconData icon, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(7),
      border: Border.all(color: AppColors.border),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: AppColors.muted),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
        ),
      ],
    ),
  );

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
