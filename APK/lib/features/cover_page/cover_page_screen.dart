import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_colors.dart';
import '../../data/session.dart';
import '../../shared/app_toast.dart';
import '../../shared/gradient_button.dart';
import '../../shared/suggest_field.dart';
import 'cover_data.dart';
import 'cover_pdf.dart';
import 'cover_suggestions.dart';

class CoverPageScreen extends StatefulWidget {
  const CoverPageScreen({super.key});

  @override
  State<CoverPageScreen> createState() => _CoverPageScreenState();
}

class _CoverPageScreenState extends State<CoverPageScreen> {
  String _template = 't1';
  String _docType = 'Assignment';
  bool _group = false;
  bool _busy = false;

  final _sugg = CoverSuggestions();
  List<Suggestion> _topicSuggestions = [];
  Timer? _topicDebounce;

  /// Shows the "your CR already made this" banner when the CR bulk-generated
  /// this student's cover page (recorded from the website's Class Mode).
  bool _crMadeIt = false;
  Timer? _crDebounce;

  final _courseTitle = TextEditingController();
  final _courseCode = TextEditingController();
  final _no = TextEditingController();
  final _topic = TextEditingController();
  final _teacher = TextEditingController();
  final _desig = TextEditingController();
  final _dept = TextEditingController(text: 'Department of Computer Science & Engineering');
  final _name = TextEditingController();
  final _sid = TextEditingController();
  final _date = TextEditingController();
  String _batch = '62nd';
  String _section = 'B';
  final List<({TextEditingController name, TextEditingController id})> _members = [];

  @override
  void initState() {
    super.initState();
    final s = Session.instance.student;
    if (s != null && !s.isDemo) {
      _name.text = s.name;
      _sid.text = s.id;
    }
    _date.text = _formatDateNice(DateTime.now());
    // First group member defaults to the logged-in user (like the site).
    _addMember(name: _name.text, id: _sid.text);
    _courseCode.addListener(_scheduleTopicRefresh);
    _no.addListener(_scheduleTopicRefresh);
    _courseCode.addListener(_scheduleCrCheck);
    _no.addListener(_scheduleCrCheck);
    _sugg.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _topicDebounce?.cancel();
    _crDebounce?.cancel();
    for (final c in [
      _courseTitle, _courseCode, _no, _topic, _teacher, _desig, _dept,
      _name, _sid, _date,
    ]) {
      c.dispose();
    }
    for (final m in _members) {
      m.name.dispose();
      m.id.dispose();
    }
    super.dispose();
  }

  String get _docTypeKey => _docType == 'Lab Report' ? 'lab' : 'assignment';

  void _scheduleTopicRefresh() {
    _topicDebounce?.cancel();
    _topicDebounce = Timer(const Duration(milliseconds: 350), _refreshTopics);
  }

  Future<void> _refreshTopics() async {
    final list = await _sugg.topicsFor(
        _courseCode.text.trim(), _docTypeKey, _no.text.trim());
    if (mounted) setState(() => _topicSuggestions = list);
  }

  // ── "CR already made this" notice ──
  // Keys are normalised exactly like the website before the lookup so "06"/"6",
  // spacing and case never cause a miss.
  static String _normCode(String s) =>
      s.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
  static String _normNo(String s) {
    s = s.trim();
    return RegExp(r'^\d+$').hasMatch(s)
        ? int.parse(s).toString()
        : s.toLowerCase();
  }

  void _scheduleCrCheck() {
    _crDebounce?.cancel();
    _crDebounce = Timer(const Duration(milliseconds: 350), _runCrCheck);
  }

  Future<void> _runCrCheck() async {
    final s = Session.instance.student;
    final code = _normCode(_courseCode.text);
    final no = _normNo(_no.text);
    if (s == null || s.isDemo || code.isEmpty || no.isEmpty) {
      if (_crMadeIt && mounted) setState(() => _crMadeIt = false);
      return;
    }
    final made = await _sugg.crAlreadyMade(code, _docTypeKey, no, s.id);
    if (mounted && made != _crMadeIt) setState(() => _crMadeIt = made);
  }

  Future<void> _messageCr() async {
    final uri = Uri.parse('https://wa.link/jwgbp2');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) AppToast.show(context, 'Could not open WhatsApp', error: true);
    }
  }

  /// Ordinal date like the site: "24th June 2026".
  static String _formatDateNice(DateTime d) {
    final day = d.day;
    final m10 = day % 10, m100 = day % 100;
    final suf = (m100 >= 11 && m100 <= 13)
        ? 'th'
        : m10 == 1
            ? 'st'
            : m10 == 2
                ? 'nd'
                : m10 == 3
                    ? 'rd'
                    : 'th';
    const mo = [
      'January','February','March','April','May','June',
      'July','August','September','October','November','December'
    ];
    return '$day$suf ${mo[d.month - 1]} ${d.year}';
  }

  void _addMember({String name = '', String id = ''}) => setState(() => _members.add((
        name: TextEditingController(text: name),
        id: TextEditingController(text: id),
      )));

  CoverData _collect() => CoverData(
        template: _template,
        docType: _docType,
        isGroup: _group,
        courseTitle: _courseTitle.text.trim(),
        courseCode: _courseCode.text.trim(),
        no: _no.text.trim(),
        topic: _topic.text.trim(),
        teacherName: _teacher.text.trim(),
        designation: _desig.text.trim(),
        department: _dept.text.trim(),
        studentName: _name.text.trim(),
        studentId: _sid.text.trim(),
        batch: _batch,
        section: _section,
        date: _date.text.trim(),
        members: _members
            .map((m) => (name: m.name.text.trim(), id: m.id.text.trim()))
            .toList(),
      );

  String _fileName() {
    final code = _courseCode.text.trim().replaceAll(RegExp(r'[^A-Za-z0-9\-]'), '');
    final base = code.isEmpty ? 'CoverPage' : code;
    return '${_docType.replaceAll(' ', '_')}_$base.pdf';
  }

  /// Generates the PDF and opens the share/save sheet (Save to Files, WhatsApp,
  /// Drive, …). Printing lives on the website only.
  Future<void> _export() async {
    if (_courseTitle.text.trim().isEmpty) {
      AppToast.show(context, 'Please enter the course title', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final bytes = await CoverPdf.build(_collect());
      if (!mounted) return;
      await Printing.sharePdf(bytes: bytes, filename: _fileName());
      // Remember the topic for next time (logged-in students only).
      final s = Session.instance.student;
      if (s != null && !s.isDemo) {
        _sugg.saveTopic(_courseCode.text.trim(), _docTypeKey, _no.text.trim(),
            _topic.text.trim(), s.id);
      }
    } catch (e) {
      if (mounted) AppToast.show(context, 'Could not generate PDF', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Pick the submission date from a calendar; fills the field in the same
  /// ordinal format ("24th June 2026"). The field stays manually editable.
  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.accent,
            surface: AppColors.card,
            onSurface: AppColors.text,
          ),
          dialogTheme: const DialogThemeData(backgroundColor: AppColors.bg),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _date.text = _formatDateNice(picked));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Cover Page'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          if (_crMadeIt) _crNotice(),
          _templatePicker(),
          const SizedBox(height: 14),
          _docTypeSelector(),
          const SizedBox(height: 14),
          _sectionLabel('Document'),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SuggestField(
              controller: _courseTitle,
              label: 'Course Title',
              hint: 'e.g. Computer Network Sessional',
              suggestions: () => _sugg.courses,
              onPicked: (s) {
                final c = s.data;
                if (c is CourseInfo) {
                  if (c.code.isNotEmpty) _courseCode.text = c.code;
                  if (c.teacher.isNotEmpty) _teacher.text = c.teacher;
                  if (c.designation.isNotEmpty) _desig.text = c.designation;
                  if (c.department.isNotEmpty) _dept.text = c.department;
                  setState(() {});
                }
              },
            ),
          ),
          _field(_courseCode, 'Course Code', hint: 'e.g. CSE-3232'),
          _field(_no, _docType == 'Lab Report' ? 'Lab Report No' : 'Assignment No',
              hint: 'e.g. 06'),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SuggestField(
              controller: _topic,
              label: 'Topic',
              hint: 'e.g. Dynamic Routing',
              showAllOnFocus: true,
              suggestions: () => _topicSuggestions,
            ),
          ),
          _sectionLabel('Submitted To'),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SuggestField(
              controller: _teacher,
              label: 'Teacher Name',
              suggestions: () => _sugg.teachers,
              onPicked: (s) {
                final t = s.data;
                if (t is TeacherInfo) {
                  if (t.designation.isNotEmpty) _desig.text = t.designation;
                  if (t.department.isNotEmpty) _dept.text = t.department;
                  setState(() {});
                }
              },
            ),
          ),
          _field(_desig, 'Designation', hint: 'e.g. Lecturer'),
          _field(_dept, 'Department'),
          _sectionLabel('Submitted From'),
          if (!_group) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SuggestField(
                controller: _name,
                label: 'Your Name',
                suggestions: () => _sugg.students,
                onPicked: (s) {
                  final id = s.data;
                  if (id is String && id.isNotEmpty) _sid.text = id;
                  setState(() {});
                },
              ),
            ),
            _field(_sid, 'Student ID'),
          ],
          Row(
            children: [
              Expanded(child: _dropdown('Batch', _batch, _batches, (v) => setState(() => _batch = v!))),
              const SizedBox(width: 10),
              Expanded(child: _dropdown('Section', _section, _sections, (v) => setState(() => _section = v!))),
            ],
          ),
          if (_group) ...[
            const SizedBox(height: 14),
            _sectionLabel('Group Members'),
            ..._members.asMap().entries.map((e) => _memberRow(e.key, e.value)),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: _addMember,
              icon: const Icon(Icons.add, size: 18, color: AppColors.accentBright),
              label: const Text('Add Member',
                  style: TextStyle(color: AppColors.accentBright)),
            ),
          ],
          _sectionLabel('Submission'),
          _dateField(),
          const SizedBox(height: 18),
          GradientButton(
            label: 'Download PDF',
            icon: Icons.file_download_rounded,
            busy: _busy,
            onPressed: _export,
          ),
          const SizedBox(height: 8),
          const Center(
            child: Text('Generates the cover page and opens save / share',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, fontSize: 11.5)),
          ),
        ],
      ),
    );
  }

  Widget _templatePicker() {
    Widget tpl(String id, String name, String desc, IconData icon) {
      final sel = _template == id;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _template = id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              gradient: sel ? AppColors.accentGradient : null,
              color: sel ? null : AppColors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: sel ? Colors.transparent : AppColors.border),
            ),
            child: Column(
              children: [
                Icon(icon, color: sel ? Colors.white : AppColors.textSecondary, size: 18),
                const SizedBox(height: 5),
                Text(name,
                    style: TextStyle(
                        color: sel ? Colors.white : AppColors.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5)),
                Text(desc,
                    style: TextStyle(
                        color: sel ? Colors.white70 : AppColors.muted, fontSize: 10)),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Template'),
        Row(children: [
          tpl('t1', 'Template 1', 'Modern', Icons.view_agenda_rounded),
          tpl('t2', 'Template 2', 'Classic', Icons.article_rounded),
        ]),
      ],
    );
  }

  Widget _docTypeSelector() {
    Widget chip(String type, IconData icon) {
      final sel = _docType == type;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() {
            _docType = type;
            _scheduleTopicRefresh();
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 13),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              gradient: sel ? AppColors.accentGradient : null,
              color: sel ? null : AppColors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: sel ? Colors.transparent : AppColors.border),
            ),
            child: Column(
              children: [
                Icon(icon, color: sel ? Colors.white : AppColors.textSecondary, size: 20),
                const SizedBox(height: 5),
                Text(type,
                    style: TextStyle(
                        color: sel ? Colors.white : AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5)),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        Row(children: [
          chip('Assignment', Icons.edit_document),
          chip('Lab Report', Icons.science_rounded),
        ]),
        const SizedBox(height: 10),
        Row(
          children: [
            const Text('Group submission',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const Spacer(),
            Switch(
              value: _group,
              activeThumbColor: AppColors.accent,
              onChanged: (v) => setState(() => _group = v),
            ),
          ],
        ),
      ],
    );
  }

  Widget _memberRow(int i, ({TextEditingController name, TextEditingController id}) m) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: SuggestField(
              controller: m.name,
              label: 'Name',
              suggestions: () => _sugg.students,
              onPicked: (s) {
                final id = s.data;
                if (id is String && id.isNotEmpty) m.id.text = id;
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: TextField(
                controller: m.id,
                style: const TextStyle(color: AppColors.text, fontSize: 13),
                decoration: const InputDecoration(labelText: 'ID', isDense: true),
              ),
            ),
          ),
          if (_members.length > 1)
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, color: AppColors.red, size: 20),
              onPressed: () => setState(() {
                m.name.dispose();
                m.id.dispose();
                _members.removeAt(i);
              }),
            ),
        ],
      ),
    );
  }

  /// Green banner shown to a student the CR has already generated for.
  Widget _crNotice() => Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.green.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.green.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: AppColors.green,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(Icons.check_rounded,
                      color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Your CR already made this cover page for you',
                          style: TextStyle(
                              color: AppColors.text,
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                              height: 1.3)),
                      SizedBox(height: 3),
                      Text(
                          'No need to generate it again. Just message the CR to collect your print.',
                          style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11.5,
                              height: 1.4)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 11),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _messageCr,
                icon: const Icon(Icons.chat_rounded, size: 18),
                label: const Text('Message the CR'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  textStyle:
                      const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _sectionLabel(String s) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 16, 2, 8),
        child: Text(s.toUpperCase(),
            style: const TextStyle(
                color: AppColors.accentBright,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6)),
      );

  Widget _field(TextEditingController c, String label, {String? hint}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          style: const TextStyle(color: AppColors.text, fontSize: 14),
          decoration: InputDecoration(labelText: label, hintText: hint),
        ),
      );

  Widget _dateField() => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: _date,
          style: const TextStyle(color: AppColors.text, fontSize: 14),
          decoration: InputDecoration(
            labelText: 'Date of Submission',
            hintText: 'e.g. 25th April 2026',
            suffixIcon: IconButton(
              tooltip: 'Pick a date',
              icon: const Icon(Icons.calendar_month_rounded, color: AppColors.accentBright, size: 20),
              onPressed: _pickDate,
            ),
          ),
        ),
      );

  Widget _dropdown(String label, String value, List<String> items,
          ValueChanged<String?> onChanged) =>
      DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        dropdownColor: AppColors.card,
        decoration: InputDecoration(labelText: label),
        style: const TextStyle(color: AppColors.text, fontSize: 14),
        items: items
            .map((e) => DropdownMenuItem(value: e, child: Text(e)))
            .toList(),
        onChanged: onChanged,
      );

  static const _sections = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N'];
  static final _batches = [
    for (var i = 55; i <= 70; i++) '${i}th'
  ]..[7] = '62nd';
}
