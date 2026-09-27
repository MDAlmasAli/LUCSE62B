import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_colors.dart';
import '../../core/sheets_api.dart';
import '../../core/worker_api.dart';
import '../../data/session.dart';
import '../../shared/app_toast.dart';
import '../../shared/avatar_badge.dart';
import '../../shared/glass_card.dart';

/// Directory payload: the grouped student rows plus an id→phone map (the phone
/// column is served separately by the Worker so the public sheet stays masked).
class _DirData {
  final List<SheetGroup> groups;
  final Map<String, String> phones;
  const _DirData(this.groups, this.phones);
}

/// Student directory — live from the "Student Info" Google Sheet via the Worker.
/// Mirrors script.js (grouped sections); demo sessions see masked data. The
/// phone column (WhatsApp numbers) gets a one-tap WhatsApp contact button.
class StudentsScreen extends StatefulWidget {
  const StudentsScreen({super.key});

  @override
  State<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends State<StudentsScreen> {
  late Future<_DirData> _future;
  String _query = '';

  bool get _demo => Session.instance.isDemo;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DirData> _load() async {
    final results = await Future.wait([
      SheetsApi.instance.sheet('Student Info'),
      _demo
          ? Future.value(<String, String>{})
          : WorkerApi.instance.studentPhones(),
    ]);
    final groups = SheetsApi.parseGroups(results[0] as List<List<String>>);
    final phones = results[1] as Map<String, String>;
    return _DirData(groups, phones);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Students'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
      ),
      body: _demo
          ? _restricted()
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
                  child: TextField(
                    onChanged: (v) => setState(() => _query = v.toLowerCase().trim()),
                    decoration: InputDecoration(
                      hintText: 'Search by name or ID…',
                      prefixIcon: Icon(Icons.search, size: 18, color: AppColors.muted),
                    ),
                  ),
                ),
                Expanded(
                  child: FutureBuilder<_DirData>(
                    future: _future,
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return Center(
                            child: CircularProgressIndicator(color: AppColors.accent));
                      }
                      if (snap.hasError || !snap.hasData) {
                        return _error();
                      }
                      return _list(snap.data!);
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _list(_DirData data) {
    // Flatten groups → headers + cards once, then render lazily so only the
    // visible rows build their elements (smooth scrolling on long lists).
    final items = <Widget>[
      for (final g in data.groups) ..._group(g, data.phones),
    ];
    return RefreshIndicator(
      color: AppColors.accent,
      backgroundColor: AppColors.card,
      onRefresh: () async {
        SheetsApi.instance.clearCache();
        setState(() => _future = _load());
      },
      child: items.isEmpty
          ? ListView(children: [
              Padding(
                padding: EdgeInsets.only(top: 90),
                child: Center(
                    child: Text('No students found.',
                        style: TextStyle(color: AppColors.muted))),
              ),
            ])
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
              itemCount: items.length,
              itemBuilder: (_, i) => items[i],
            ),
    );
  }

  List<Widget> _group(SheetGroup g, Map<String, String> phones) {
    // Identify key columns by header name.
    int idxOf(List<String> keys) => g.headers.indexWhere(
        (h) => keys.any((k) => h.toLowerCase().contains(k)));
    final nameIdx = idxOf(['name']);
    final idIdx = idxOf(['id']);
    final slIdx = g.headers.indexWhere((h) {
      final l = h.toLowerCase().trim();
      return l == '#' || l == 'sl' || l.startsWith('sl ') || l.startsWith('sl.') || l.contains('serial');
    });
    final phoneIdx = idxOf(['phone', 'mobile', 'whatsapp', 'contact', 'number']);

    final filtered = g.rows.where((r) {
      if (_query.isEmpty) return true;
      final name = nameIdx >= 0 && nameIdx < r.length ? r[nameIdx] : '';
      final id = idIdx >= 0 && idIdx < r.length ? r[idIdx] : '';
      return name.toLowerCase().contains(_query) || id.toLowerCase().contains(_query);
    }).toList();

    if (filtered.isEmpty) return const [];

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 10),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(Icons.groups_rounded, size: 16, color: AppColors.accentBright),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(g.title,
                  style: TextStyle(
                      color: AppColors.textBright,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
              ),
              child: Text('${filtered.length}',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
      ...filtered.map((r) {
        final id = (idIdx >= 0 && idIdx < r.length) ? r[idIdx] : '';
        final phone = phones[_digits(id)] ?? '';
        return _studentCard(g.headers, r, nameIdx, idIdx, slIdx, phoneIdx, phone);
      }),
    ];
  }

  static String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  Widget _studentCard(List<String> headers, List<String> row, int nameIdx,
      int idIdx, int slIdx, int phoneIdx, String phone) {
    final name = (nameIdx >= 0 && nameIdx < row.length) ? row[nameIdx] : 'Student';
    final id = (idIdx >= 0 && idIdx < row.length) ? row[idIdx] : '';
    final sl = (slIdx >= 0 && slIdx < row.length) ? row[slIdx].trim() : '';

    // Extra fields (skip name / id / phone / serial which get dedicated spots).
    final details = <MapEntry<String, String>>[];
    for (var i = 0; i < headers.length && i < row.length; i++) {
      if (i == nameIdx || i == idIdx || i == phoneIdx || i == slIdx) continue;
      final label = headers[i].trim();
      final value = row[i].trim();
      if (label.isEmpty || value.isEmpty || label == '#') continue;
      details.add(MapEntry(label, value));
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AvatarBadge(name: name, size: 46),
                    if (sl.isNotEmpty)
                      Positioned(
                        left: -4,
                        top: -4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Text(sl,
                              style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: TextStyle(
                              color: AppColors.textBright,
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5,
                              height: 1.25)),
                      if (id.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(id,
                              style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                  fontFamily: 'monospace')),
                        ),
                    ],
                  ),
                ),
                if (phone.isNotEmpty) _whatsappButton(name, phone),
              ],
            ),
            if (details.isNotEmpty) ...[
              Divider(height: 18, color: AppColors.border),
              ...details.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.key.toUpperCase(),
                            style: TextStyle(
                                color: AppColors.muted,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.4)),
                        const SizedBox(height: 2),
                        Text(e.value,
                            style: TextStyle(
                                color: AppColors.text, fontSize: 13, height: 1.3)),
                      ],
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }

  /// Round WhatsApp button — opens a chat with the student's number.
  Widget _whatsappButton(String name, String phone) {
    return Tooltip(
      message: 'WhatsApp $phone',
      child: Material(
        color: const Color(0xFF25D366).withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openWhatsApp(phone),
          child: Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF25D366).withValues(alpha: 0.4)),
            ),
            child: const Icon(Icons.chat_rounded, color: Color(0xFF25D366), size: 21),
          ),
        ),
      ),
    );
  }

  Future<void> _openWhatsApp(String rawPhone) async {
    final intl = _toIntlNumber(rawPhone);
    if (intl.isEmpty) {
      if (mounted) AppToast.show(context, 'No valid number to message', error: true);
      return;
    }
    final uri = Uri.parse('https://wa.me/$intl');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        AppToast.show(context, 'Could not open WhatsApp', error: true);
      }
    } catch (_) {
      if (mounted) AppToast.show(context, 'Could not open WhatsApp', error: true);
    }
  }

  /// Normalise a (Bangladeshi) phone number to wa.me international form.
  static String _toIntlNumber(String raw) {
    var d = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.isEmpty) return '';
    if (d.startsWith('00')) d = d.substring(2);
    if (d.startsWith('880')) return d;
    if (d.startsWith('0')) return '88$d'; // 01XXXXXXXXX → 8801XXXXXXXXX
    if (d.length == 10 && d.startsWith('1')) return '880$d';
    return d;
  }

  Widget _restricted() => Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, color: AppColors.muted, size: 36),
              SizedBox(height: 12),
              Text('Student directory is not available in demo mode.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
            ],
          ),
        ),
      );

  Widget _error() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, color: AppColors.muted, size: 34),
            const SizedBox(height: 12),
            Text('Unable to load student data right now.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: () => setState(() => _future = _load()),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
}
