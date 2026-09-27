import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_colors.dart';
import '../../data/retake_repository.dart';
import '../../data/session.dart';
import '../../shared/app_toast.dart';
import '../../shared/suggest_field.dart';

/// Retake & Improve — detects the student's retake (F) and improve (C/D/B-/C+)
/// courses from their results, then shows which sections in the routine they
/// can take without clashing with the 62B schedule. Courses can also be added
/// manually. Mirrors the website's Retake & Improve tab.
class RetakeScreen extends StatefulWidget {
  const RetakeScreen({super.key});

  @override
  State<RetakeScreen> createState() => _RetakeScreenState();
}

class _RetakeScreenState extends State<RetakeScreen> {
  bool _loading = true;
  RetakeData? _data;
  bool _retakeTab = true;
  final _search = TextEditingController();
  String? _searchCode;

  // Top view: 'find' | 'mylist' | 'classmates'.
  String _view = 'find';
  List<RetakeEnrollment> _myEnroll = [];
  List<RetakeEnrollment> _allEnroll = [];
  bool _enrollBusy = false;

  static Color get _retakeColor => AppColors.red;
  static Color get _improveColor => AppColors.orangeBright;
  static Color get _green => AppColors.greenBright;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool refresh = false}) async {
    setState(() => _loading = true);
    if (refresh) RetakeRepository.instance.invalidateCache();
    final s = Session.instance.student;
    String? dob;
    if (s != null && !s.isDemo) {
      dob = await Session.instance.storedDob(s.id);
    }
    final data = await RetakeRepository.instance.load(s?.id, dob);
    if (mounted) {
      setState(() {
        _data = data;
        _loading = false;
      });
    }
    _loadEnrollments();
  }

  Future<void> _loadEnrollments() async {
    final s = Session.instance.student;
    if (s == null || s.isDemo) return;
    final res = await Future.wait([
      RetakeRepository.instance.myEnrollments(s.id),
      RetakeRepository.instance.allEnrollments(),
    ]);
    if (mounted) {
      setState(() {
        _myEnroll = res[0];
        _allEnroll = res[1];
      });
    }
  }

  RetakeEnrollment? _enrolledIn(String code) {
    final norm = RetakeRepository.norm(code);
    for (final e in _myEnroll) {
      if (RetakeRepository.norm(e.courseCode) == norm) return e;
    }
    return null;
  }

  Future<void> _toggleEnroll(String code, String courseName, RetakeSection sec, bool retake) async {
    final s = Session.instance.student;
    if (s == null || s.isDemo) {
      AppToast.show(context, 'Log in as a student to enroll.', error: true);
      return;
    }
    setState(() => _enrollBusy = true);
    final existing = _enrolledIn(code);
    final isThis = existing != null && existing.batch == sec.batch && existing.section == sec.section;
    bool ok;
    if (isThis) {
      ok = await RetakeRepository.instance.unenroll(s.id, RetakeRepository.norm(code));
    } else {
      ok = await RetakeRepository.instance.enroll(
        studentId: s.id,
        studentName: s.name,
        courseCode: RetakeRepository.norm(code),
        courseName: courseName,
        batch: sec.batch,
        section: sec.section,
        teacher: sec.initials,
        type: retake ? 'retake' : 'improve',
      );
    }
    if (ok) await _loadEnrollments();
    if (mounted) {
      setState(() => _enrollBusy = false);
      if (ok) AppToast.show(context, isThis ? 'Removed from My List' : 'Added to My List');
    }
  }

  Future<void> _unenroll(String code) async {
    final s = Session.instance.student;
    if (s == null) return;
    final ok = await RetakeRepository.instance.unenroll(s.id, RetakeRepository.norm(code));
    if (ok) await _loadEnrollments();
  }

  void _mutateManual(String code, {required bool add, required bool retake}) {
    final d = _data;
    final s = Session.instance.student;
    if (d == null || s == null) return;
    final c = RetakeRepository.norm(code);
    d.manualRetake.remove(c);
    d.manualImprove.remove(c);
    if (add) {
      (retake ? d.manualRetake : d.manualImprove).add(c);
    }
    RetakeRepository.instance.saveManual(s.id, d.manualRetake, d.manualImprove);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Retake & Improve'),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.canPop() ? context.pop() : context.go('/info')),
        actions: [
          if (!_loading)
            IconButton(icon: const Icon(Icons.refresh_rounded, size: 22), onPressed: () => _load(refresh: true)),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppColors.accent))
          : Column(
              children: [
                _topTabs(),
                Expanded(child: _viewBody()),
              ],
            ),
    );
  }

  Widget _viewBody() {
    switch (_view) {
      case 'mylist':
        return _myListView();
      case 'classmates':
        return _classmatesView();
      default:
        return _content(_data!);
    }
  }

  Widget _topTabs() {
    Widget t(String id, String label, IconData icon, int? count) {
      final active = _view == id;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _view = id),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                    color: active ? AppColors.accent : Colors.transparent, width: 2.5),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 15, color: active ? AppColors.accentBright : AppColors.muted),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: active ? AppColors.accentBright : AppColors.textSecondary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700)),
                ),
                if (count != null && count > 0) ...[
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('$count',
                        style: TextStyle(
                            color: AppColors.accentBright, fontSize: 10, fontWeight: FontWeight.w800)),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          t('find', 'Find', Icons.search_rounded, null),
          t('mylist', 'My List', Icons.bookmark_rounded, _myEnroll.length),
          t('classmates', 'Classmates', Icons.groups_rounded, _allEnroll.length),
        ],
      ),
    );
  }

  Widget _content(RetakeData d) {
    final list = _retakeTab ? d.retakeList : d.improveList;
    return RefreshIndicator(
      color: AppColors.accent,
      backgroundColor: AppColors.card,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        children: [
          _tabs(d),
          const SizedBox(height: 12),
          _searchBar(),
          if (_searchCode != null) ...[
            const SizedBox(height: 12),
            _searchResult(d, _searchCode!),
          ],
          const SizedBox(height: 14),
          if (!d.resultLive)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _note(
                  'Your results could not be loaded automatically (LU verification). Auto-detected courses may be missing — you can still add courses manually with the search above.'),
            ),
          if (list.isEmpty)
            _emptyState()
          else
            ...list.map((code) => _courseCard(d, code, _retakeTab)),
        ],
      ),
    );
  }

  Widget _tabs(RetakeData d) {
    Widget tab(String label, IconData icon, bool retake, int count) {
      final sel = _retakeTab == retake;
      final color = retake ? _retakeColor : _improveColor;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _retakeTab = retake),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 11),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: sel ? color.withValues(alpha: 0.16) : AppColors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: sel ? color.withValues(alpha: 0.5) : AppColors.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: sel ? color : AppColors.textSecondary),
                const SizedBox(width: 7),
                Text(label,
                    style: TextStyle(
                        color: sel ? color : AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                  decoration: BoxDecoration(
                    color: (sel ? color : AppColors.muted).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('$count',
                      style: TextStyle(
                          color: sel ? color : AppColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(children: [
      tab('Retake', Icons.rotate_right_rounded, true, d.retakeList.length),
      tab('Improve', Icons.trending_up_rounded, false, d.improveList.length),
    ]);
  }

  List<Suggestion> _courseSuggestions() {
    final d = _data;
    if (d == null) return const [];
    return d.courseNameMap.entries
        .map((e) => Suggestion(e.key, secondary: e.value, data: e.key))
        .toList();
  }

  Widget _searchBar() => SuggestField(
        controller: _search,
        label: 'Add a course (code or name)',
        hint: 'e.g. CSE-3201 or Operating System',
        suggestions: _courseSuggestions,
        onPicked: (s) => setState(() => _searchCode = (s.data as String?) ?? s.text),
        onChanged: (v) {
          // Let Enter / a full code still resolve even without picking.
          if (v.trim().isEmpty) setState(() => _searchCode = null);
        },
      );

  Widget _searchResult(RetakeData d, String code) {
    final title = d.courseNameMap[code] ?? '';
    final inRetake = d.isApi(code, true) || d.isManual(code, true);
    final inImprove = d.isApi(code, false) || d.isManual(code, false);

    Widget addBtn(bool retake) {
      final isApi = d.isApi(code, retake);
      final isManual = d.isManual(code, retake);
      final color = retake ? _retakeColor : _improveColor;
      final label = retake ? 'Retake' : 'Improve';
      if (isApi) {
        return _pill('In $label (from results)', color, Icons.check_circle, filled: true);
      }
      if (isManual) {
        return GestureDetector(
          onTap: () => _mutateManual(code, add: false, retake: retake),
          child: _pill('Saved · Remove', color, Icons.bookmark, filled: true),
        );
      }
      return GestureDetector(
        onTap: () => _mutateManual(code, add: true, retake: retake),
        child: _pill('Add to $label', color, Icons.add, filled: false),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _codeTitle(code, title)),
              IconButton(
                icon: Icon(Icons.close, size: 18, color: AppColors.muted),
                onPressed: () => setState(() => _searchCode = null),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(spacing: 8, runSpacing: 8, children: [addBtn(true), addBtn(false)]),
          const SizedBox(height: 6),
          _sectionsBlock(d, code, inRetake || !inImprove),
        ],
      ),
    );
  }

  Widget _courseCard(RetakeData d, String code, bool retake) {
    final title = d.courseNameMap[code] ?? '';
    final isManual = d.isManual(code, retake);
    final color = retake ? _retakeColor : _improveColor;
    final credit = d.creditMap[code];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border(top: BorderSide(color: color, width: 3)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: _codeTitle(code, title)),
                  if (credit != null && credit > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text('${credit.toStringAsFixed(credit % 1 == 0 ? 0 : 1)} cr',
                          style: TextStyle(color: AppColors.muted, fontSize: 11.5)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _pill(retake ? 'RETAKE' : 'IMPROVE', color, null, filled: true, small: true),
                  if (isManual) ...[
                    const SizedBox(width: 6),
                    _pill('Manual', AppColors.indigoBright, Icons.edit, filled: true, small: true),
                  ],
                  const Spacer(),
                  if (isManual)
                    GestureDetector(
                      onTap: () => _mutateManual(code, add: false, retake: retake),
                      child: Text('× Remove',
                          style: TextStyle(color: AppColors.muted, fontSize: 11.5)),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              _sectionsBlock(d, code, retake),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionsBlock(RetakeData d, String code, bool retake) {
    final sections = d.sectionsFor(code);
    if (sections.isEmpty) {
      return Row(
        children: [
          Icon(Icons.info_outline, size: 14, color: AppColors.muted),
          SizedBox(width: 6),
          Expanded(
            child: Text('Not found in the current routine — may not be offered this semester.',
                style: TextStyle(color: AppColors.muted, fontSize: 12, fontStyle: FontStyle.italic)),
          ),
        ],
      );
    }
    final free = sections.where((s) => !s.hasConflict).length;
    final clash = sections.length - free;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('${sections.length} section${sections.length == 1 ? '' : 's'}',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
            const SizedBox(width: 8),
            if (free > 0) _miniBadge('$free Free', _green),
            if (clash > 0) ...[
              const SizedBox(width: 6),
              _miniBadge('$clash Clash', _retakeColor),
            ],
          ],
        ),
        const SizedBox(height: 8),
        ...sections.map((s) => _sectionRow(s, code, d.courseNameMap[code] ?? '', retake, d.offDays)),
      ],
    );
  }

  Widget _sectionRow(RetakeSection s, String code, String courseName, bool retake,
      Set<String> offDays) {
    final color = s.hasConflict ? _retakeColor : _green;
    final enrolled = _enrolledIn(code);
    final isThis = enrolled != null && enrolled.batch == s.batch && enrolled.section == s.section;
    // Section sits entirely on the student's off days → ideal pick.
    final allOff = s.slots.isNotEmpty && s.slots.every((sl) => offDays.contains(sl.day));
    final offColor = AppColors.tealBright;
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Batch ${s.batch} · Sec ${s.section}',
                  style: TextStyle(
                      color: AppColors.textBright, fontWeight: FontWeight.w700, fontSize: 12.5)),
              if (s.initials.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(s.initials, style: TextStyle(color: AppColors.muted, fontSize: 11)),
              ],
              const Spacer(),
              if (allOff) ...[
                _miniBadge('Off Day', offColor),
                const SizedBox(width: 6),
              ],
              _miniBadge(s.hasConflict ? 'Clash' : 'Free', color),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: s.slots.map((slot) {
              final off = offDays.contains(slot.day);
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: off ? offColor.withValues(alpha: 0.12) : AppColors.surface,
                  borderRadius: BorderRadius.circular(6),
                  border: off ? Border.all(color: offColor.withValues(alpha: 0.35)) : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${_day3(slot.day)} ${slot.time}',
                        style: TextStyle(
                            color: off ? offColor : AppColors.textSecondary, fontSize: 10.5)),
                    if (off) ...[
                      const SizedBox(width: 4),
                      Text('· Off',
                          style: TextStyle(
                              color: offColor, fontSize: 9, fontWeight: FontWeight.w800)),
                    ],
                  ],
                ),
              );
            }).toList(),
          ),
          if (s.hasConflict && s.clashCourses.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Clashes with: ${s.clashCourses.join(', ')}',
                style: TextStyle(color: _retakeColor, fontSize: 10.5)),
          ],
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _enrollBusy ? null : () => _toggleEnroll(code, courseName, s, retake),
            child: Container(
              width: double.infinity,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: isThis ? _green.withValues(alpha: 0.16) : AppColors.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: isThis ? _green.withValues(alpha: 0.4) : AppColors.accent.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(isThis ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
                      size: 15, color: isThis ? _green : AppColors.accentBright),
                  const SizedBox(width: 6),
                  Text(isThis ? 'Enrolled — tap to remove' : 'Enroll in this section',
                      style: TextStyle(
                          color: isThis ? _green : AppColors.accentBright,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _codeTitle(String code, String title) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(code,
              style: TextStyle(
                  color: AppColors.accentBright,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  fontFamily: 'monospace')),
          if (title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(title,
                  style: TextStyle(
                      color: AppColors.text, fontSize: 13.5, fontWeight: FontWeight.w600)),
            ),
        ],
      );

  Widget _pill(String label, Color color, IconData? icon,
      {required bool filled, bool small = false}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 8 : 11, vertical: small ? 3 : 7),
      decoration: BoxDecoration(
        color: filled ? color.withValues(alpha: 0.15) : AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: filled ? color.withValues(alpha: 0.35) : AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: small ? 11 : 14, color: filled ? color : AppColors.textSecondary),
            const SizedBox(width: 5),
          ],
          Text(label,
              style: TextStyle(
                  color: filled ? color : AppColors.textSecondary,
                  fontSize: small ? 10.5 : 12.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: small ? 0.4 : 0)),
        ],
      ),
    );
  }

  Widget _miniBadge(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Text(label,
            style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w700)),
      );

  Widget _note(String text) => Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: _improveColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: _improveColor.withValues(alpha: 0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: _improveColor, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.45)),
            ),
          ],
        ),
      );

  Widget _emptyState() {
    final retake = _retakeTab;
    return Padding(
      padding: const EdgeInsets.only(top: 50),
      child: Center(
        child: Column(
          children: [
            Icon(retake ? Icons.check_circle_rounded : Icons.star_rounded,
                size: 44, color: (retake ? _green : AppColors.amberBright).withValues(alpha: 0.5)),
            const SizedBox(height: 14),
            Text(retake ? 'No retake courses — great job!' : 'No improve courses found.',
                style: TextStyle(
                    color: AppColors.textBright, fontWeight: FontWeight.w700, fontSize: 14.5)),
            const SizedBox(height: 6),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                'Add a course with the search above, or check that your date of birth is set so results can load.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── My List view ──
  Widget _myListView() {
    final s = Session.instance.student;
    if (s == null || s.isDemo) {
      return _centerNote('Log in as a student to track your retake/improve enrollments.');
    }
    if (_myEnroll.isEmpty) {
      return _centerNote(
          'You haven’t enrolled in any sections yet.\nGo to Find, open a course, and tap Enroll on a section.');
    }
    return RefreshIndicator(
      color: AppColors.accent,
      backgroundColor: AppColors.card,
      onRefresh: _loadEnrollments,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
        children: _myEnroll.map((e) {
          final color = e.type == 'improve' ? _improveColor : _retakeColor;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(13),
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
                      Row(
                        children: [
                          Text(e.courseCode,
                              style: TextStyle(
                                  color: AppColors.accentBright,
                                  fontWeight: FontWeight.w800,
                                  fontFamily: 'monospace',
                                  fontSize: 13)),
                          const SizedBox(width: 8),
                          _pill(e.type == 'improve' ? 'IMPROVE' : 'RETAKE', color, null,
                              filled: true, small: true),
                        ],
                      ),
                      if (e.courseName.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(e.courseName,
                            style: TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                      const SizedBox(height: 5),
                      Text(
                          'Batch ${e.batch} · Sec ${e.section}${e.teacher.isNotEmpty ? ' · ${e.teacher}' : ''}',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline_rounded, color: AppColors.muted, size: 20),
                  tooltip: 'Remove',
                  onPressed: () => _unenroll(e.courseCode),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Classmates view ──
  Widget _classmatesView() {
    if (_allEnroll.isEmpty) {
      return _centerNote('No one in 62B has enrolled in any retake/improve sections yet.');
    }
    // Group by course code.
    final byCourse = <String, List<RetakeEnrollment>>{};
    for (final e in _allEnroll) {
      byCourse.putIfAbsent(e.courseCode, () => []).add(e);
    }
    final codes = byCourse.keys.toList()..sort();
    final myId = Session.instance.student?.id;
    return RefreshIndicator(
      color: AppColors.accent,
      backgroundColor: AppColors.card,
      onRefresh: _loadEnrollments,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
        children: codes.map((code) {
          final people = byCourse[code]!;
          final name = people.firstWhere((p) => p.courseName.isNotEmpty,
              orElse: () => people.first).courseName;
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
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
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(5)),
                      child: Text(code,
                          style: TextStyle(
                              color: AppColors.accentBright, fontWeight: FontWeight.w800, fontSize: 12)),
                    ),
                    const Spacer(),
                    _miniBadge('${people.length}', AppColors.accentBright),
                  ],
                ),
                if (name.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(name,
                      style: TextStyle(
                          color: AppColors.textBright, fontSize: 14, fontWeight: FontWeight.w700, height: 1.3)),
                ],
                const SizedBox(height: 10),
                ...people.map((p) {
                  final isMe = myId != null && p.studentId == myId;
                  final color = p.type == 'improve' ? _improveColor : _retakeColor;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Icon(Icons.person_rounded, size: 14, color: isMe ? AppColors.accentBright : AppColors.muted),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(isMe ? '${p.studentName.isEmpty ? 'You' : p.studentName} (You)' : (p.studentName.isEmpty ? 'Student' : p.studentName),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: isMe ? AppColors.accentBright : AppColors.text,
                                  fontSize: 12.5,
                                  fontWeight: isMe ? FontWeight.w700 : FontWeight.w500)),
                        ),
                        Text('${p.batch}${p.section}',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                        const SizedBox(width: 8),
                        _pill(p.type == 'improve' ? 'IMP' : 'RET', color, null, filled: true, small: true),
                      ],
                    ),
                  );
                }),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _centerNote(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(34),
          child: Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 13.5, height: 1.6)),
        ),
      );

  static String _day3(String day) =>
      day.length <= 3 ? day : day.substring(0, 3).toUpperCase();
}
