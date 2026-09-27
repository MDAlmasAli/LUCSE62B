import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_colors.dart';
import '../../core/sheets_api.dart';
import '../../shared/app_toast.dart';
import '../../shared/glass_card.dart';
import 'sheet_scaffold.dart';

/// Group links & codes — from "CPG_Courses".
/// Cols: Title, Code, ... Teacher(4), GroupLink(9), ClassroomLink(10), ClassroomCode(11).
class GroupLinksScreen extends StatelessWidget {
  const GroupLinksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SheetScaffold(
      title: 'Group Links & Codes',
      icon: Icons.link_rounded,
      load: () => SheetsApi.instance.sheet('CPG_Courses'),
      builder: (rows) {
        final courses = _parse(rows);
        if (courses.isEmpty) {
          return const SheetEmpty(message: 'No group links available yet.');
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
          itemCount: courses.length,
          itemBuilder: (_, i) => _card(context, courses[i]),
        );
      },
    );
  }

  List<_Course> _parse(List<List<String>> rows) {
    if (rows.isEmpty) return [];
    final firstCode = rows[0].length > 1 ? rows[0][1].toLowerCase().trim() : '';
    final start = (firstCode == 'code' || firstCode == 'course code') ? 1 : 0;
    final out = <_Course>[];
    for (var i = start; i < rows.length; i++) {
      final r = rows[i];
      String at(int n) => n < r.length ? r[n].trim() : '';
      String clean(String s) => (s == '-') ? '' : s;
      final wa = clean(at(9)), gc = clean(at(10)), code = clean(at(11));
      if (wa.isEmpty && gc.isEmpty && code.isEmpty) continue;
      out.add(_Course(
        title: at(0),
        code: at(1),
        teacher: at(4).isEmpty ? 'TBA' : at(4),
        groupLink: wa,
        classroomLink: gc,
        classroomCode: code,
      ));
    }
    return out;
  }

  Widget _card(BuildContext context, _Course c) {
    final color = _courseColor(c.code);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(height: 3, color: color),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(c.code,
                        style: TextStyle(
                            color: color, fontWeight: FontWeight.w700, fontSize: 12)),
                  ),
                  const SizedBox(height: 8),
                  Text(c.title,
                      style: TextStyle(
                          color: AppColors.textBright,
                          fontWeight: FontWeight.w700,
                          fontSize: 15)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.person, size: 13, color: AppColors.muted),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(c.teacher,
                            style: TextStyle(
                                color: AppColors.textSecondary, fontSize: 12.5)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (c.groupLink.isNotEmpty)
                        _btn(Icons.chat, 'WhatsApp', const Color(0xFF25D366),
                            () => _open(c.groupLink)),
                      if (c.classroomLink.isNotEmpty)
                        _btn(Icons.school, 'Classroom', const Color(0xFF1A73E8),
                            () => _open(c.classroomLink)),
                      if (c.classroomCode.isNotEmpty)
                        _btn(Icons.key, c.classroomCode, AppColors.accentBright, () {
                          Clipboard.setData(ClipboardData(text: c.classroomCode));
                          AppToast.show(context, 'Class code copied');
                        }),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _btn(IconData icon, String label, Color color, VoidCallback onTap) =>
      InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: color.withValues(alpha: 0.28)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      color: color, fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );

  Color _courseColor(String code) {
    var h = 0;
    for (var i = 0; i < code.length; i++) {
      h = (h * 31 + code.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    final palette = [
      AppColors.accentBright, AppColors.blueBright, AppColors.greenBright,
      AppColors.redBright, AppColors.amberBright, AppColors.pinkBright,
      AppColors.cyanBright, Color(0xFFC084FC),
    ];
    return palette[h % palette.length];
  }

  Future<void> _open(String url) async {
    var u = url.trim();
    if (!u.startsWith('http')) u = 'https://$u';
    final uri = Uri.parse(u);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _Course {
  final String title, code, teacher, groupLink, classroomLink, classroomCode;
  _Course({
    required this.title,
    required this.code,
    required this.teacher,
    required this.groupLink,
    required this.classroomLink,
    required this.classroomCode,
  });
}
