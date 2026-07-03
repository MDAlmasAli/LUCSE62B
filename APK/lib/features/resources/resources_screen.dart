import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_colors.dart';
import '../../core/sheets_api.dart';
import '../../shared/glass_card.dart';
import 'course_materials_screen.dart';

class CourseMaterial {
  final String code;
  final String name;
  final String midFolderId;
  final String finalFolderId;
  const CourseMaterial(this.code, this.name, this.midFolderId, this.finalFolderId);
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
      ),
      body: FutureBuilder<List<CourseMaterial>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.accent));
          }
          final courses = snap.data ?? [];
          if (courses.isEmpty) {
            return const Center(
              child: Text('No materials posted yet.',
                  style: TextStyle(color: AppColors.muted, fontSize: 14)),
            );
          }
          return RefreshIndicator(
            color: AppColors.accent,
            backgroundColor: AppColors.card,
            onRefresh: () async => setState(() => _future = _load()),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
              itemCount: courses.length,
              itemBuilder: (_, i) => _card(courses[i]),
            ),
          );
        },
      ),
    );
  }

  Widget _card(CourseMaterial c) {
    final color = _color(c.code);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => CourseMaterialsScreen(course: c),
        )),
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
                  Text(c.code,
                      style: TextStyle(
                          color: color, fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(c.name,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12.5, height: 1.3)),
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
      Color(0xFFA78BFA), Color(0xFF38BDF8), Color(0xFF34D399),
      Color(0xFFF87171), Color(0xFFFBBF24), Color(0xFFF472B6), Color(0xFF22D3EE),
    ];
    return palette[h % palette.length];
  }
}
