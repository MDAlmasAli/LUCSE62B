import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_colors.dart';
import '../../core/sheets_api.dart';
import '../../data/session.dart';
import '../../core/worker_api.dart';
import '../../shared/app_toast.dart';
import 'result_import.dart';
import 'results_model.dart';

/// Result dashboard — Overview / Analytics / Compare tabs, mirroring the
/// website's result-dashboard.html (CGPA, degree-credit progress, grade &
/// GPA charts, a target-CGPA calculator, retake/improve summary, and a
/// two-student comparison). Uses the DOB already verified at login.
class ResultsScreen extends StatefulWidget {
  const ResultsScreen({super.key});

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 3, vsync: this);
  bool _loading = true;
  String? _error;
  bool _blocked = false;
  ResultData? _data;
  String? _dob; // verified DOB (needed to store an imported result)

  // Analytics: target CGPA calculator.
  double _target = 3.50;

  // Compare tab.
  final _cmpId = TextEditingController();
  DateTime? _cmpDob;
  bool _cmpLoading = false;
  String? _cmpError;
  ResultData? _cmpData;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    _cmpId.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _blocked = false;
    });
    final s = Session.instance.student;
    if (s == null || s.isDemo) {
      setState(() {
        _loading = false;
        _error = 'Results are available for logged-in students.';
      });
      return;
    }
    try {
      var dob = await Session.instance.storedDob(s.id);
      dob ??= await WorkerApi.instance.dobGet(s.id);
      if (dob == null || dob.isEmpty) {
        setState(() {
          _loading = false;
          _error =
              'We could not find your verified date of birth. Please re-open the app to verify it.';
        });
        return;
      }
      _dob = dob;
      final raw = await WorkerApi.instance.result(s.id, dob);
      final data = ResultData.parse(raw);
      if (data == null) {
        setState(() {
          _loading = false;
          _blocked = true;
        });
        return;
      }
      setState(() {
        _loading = false;
        _data = data;
      });
    } catch (_) {
      setState(() {
        _loading = false;
        _blocked = true;
      });
    }
  }

  void _openImport() {
    final s = Session.instance.student;
    if (s == null || s.isDemo) return;
    final dob = _dob;
    if (dob == null || dob.isEmpty) {
      AppToast.show(
        context,
        'Verify your date of birth first (re-open the app).',
        error: true,
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ImportSheet(
        studentId: s.id,
        dob: dob,
        onImported: () {
          AppToast.show(context, 'Result imported successfully.');
          _load();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ready = !_loading && !_blocked && _error == null && _data != null;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Results'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
        actions: [
          if (!_loading && Session.instance.student?.isDemo == false)
            IconButton(
              icon: const Icon(Icons.cloud_upload_rounded, size: 22),
              tooltip: 'Import result',
              onPressed: _openImport,
            ),
          if (!_loading)
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 22),
              onPressed: _load,
            ),
        ],
        bottom: ready
            ? TabBar(
                controller: _tab,
                indicatorColor: AppColors.accent,
                labelColor: AppColors.accentBright,
                unselectedLabelColor: AppColors.muted,
                labelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
                tabs: const [
                  Tab(text: 'Overview'),
                  Tab(text: 'Analytics'),
                  Tab(text: 'Compare'),
                ],
              )
            : null,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            )
          : _blocked
          ? _blockedView()
          : _error != null
          ? _messageView(_error!)
          : TabBarView(
              controller: _tab,
              children: [_overview(_data!), _analytics(_data!), _compareTab()],
            ),
    );
  }

  // ── Overview ──
  Widget _overview(ResultData d) {
    return RefreshIndicator(
      color: AppColors.accent,
      backgroundColor: AppColors.card,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
        children: [
          _headerCard(d),
          const SizedBox(height: 14),
          _creditProgress(d),
          const SizedBox(height: 18),
          _sectionLabel('Semesters'),
          const SizedBox(height: 8),
          ...d.semesters.asMap().entries.map(
            (e) => _semesterCard(d, e.key, e.value),
          ),
        ],
      ),
    );
  }

  // ── Analytics ──
  Widget _analytics(ResultData d) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
      children: [
        if (d.gradeDistribution().isNotEmpty) ...[
          _sectionLabel('Grade Distribution'),
          const SizedBox(height: 8),
          _gradeChart(d.gradeDistribution()),
          const SizedBox(height: 18),
        ],
        if (d.semesters.length > 1) ...[
          _sectionLabel('GPA by Semester'),
          const SizedBox(height: 8),
          _gpaTrend(d.semesters),
          const SizedBox(height: 18),
        ],
        _sectionLabel('Target CGPA'),
        const SizedBox(height: 8),
        _targetCalc(d),
        const SizedBox(height: 18),
        _sectionLabel('Retake & Improvement'),
        const SizedBox(height: 8),
        _retakeImprove(d),
      ],
    );
  }

  // ── Compare ──
  Widget _compareTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 28),
      children: [
        const Text(
          'Compare with another student',
          style: TextStyle(
            color: AppColors.textBright,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Enter a classmate’s Student ID and date of birth to compare results side by side.',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12.5,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _cmpId,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: AppColors.text, fontSize: 14),
          decoration: const InputDecoration(
            labelText: 'Student ID',
            hintText: 'e.g. 0182320012101068',
            prefixIcon: Icon(
              Icons.badge_outlined,
              size: 18,
              color: AppColors.muted,
            ),
          ),
        ),
        const SizedBox(height: 10),
        InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: _pickCmpDob,
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Date of birth',
              prefixIcon: Icon(
                Icons.cake_outlined,
                size: 18,
                color: AppColors.muted,
              ),
            ),
            child: Text(
              _cmpDob == null
                  ? 'Tap to choose'
                  : '${_cmpDob!.year}-${_two(_cmpDob!.month)}-${_two(_cmpDob!.day)}',
              style: TextStyle(
                color: _cmpDob == null ? AppColors.muted : AppColors.text,
                fontSize: 14,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _cmpLoading ? null : _runCompare,
            icon: _cmpLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.compare_arrows_rounded, size: 18),
            label: Text(_cmpLoading ? 'Loading…' : 'Compare'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(11),
              ),
            ),
          ),
        ),
        if (_cmpError != null) ...[
          const SizedBox(height: 14),
          Text(
            _cmpError!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.red, fontSize: 12.5),
          ),
        ],
        if (_cmpData != null) ...[
          const SizedBox(height: 20),
          _compareResult(_data!, _cmpData!),
        ],
      ],
    );
  }

  Future<void> _pickCmpDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 21),
      firstDate: DateTime(1960),
      lastDate: now,
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.accent,
            surface: AppColors.card,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _cmpDob = picked);
  }

  Future<void> _runCompare() async {
    final id = _cmpId.text.trim();
    if (id.isEmpty || _cmpDob == null) {
      setState(() => _cmpError = 'Enter a Student ID and date of birth.');
      return;
    }
    setState(() {
      _cmpLoading = true;
      _cmpError = null;
      _cmpData = null;
    });
    final dob =
        '${_cmpDob!.year}-${_two(_cmpDob!.month)}-${_two(_cmpDob!.day)}';
    try {
      final raw = await WorkerApi.instance.result(id, dob);
      final data = ResultData.parse(raw);
      if (data == null) {
        setState(
          () => _cmpError =
              "Couldn't load that result (LU verification or wrong details).",
        );
      } else {
        setState(() => _cmpData = data);
      }
    } catch (_) {
      setState(
        () => _cmpError =
            "Couldn't load that result. Check the ID and date of birth.",
      );
    } finally {
      if (mounted) setState(() => _cmpLoading = false);
    }
  }

  Widget _compareResult(ResultData me, ResultData them) {
    Widget col(ResultData r, bool isMe) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isMe
                ? AppColors.accent.withValues(alpha: 0.4)
                : AppColors.border,
          ),
        ),
        child: Column(
          children: [
            Text(
              isMe ? 'You' : r.name.split(' ').first,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textBright,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              r.cgpa.toStringAsFixed(2),
              style: TextStyle(
                color: _gpaColor(r.cgpa),
                fontSize: 26,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Text(
              'CGPA',
              style: TextStyle(color: AppColors.muted, fontSize: 10),
            ),
            const SizedBox(height: 12),
            _cmpRow(
              'Credits',
              r.totalCredit.toStringAsFixed(r.totalCredit % 1 == 0 ? 0 : 1),
            ),
            _cmpRow('Courses', '${r.coursesCompleted}'),
            _cmpRow('Semesters', '${r.semesters.length}'),
          ],
        ),
      ),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [col(me, true), const SizedBox(width: 10), col(them, false)],
    );
  }

  Widget _cmpRow(String label, String v) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.muted, fontSize: 11.5),
        ),
        Text(
          v,
          style: const TextStyle(
            color: AppColors.text,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );

  // ── Shared pieces ──
  Widget _messageView(String msg) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(
        msg,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: AppColors.muted,
          fontSize: 14,
          height: 1.5,
        ),
      ),
    ),
  );

  Widget _blockedView() => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.lock_clock_rounded,
            color: AppColors.muted,
            size: 46,
          ),
          const SizedBox(height: 16),
          const Text(
            "Couldn't fetch your result right now",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textBright,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Leading University now asks for a verification (CAPTCHA) before showing results, so it can’t be loaded automatically. Open your result on the LU page, copy it, then import it here once — it’ll be saved for next time.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _openImport,
            icon: const Icon(Icons.cloud_upload_rounded, size: 18),
            label: const Text('Import my result'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(11),
              ),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => launchUrl(
              Uri.parse('https://lus.ac.bd/result/'),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(
              Icons.open_in_new_rounded,
              size: 16,
              color: AppColors.accentBright,
            ),
            label: const Text(
              'Open LU Result Page',
              style: TextStyle(color: AppColors.accentBright),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppColors.accent.withValues(alpha: 0.4)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(11),
              ),
            ),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: _load,
            child: const Text(
              'Try again',
              style: TextStyle(color: AppColors.muted),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _headerCard(ResultData d) {
    final cgpaColor = _gpaColor(d.cgpa);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cgpaColor.withValues(alpha: 0.16), AppColors.card],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cgpaColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.name,
                      style: const TextStyle(
                        color: AppColors.textBright,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${d.id}${d.department.isNotEmpty ? '  ·  ${d.department}' : ''}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                      ),
                    ),
                    if (d.degree.isNotEmpty || d.imported) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (d.degree.isNotEmpty)
                            _chip(Icons.school_rounded, d.degree),
                          if (d.imported)
                            _chip(Icons.cloud_done_rounded, 'Imported'),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Column(
                children: [
                  Text(
                    d.cgpa.toStringAsFixed(2),
                    style: TextStyle(
                      color: cgpaColor,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
                  const Text(
                    'CGPA',
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _miniStat(
                d.totalCredit.toStringAsFixed(d.totalCredit % 1 == 0 ? 0 : 1),
                'Credits',
              ),
              _statDivider(),
              _miniStat('${d.coursesCompleted}', 'Courses'),
              _statDivider(),
              _miniStat('${d.semesters.length}', 'Semesters'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: AppColors.accent.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: AppColors.accentBright),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(color: AppColors.accentBright, fontSize: 10.5),
        ),
      ],
    ),
  );

  Widget _creditProgress(ResultData d) {
    const total = 160.0;
    final done = d.totalCredit.clamp(0, total);
    final pct = (done / total).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Degree Credit Progress',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '${done.toStringAsFixed(done % 1 == 0 ? 0 : 1)} / 160 cr',
                style: const TextStyle(
                  color: AppColors.accentBright,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 10,
              backgroundColor: AppColors.surface,
              valueColor: const AlwaysStoppedAnimation(AppColors.accent),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${(pct * 100).toStringAsFixed(0)}% complete',
            style: const TextStyle(color: AppColors.muted, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _targetCalc(ResultData d) {
    final req = d.requiredGpaFor(_target);
    String msg;
    Color color;
    if (req == null) {
      msg = 'You have completed the full degree credits.';
      color = const Color(0xFF34D399);
    } else if (req <= 0) {
      msg = 'Already achieved — keep it up!';
      color = const Color(0xFF34D399);
    } else if (req > 4.0) {
      msg = 'Not reachable within the remaining credits.';
      color = AppColors.red;
    } else {
      msg = 'Average GPA needed on the remaining credits';
      color = _gpaColor(req);
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Text(
                'Target CGPA',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              _stepBtn(
                Icons.remove,
                () =>
                    setState(() => _target = (_target - 0.05).clamp(2.0, 4.0)),
              ),
              SizedBox(
                width: 56,
                child: Text(
                  _target.toStringAsFixed(2),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textBright,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _stepBtn(
                Icons.add,
                () =>
                    setState(() => _target = (_target + 0.05).clamp(2.0, 4.0)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (req != null && req > 0 && req <= 4.0)
            Text(
              req.toStringAsFixed(2),
              style: TextStyle(
                color: color,
                fontSize: 30,
                fontWeight: FontWeight.w800,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            msg,
            textAlign: TextAlign.center,
            style: TextStyle(color: color, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap) => InkWell(
    borderRadius: BorderRadius.circular(8),
    onTap: onTap,
    child: Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 18, color: AppColors.accentBright),
    ),
  );

  Widget _retakeImprove(ResultData d) {
    final ri = d.retakeImprove();
    if (ri.fail.isEmpty && ri.improve.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF34D399).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFF34D399).withValues(alpha: 0.3),
          ),
        ),
        child: const Row(
          children: [
            Icon(
              Icons.check_circle_rounded,
              color: Color(0xFF34D399),
              size: 20,
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'No retake or improve courses — great work!',
                style: TextStyle(
                  color: AppColors.textBright,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        Row(
          children: [
            if (ri.fail.isNotEmpty)
              _riBadge('${ri.fail.length} Retake', AppColors.red),
            if (ri.fail.isNotEmpty && ri.improve.isNotEmpty)
              const SizedBox(width: 8),
            if (ri.improve.isNotEmpty)
              _riBadge('${ri.improve.length} Improve', const Color(0xFFFB923C)),
          ],
        ),
        const SizedBox(height: 10),
        ...ri.fail.map((c) => _riRow(c, AppColors.red, 'RETAKE')),
        ...ri.improve.map((c) => _riRow(c, const Color(0xFFFB923C), 'IMPROVE')),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => context.push('/info/retake'),
            icon: const Icon(
              Icons.open_in_new_rounded,
              size: 16,
              color: AppColors.accentBright,
            ),
            label: const Text(
              'Find sections in Retake & Improve',
              style: TextStyle(color: AppColors.accentBright, fontSize: 12.5),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppColors.accent.withValues(alpha: 0.4)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _riBadge(String label, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.13),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: c.withValues(alpha: 0.3)),
    ),
    child: Text(
      label,
      style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w700),
    ),
  );

  Widget _riRow(RetakeItem c, Color color, String tag) => Container(
    margin: const EdgeInsets.only(bottom: 7),
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(10),
      border: Border(
        left: BorderSide(color: color, width: 3),
        top: BorderSide(color: AppColors.border),
        right: BorderSide(color: AppColors.border),
        bottom: BorderSide(color: AppColors.border),
      ),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                c.title.isEmpty ? c.code : c.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                c.code,
                style: const TextStyle(color: AppColors.muted, fontSize: 10.5),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            c.grade,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _miniStat(String v, String label) => Expanded(
    child: Column(
      children: [
        Text(
          v,
          style: const TextStyle(
            color: AppColors.textBright,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: AppColors.muted, fontSize: 11),
        ),
      ],
    ),
  );

  Widget _statDivider() =>
      Container(width: 1, height: 28, color: AppColors.border);

  Widget _gradeChart(Map<String, int> dist) {
    final maxN = dist.values.fold(0, (a, b) => a > b ? a : b);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: dist.entries.map((e) {
          final c = _gradeColor(e.key);
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 30,
                  child: Text(
                    e.key,
                    style: TextStyle(
                      color: c,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      Container(
                        height: 16,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: maxN == 0 ? 0 : e.value / maxN,
                        child: Container(
                          height: 16,
                          decoration: BoxDecoration(
                            color: c.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 28,
                  child: Text(
                    '${e.value}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _gpaTrend(List<ResultSemester> sems) {
    final ordered = sems.reversed.toList();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: ordered.map((s) {
          final c = _gpaColor(s.gpa);
          return Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Row(
              children: [
                SizedBox(
                  width: 92,
                  child: Text(
                    _shortSem(s),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11.5,
                    ),
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      Container(
                        height: 14,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: (s.gpa / 4).clamp(0, 1),
                        child: Container(
                          height: 14,
                          decoration: BoxDecoration(
                            color: c.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 34,
                  child: Text(
                    s.gpa.toStringAsFixed(2),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: c,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _semesterCard(ResultData d, int i, ResultSemester s) {
    final c = _gpaColor(s.gpa);
    final isBest = i == d.bestSemesterIndex;
    final isWorst = i == d.worstSemesterIndex;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Theme(
        data: ThemeData.dark().copyWith(
          dividerColor: Colors.transparent,
          colorScheme: const ColorScheme.dark(primary: AppColors.accent),
        ),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 14),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            iconColor: AppColors.accentBright,
            collapsedIconColor: AppColors.muted,
            title: Row(
              children: [
                Flexible(
                  child: Text(
                    s.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textBright,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (isBest) _semBadge('🏆 Best', const Color(0xFF34D399)),
                if (isWorst) _semBadge('↓ Lowest', const Color(0xFFFB923C)),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                '${s.courses.length} course${s.courses.length == 1 ? '' : 's'} · ${s.credit.toStringAsFixed(s.credit % 1 == 0 ? 0 : 1)} cr',
                style: const TextStyle(color: AppColors.muted, fontSize: 11.5),
              ),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  s.gpa.toStringAsFixed(2),
                  style: TextStyle(
                    color: c,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const Text(
                  'GPA',
                  style: TextStyle(color: AppColors.muted, fontSize: 9.5),
                ),
              ],
            ),
            children: s.courses.map(_courseRow).toList(),
          ),
        ),
      ),
    );
  }

  Widget _semBadge(String label, Color c) => Padding(
    padding: const EdgeInsets.only(left: 6),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(color: c, fontSize: 9.5, fontWeight: FontWeight.w700),
      ),
    ),
  );

  Widget _courseRow(ResultCourse c) {
    final gc = _gradeColor(c.grade);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.code.isEmpty ? c.title : c.code,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (c.title.isNotEmpty && c.code.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      c.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                        height: 1.3,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (c.credit > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                '${c.credit.toStringAsFixed(c.credit % 1 == 0 ? 0 : 1)} cr',
                style: const TextStyle(color: AppColors.muted, fontSize: 11),
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: gc.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: gc.withValues(alpha: 0.35)),
            ),
            child: Text(
              c.grade.isEmpty ? '—' : c.grade,
              style: TextStyle(
                color: gc,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String s) => Text(
    s.toUpperCase(),
    style: const TextStyle(
      color: AppColors.accentBright,
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.6,
    ),
  );

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _shortSem(ResultSemester s) {
    final n = s.name.trim();
    return n.contains(s.year) ? n : '$n ${s.year}';
  }

  static Color _gpaColor(double g) {
    if (g >= 3.5) return const Color(0xFF34D399);
    if (g >= 3.0) return const Color(0xFF38BDF8);
    if (g >= 2.5) return const Color(0xFFFBBF24);
    if (g > 0) return const Color(0xFFF87171);
    return AppColors.muted;
  }

  static Color _gradeColor(String grade) {
    final g = grade.toUpperCase();
    if (g.startsWith('A')) return const Color(0xFF34D399);
    if (g.startsWith('B')) return const Color(0xFF38BDF8);
    if (g == 'C+' || g == 'C') return const Color(0xFFFBBF24);
    if (g == 'D') return const Color(0xFFFB923C);
    if (g == 'F') return const Color(0xFFF87171);
    return AppColors.muted;
  }
}

/// Bottom sheet to paste a copied LU result and import it (self-only). Parsed
/// client-side, then stored via the Worker's /result-import. Mirrors the
/// website's manual-import flow.
class _ImportSheet extends StatefulWidget {
  final String studentId;
  final String dob;
  final VoidCallback onImported;
  const _ImportSheet({
    required this.studentId,
    required this.dob,
    required this.onImported,
  });

  @override
  State<_ImportSheet> createState() => _ImportSheetState();
}

class _TutorialVideo {
  final String title;
  final String url;
  final String youtubeId;
  const _TutorialVideo(this.title, this.url, this.youtubeId);
}

class _ImportSheetState extends State<_ImportSheet> {
  final _ctrl = TextEditingController();
  late final Future<_TutorialVideo?> _tutorial = _loadTutorial();
  bool _busy = false;
  String? _error;

  Future<_TutorialVideo?> _loadTutorial() async {
    try {
      final rows = await SheetsApi.instance.sheet('Tutorial Video');
      _TutorialVideo? fallback;
      for (final row in rows) {
        if (row.length < 2) continue;
        final title = row[0].trim();
        final url = row[1].trim();
        if (title.toLowerCase() == 'title' || url.isEmpty) continue;
        final match = RegExp(
          r'(?:youtu\.be/|[?&]v=|embed/|shorts/)([A-Za-z0-9_-]{6,})',
          caseSensitive: false,
        ).firstMatch(url);
        if (match == null) continue;
        final video = _TutorialVideo(title, url, match.group(1)!);
        fallback ??= video;
        if (title.toLowerCase().contains('mobile')) return video;
      }
      return fallback;
    } catch (_) {
      return null;
    }
  }

  Widget _tutorialCard() {
    return FutureBuilder<_TutorialVideo?>(
      future: _tutorial,
      builder: (context, snap) {
        final video = snap.data;
        if (video == null) return const SizedBox.shrink();
        return InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: () => launchUrl(
            Uri.parse(video.url),
            mode: LaunchMode.externalApplication,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: AppColors.borderAccent),
            ),
            clipBehavior: Clip.antiAlias,
            child: Row(
              children: [
                SizedBox(
                  width: 126,
                  height: 82,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CachedNetworkImage(
                        imageUrl:
                            'https://i.ytimg.com/vi/${video.youtubeId}/hqdefault.jpg',
                        fit: BoxFit.cover,
                        placeholder: (_, _) => const ColoredBox(
                          color: AppColors.surface,
                          child: Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.accent,
                            ),
                          ),
                        ),
                      ),
                      const Center(
                        child: CircleAvatar(
                          radius: 18,
                          backgroundColor: Color(0xFFE11D48),
                          child: Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 25,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'MOBILE TUTORIAL',
                          style: TextStyle(
                            color: AppColors.accentBright,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          video.title,
                          style: const TextStyle(
                            color: AppColors.textBright,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final raw = _ctrl.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = 'Paste the copied result first.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = importParse(raw);
      if (data['success'] != true) {
        setState(() {
          _busy = false;
          _error =
              "Couldn't read a result from that. Make sure you copied the whole result page (after it loaded on LU).";
        });
        return;
      }
      final parsedId = ((data['student'] as Map?)?['id'] ?? '').toString();
      if (parsedId != widget.studentId) {
        setState(() {
          _busy = false;
          _error = 'That result is for ID $parsedId, not your account.';
        });
        return;
      }
      final ok = await WorkerApi.instance.resultImport(
        widget.studentId,
        widget.dob,
        data,
      );
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _busy = false;
          _error = 'Import failed. Please try again in a moment.';
        });
        return;
      }
      Navigator.of(context).pop();
      widget.onImported();
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not import. Check what you pasted and try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          border: Border(top: BorderSide(color: AppColors.borderAccent)),
        ),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9 - bottom,
        ),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.muted,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Import your result',
                style: TextStyle(
                  color: AppColors.textBright,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              _tutorialCard(),
              const SizedBox(height: 6),
              const Text(
                '1. Open the LU result page and view your result.\n2. Tap & hold the text → Select All → Copy.\n3. Paste it below and import.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12.5,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _ctrl,
                maxLines: 6,
                style: const TextStyle(color: AppColors.text, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Paste your copied result here…',
                  hintStyle: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 13,
                  ),
                  filled: true,
                  fillColor: AppColors.card,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.accent),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: const TextStyle(color: AppColors.red, fontSize: 12.5),
                ),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _busy ? null : _import,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.cloud_upload_rounded, size: 18),
                  label: Text(_busy ? 'Importing…' : 'Import my result'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
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
