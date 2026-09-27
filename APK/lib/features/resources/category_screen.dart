import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_colors.dart';
import '../../core/sheets_api.dart';
import '../../shared/glass_card.dart';

/// Per-category visuals — mirrors category.html's CAT_META.
class _CatMeta {
  final IconData icon;
  final Color color;
  final String label;
  const _CatMeta(this.icon, this.color, this.label);
}

Map<String, _CatMeta> get _catMeta => {
  'assignment': _CatMeta(Icons.edit_rounded, AppColors.greenBright, 'Assignment'),
  'tutorial': _CatMeta(Icons.menu_book_rounded, AppColors.indigoBright, 'Tutorial'),
  'lab report': _CatMeta(Icons.science_rounded, AppColors.greenBright, 'Lab Report'),
  'lab test': _CatMeta(Icons.biotech_rounded, AppColors.tealBright, 'Lab Test'),
  'viva': _CatMeta(Icons.mic_rounded, Color(0xFFFB7185), 'Viva'),
  'lab final': _CatMeta(Icons.local_fire_department_rounded, AppColors.amberBright, 'Lab Final'),
  'project': _CatMeta(Icons.account_tree_rounded, Color(0xFFC4B5FD), 'Project'),
  'presentation': _CatMeta(Icons.co_present_rounded, AppColors.orangeBright, 'Presentation'),
};

/// Resolve a keyword to a category bucket — mirrors category.html's KEYWORD_MAP.
String? _resolveCategory(String keyword) {
  final kl = keyword.toLowerCase().trim();
  const map = <(List<String>, String)>[
    (['assignment'], 'assignment'),
    (['lab report'], 'lab report'),
    (['lab test'], 'lab test'),
    (['tutorial', 'quiz'], 'tutorial'),
    (['viva'], 'viva'),
    (['lab final', 'lab exam'], 'lab final'),
    (['project'], 'project'),
    (['presentation'], 'presentation'),
  ];
  for (final (keys, cat) in map) {
    for (final k in keys) {
      if (kl == k || kl.contains(k)) return cat;
    }
  }
  return null;
}

class _Entry {
  final String keyword;
  final String reply;
  const _Entry(this.keyword, this.reply);
}

class _Deadline {
  final String course;
  final String title;
  final DateTime due;
  const _Deadline(this.course, this.title, this.due);
}

/// A category browser (Assignment / Tutorial / Lab Report / Viva / Lab Final /
/// Project / Presentation) — AutoBOT keyword→reply cards plus a live
/// countdown of that category's deadlines. Equivalent to category.html.
class CategoryScreen extends StatefulWidget {
  final String cat; // resolved category, e.g. 'presentation', 'lab report'
  const CategoryScreen({super.key, required this.cat});

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  late Future<void> _future = _load();
  List<_Entry> _entries = [];
  List<_Deadline> _deadlines = [];
  String _query = '';
  Timer? _ticker;

  _CatMeta get _meta =>
      _catMeta[widget.cat] ?? _CatMeta(Icons.folder_rounded, AppColors.accentBright, 'Category');

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      SheetsApi.instance.botSheetRaw('AutoBOT').catchError((_) => <List<String>>[]),
      SheetsApi.instance.botSheetRaw('Deadlines').catchError((_) => <List<String>>[]),
    ]);
    _entries = _parseEntries(results[0]);
    _deadlines = _parseDeadlines(results[1]);
    if (_deadlines.isNotEmpty) {
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  List<_Entry> _parseEntries(List<List<String>> rows) {
    final out = <_Entry>[];
    for (final r in rows) {
      if (r.length < 2) continue;
      final keyword = r[0].trim(), reply = r[1].trim();
      if (keyword.isEmpty || reply.isEmpty) continue;
      if (['keyword', 'keywords', 'key'].contains(keyword.toLowerCase())) continue;
      if (_resolveCategory(keyword) == widget.cat) out.add(_Entry(keyword, reply));
    }
    return out;
  }

  List<_Deadline> _parseDeadlines(List<List<String>> rows) {
    final out = <_Deadline>[];
    final now = DateTime.now();
    for (final r in rows) {
      if (r.length < 4) continue;
      final course = r[0].trim(), type = r[1].trim().toLowerCase();
      final title = r[2].trim();
      if (course.isEmpty || title.isEmpty) continue;
      if (['course', 'type', 'title', 'deadline'].contains(course.toLowerCase())) continue;
      if (type != widget.cat) continue;
      final due = _parseGvizDate(r[3]);
      if (due == null || !due.isAfter(now)) continue;
      out.add(_Deadline(course, title, due));
    }
    out.sort((a, b) => a.due.compareTo(b.due));
    return out;
  }

  static DateTime? _parseGvizDate(String s) {
    final t = s.trim();
    final m = RegExp(r'^Date\((\d+),(\d+),(\d+)(?:,(\d+),(\d+)(?:,(\d+))?)?\)$').firstMatch(t);
    if (m != null) {
      return DateTime(
        int.parse(m[1]!),
        int.parse(m[2]!) + 1, // GVIZ month is 0-based
        int.parse(m[3]!),
        int.parse(m[4] ?? '0'),
        int.parse(m[5] ?? '0'),
        int.parse(m[6] ?? '0'),
      );
    }
    return DateTime.tryParse(t.replaceFirst(' ', 'T'));
  }

  @override
  Widget build(BuildContext context) {
    final meta = _meta;
    final filtered = _query.isEmpty
        ? _entries
        : _entries
            .where((e) =>
                e.keyword.toLowerCase().contains(_query) ||
                e.reply.toLowerCase().contains(_query))
            .toList();
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Row(
          children: [
            Icon(meta.icon, color: meta.color, size: 20),
            const SizedBox(width: 8),
            Text(meta.label),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
      ),
      body: FutureBuilder<void>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: AppColors.accent));
          }
          return RefreshIndicator(
            color: AppColors.accent,
            backgroundColor: AppColors.card,
            onRefresh: () async {
              _future = _load();
              await _future;
              if (mounted) setState(() {});
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
              children: [
                _searchBar(meta),
                if (_deadlines.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _sectionLabel('Deadlines', Icons.hourglass_bottom_rounded),
                  const SizedBox(height: 8),
                  ..._deadlines.map((d) => _deadlineCard(d, meta)),
                ],
                const SizedBox(height: 16),
                if (filtered.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 60),
                    child: Center(
                      child: Text(
                        _entries.isEmpty
                            ? 'No entries posted yet for ${meta.label}.'
                            : 'No matches found.',
                        style: TextStyle(color: AppColors.muted, fontSize: 14),
                      ),
                    ),
                  )
                else
                  ...filtered.map((e) => _entryCard(e, meta)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _searchBar(_CatMeta meta) => TextField(
        style: TextStyle(color: AppColors.text, fontSize: 14),
        onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
        decoration: InputDecoration(
          hintText: 'Search ${meta.label}...',
          prefixIcon: Icon(Icons.search, color: AppColors.muted, size: 20),
          isDense: true,
        ),
      );

  Widget _sectionLabel(String s, IconData icon) => Row(
        children: [
          Icon(icon, color: AppColors.accentBright, size: 15),
          const SizedBox(width: 6),
          Text(s.toUpperCase(),
              style: TextStyle(
                  color: AppColors.accentBright,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6)),
        ],
      );

  Widget _entryCard(_Entry e, _CatMeta meta) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: meta.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: meta.color.withValues(alpha: 0.3)),
                  ),
                  child: Icon(meta.icon, color: meta.color, size: 17),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(e.keyword,
                      style: TextStyle(
                          color: AppColors.textBright,
                          fontWeight: FontWeight.w700,
                          fontSize: 14)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SelectableText.rich(
              TextSpan(
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 13, height: 1.5),
                children: _linkify(e.reply, meta.color),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _deadlineCard(_Deadline d, _CatMeta meta) {
    final diff = d.due.difference(DateTime.now());
    final urgent = diff.inHours < 24;
    final warn = diff.inDays < 3;
    final c = urgent
        ? AppColors.red
        : warn
            ? AppColors.amberBright
            : AppColors.greenBright;
    String two(int n) => n.toString().padLeft(2, '0');
    final days = diff.inDays;
    final cd = '${days}d ${two(diff.inHours % 24)}h ${two(diff.inMinutes % 60)}m ${two(diff.inSeconds % 60)}s';
    final due = _fmtDue(d.due);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: meta.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: meta.color.withValues(alpha: 0.3)),
              ),
              child: Icon(meta.icon, color: meta.color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (d.course.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: meta.color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(d.course,
                              style: TextStyle(
                                  color: meta.color,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(d.title,
                      style: TextStyle(
                          color: AppColors.textBright,
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                          height: 1.3)),
                  const SizedBox(height: 3),
                  Text('Due: $due',
                      style: TextStyle(color: AppColors.muted, fontSize: 11.5)),
                  const SizedBox(height: 5),
                  Text(cd,
                      style: TextStyle(
                          color: c,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          fontFeatures: [FontFeature.tabularFigures()])),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _fmtDue(DateTime d) {
    const mo = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ap = d.hour >= 12 ? 'PM' : 'AM';
    return '${mo[d.month - 1]} ${d.day}, $h12:${d.minute.toString().padLeft(2, '0')} $ap';
  }

  List<InlineSpan> _linkify(String text, Color linkColor) {
    final spans = <InlineSpan>[];
    final re = RegExp(r'(https?://[^\s]+)');
    var last = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      final url = m.group(0)!;
      spans.add(TextSpan(
        text: url,
        style: TextStyle(color: linkColor, decoration: TextDecoration.underline),
        recognizer: TapGestureRecognizer()
          ..onTap = () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      ));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return spans;
  }
}
