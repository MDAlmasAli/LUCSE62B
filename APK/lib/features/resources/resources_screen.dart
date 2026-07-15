import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_colors.dart';
import '../../core/sheets_api.dart';
import '../../shared/glass_card.dart';
import 'course_materials_screen.dart';

class CourseMaterial {
  final String code;
  final String name;
  final String midFolderId;
  final String finalFolderId;
  const CourseMaterial(
    this.code,
    this.name,
    this.midFolderId,
    this.finalFolderId,
  );
}

/// Study materials — a grid of courses from the "Materials" sheet. Each course
/// opens its Mid/Final Drive folders.
class ResourcesScreen extends StatefulWidget {
  const ResourcesScreen({super.key});

  @override
  State<ResourcesScreen> createState() => _ResourcesScreenState();
}

class _ResourcesScreenState extends State<ResourcesScreen> {
  late Future<List<CourseMaterial>> _future = _load();
  final _search = TextEditingController();
  String _sort = 'code';
  List<String> _recent = const [];

  static const _recentKey = 'resource_recent_courses_v1';

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _recent = prefs.getStringList(_recentKey) ?? const []);
    }
  }

  Future<void> _remember(CourseMaterial c) async {
    final key = c.code.trim().toUpperCase();
    final next = [key, ..._recent.where((e) => e != key)].take(8).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_recentKey, next);
    if (mounted) setState(() => _recent = next);
  }

  Future<List<CourseMaterial>> _load() async {
    final rows = await SheetsApi.instance.sheet('Materials');
    final out = <CourseMaterial>[];
    for (final r in rows) {
      String at(int n) => n < r.length ? r[n].trim() : '';
      final code = at(0);
      if (code.isEmpty || code.toLowerCase() == 'coursecode') continue;
      final mid = at(2), fin = at(3);
      if (mid.isEmpty && fin.isEmpty) continue;
      out.add(CourseMaterial(code, at(1).isEmpty ? code : at(1), mid, fin));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Resources'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Sort resources',
            color: AppColors.card,
            initialValue: _sort,
            onSelected: (v) => setState(() => _sort = v),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'code',
                child: Text(
                  'Sort by course code',
                  style: TextStyle(color: AppColors.text),
                ),
              ),
              PopupMenuItem(
                value: 'name',
                child: Text(
                  'Sort by course name',
                  style: TextStyle(color: AppColors.text),
                ),
              ),
              PopupMenuItem(
                value: 'recent',
                child: Text(
                  'Recent first',
                  style: TextStyle(color: AppColors.text),
                ),
              ),
            ],
            icon: const Icon(Icons.sort_rounded),
          ),
        ],
      ),
      body: FutureBuilder<List<CourseMaterial>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            );
          }
          final courses = snap.data ?? [];
          if (courses.isEmpty) {
            return const Center(
              child: Text(
                'No materials posted yet.',
                style: TextStyle(color: AppColors.muted, fontSize: 14),
              ),
            );
          }
          final visible = _visibleCourses(courses);
          return RefreshIndicator(
            color: AppColors.accent,
            backgroundColor: AppColors.card,
            onRefresh: () async {
              SheetsApi.instance.clearCache();
              setState(() => _future = _load());
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
              children: [
                _searchBox(),
                if (_recent.isNotEmpty) _recentStrip(courses),
                if (visible.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Center(
                      child: Text(
                        'No matching resources found.',
                        style: TextStyle(color: AppColors.muted, fontSize: 14),
                      ),
                    ),
                  )
                else
                  ...visible.map(_card),
              ],
            ),
          );
        },
      ),
    );
  }

  List<CourseMaterial> _visibleCourses(List<CourseMaterial> courses) {
    final q = _search.text.trim().toLowerCase();
    final list = courses.where((c) {
      if (q.isEmpty) return true;
      return c.code.toLowerCase().contains(q) ||
          c.name.toLowerCase().contains(q);
    }).toList();
    if (_sort == 'name') {
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } else if (_sort == 'recent') {
      int rank(CourseMaterial c) {
        final i = _recent.indexOf(c.code.trim().toUpperCase());
        return i < 0 ? 9999 : i;
      }

      list.sort((a, b) {
        final r = rank(a).compareTo(rank(b));
        return r != 0 ? r : a.code.compareTo(b.code);
      });
    } else {
      list.sort((a, b) => a.code.compareTo(b.code));
    }
    return list;
  }

  Widget _searchBox() => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: _search,
      onChanged: (_) => setState(() {}),
      style: const TextStyle(color: AppColors.text, fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Search course code or resource name...',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _search.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  _search.clear();
                  setState(() {});
                },
              ),
      ),
    ),
  );

  Widget _recentStrip(List<CourseMaterial> courses) {
    final byCode = {for (final c in courses) c.code.trim().toUpperCase(): c};
    final recent = _recent
        .map((c) => byCode[c])
        .whereType<CourseMaterial>()
        .toList();
    if (recent.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recently opened',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final c in recent)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      backgroundColor: AppColors.card,
                      side: BorderSide(color: AppColors.border),
                      label: Text(
                        c.code,
                        style: const TextStyle(color: AppColors.text),
                      ),
                      avatar: Icon(
                        _icon(c.code),
                        color: _color(c.code),
                        size: 16,
                      ),
                      onPressed: () => _openCourse(c),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openCourse(CourseMaterial c) async {
    await _remember(c);
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => CourseMaterialsScreen(course: c)));
    await _loadRecent();
  }

  Widget _card(CourseMaterial c) {
    final color = _color(c.code);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        onTap: () => _openCourse(c),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: color.withValues(alpha: 0.28)),
              ),
              child: Icon(_icon(c.code), color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.code,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    c.name,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.muted),
          ],
        ),
      ),
    );
  }

  IconData _icon(String code) {
    final p = code.split('-').first.toUpperCase();
    switch (p) {
      case 'CSE':
        return Icons.laptop_mac_rounded;
      case 'MAT':
        return Icons.functions_rounded;
      case 'PHY':
        return Icons.science_rounded;
      case 'EEE':
        return Icons.bolt_rounded;
      case 'GED':
        return Icons.menu_book_rounded;
      default:
        return Icons.school_rounded;
    }
  }

  Color _color(String code) {
    var h = 0;
    for (var i = 0; i < code.length; i++) {
      h = (h * 31 + code.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    const palette = [
      Color(0xFFA78BFA),
      Color(0xFF38BDF8),
      Color(0xFF34D399),
      Color(0xFFF87171),
      Color(0xFFFBBF24),
      Color(0xFFF472B6),
      Color(0xFF22D3EE),
    ];
    return palette[h % palette.length];
  }
}
