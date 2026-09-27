import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_colors.dart';
import '../../core/sheets_api.dart';
import '../../shared/avatar_badge.dart';
import '../../shared/glass_card.dart';
import 'sheet_scaffold.dart';

/// Teacher directory — from the "CPG_Teachers" sheet.
/// Columns: Acronym, Name, Designation, Department, Cell, Email.
class TeachersScreen extends StatefulWidget {
  const TeachersScreen({super.key});

  @override
  State<TeachersScreen> createState() => _TeachersScreenState();
}

class _TeachersScreenState extends State<TeachersScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return SheetScaffold(
      title: 'Teachers',
      icon: Icons.person_rounded,
      load: () => SheetsApi.instance.sheet('CPG_Teachers'),
      builder: (rows) {
        final teachers = _parse(rows);
        final filtered = teachers
            .where((t) =>
                _query.isEmpty ||
                t.name.toLowerCase().contains(_query) ||
                t.acronym.toLowerCase().contains(_query))
            .toList();
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
              child: TextField(
                onChanged: (v) => setState(() => _query = v.toLowerCase().trim()),
                decoration: InputDecoration(
                  hintText: 'Search teacher…',
                  prefixIcon: Icon(Icons.search, size: 18, color: AppColors.muted),
                ),
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? const SheetEmpty(message: 'No teachers found.')
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) => _card(filtered[i]),
                    ),
            ),
          ],
        );
      },
    );
  }

  List<_Teacher> _parse(List<List<String>> rows) {
    final out = <_Teacher>[];
    for (final r in rows) {
      String at(int n) => n < r.length ? r[n].trim() : '';
      final acr = at(0);
      final name = at(1);
      if (name.isEmpty || RegExp(r'^(acronym|initials|name)', caseSensitive: false).hasMatch(acr)) {
        continue;
      }
      out.add(_Teacher(
        acronym: acr,
        name: name,
        designation: at(2),
        department: at(3),
        cell: at(4),
        email: at(5),
      ));
    }
    return out;
  }

  Widget _card(_Teacher t) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: GlassCard(
          padding: const EdgeInsets.all(13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AvatarBadge(name: t.name, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.name,
                            style: TextStyle(
                                color: AppColors.textBright,
                                fontWeight: FontWeight.w700,
                                fontSize: 14.5)),
                        if (t.designation.isNotEmpty)
                          Text(t.designation,
                              style: TextStyle(
                                  color: AppColors.textSecondary, fontSize: 12)),
                        if (t.department.isNotEmpty)
                          Text(t.department,
                              style: TextStyle(
                                  color: AppColors.muted, fontSize: 11)),
                      ],
                    ),
                  ),
                  if (t.acronym.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(t.acronym,
                          style: TextStyle(
                              color: AppColors.accentBright,
                              fontWeight: FontWeight.w700,
                              fontSize: 11)),
                    ),
                ],
              ),
              if (t.cell.isNotEmpty || t.email.isNotEmpty) ...[
                const SizedBox(height: 11),
                Row(
                  children: [
                    if (t.cell.isNotEmpty) ...[
                      _action(Icons.call, 'Call', AppColors.green,
                          () => _launch('tel:${_telNumber(t.cell)}')),
                      const SizedBox(width: 8),
                      _action(Icons.chat, 'WhatsApp', const Color(0xFF25D366),
                          () => _launch('https://wa.me/${_waNumber(t.cell)}')),
                    ],
                    if (t.email.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      _action(Icons.email_outlined, 'Email', AppColors.accentBright,
                          () => _launch('mailto:${t.email}')),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      );

  Widget _action(IconData icon, String label, Color color, VoidCallback onTap) =>
      Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: color.withValues(alpha: 0.25)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 5),
                Text(label,
                    style: TextStyle(
                        color: color, fontSize: 11.5, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      );

  // BD phone normalization. Stored values are usually 10 digits without the
  // leading 0 (e.g. "1714506159").
  String _digits(String s) => s.replaceAll(RegExp(r'\D'), '');
  String _telNumber(String s) {
    final d = _digits(s);
    if (d.startsWith('880')) return '+$d';
    if (d.startsWith('0')) return d;
    return '0$d';
  }

  String _waNumber(String s) {
    final d = _digits(s);
    if (d.startsWith('880')) return d;
    if (d.startsWith('0')) return '880${d.substring(1)}';
    return '880$d';
  }

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _Teacher {
  final String acronym, name, designation, department, cell, email;
  _Teacher({
    required this.acronym,
    required this.name,
    required this.designation,
    required this.department,
    required this.cell,
    required this.email,
  });
}
