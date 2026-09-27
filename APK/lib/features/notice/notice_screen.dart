import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_colors.dart';
import '../../core/worker_api.dart';

/// LU notices — from the Worker `/notices` endpoint (scraped LU notice board).
class NoticeScreen extends StatefulWidget {
  const NoticeScreen({super.key});

  @override
  State<NoticeScreen> createState() => _NoticeScreenState();
}

class _NoticeScreenState extends State<NoticeScreen> {
  late Future<List<Map<String, dynamic>>> _future = WorkerApi.instance.notices();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('LU Notices'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: AppColors.accent));
          }
          final items = snap.data ?? [];
          if (items.isEmpty) {
            return Center(
              child: Text('No notices available right now.',
                  style: TextStyle(color: AppColors.muted, fontSize: 14)),
            );
          }
          return RefreshIndicator(
            color: AppColors.accent,
            backgroundColor: AppColors.card,
            onRefresh: () async =>
                setState(() => _future = WorkerApi.instance.notices()),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
              itemCount: items.length,
              itemBuilder: (_, i) => _card(items[i]),
            ),
          );
        },
      ),
    );
  }

  Widget _card(Map<String, dynamic> n) {
    final title = (n['title'] ?? 'Notice').toString();
    final link = (n['link'] ?? '').toString();
    final image = (n['image'] ?? '').toString();
    final date = _fmtDate((n['date'] ?? '').toString());

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => _NoticeDetailScreen(
                title: title, image: image, link: link, date: date),
          )),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (image.isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: image,
                    width: double.infinity,
                    height: 170,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => Container(
                      height: 170,
                      color: AppColors.cardElevated,
                      child: Center(
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.accent)),
                    ),
                    errorWidget: (_, _, _) => const SizedBox.shrink(),
                  ),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              color: AppColors.textBright,
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5,
                              height: 1.4)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.schedule, size: 13, color: AppColors.muted),
                          const SizedBox(width: 5),
                          Text(date,
                              style: TextStyle(
                                  color: AppColors.muted, fontSize: 11.5)),
                          const Spacer(),
                          Icon(Icons.chevron_right_rounded,
                              size: 18, color: AppColors.accentBright),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _fmtDate(String s) {
    try {
      return DateFormat('d MMM yyyy').format(DateTime.parse(s).toLocal());
    } catch (_) {
      // RFC-822 style "Mon, 22 Jun 2026 09:59:48 +0000" — take the date part.
      final parts = s.split(' ');
      if (parts.length >= 4) return '${parts[1]} ${parts[2]} ${parts[3]}';
      return s;
    }
  }

}

/// In-app notice view — shows the notice image (zoomable) and details without
/// leaving the app, with an option to open the original on the LU site.
class _NoticeDetailScreen extends StatelessWidget {
  final String title, image, link, date;
  const _NoticeDetailScreen(
      {required this.title, required this.image, required this.link, required this.date});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Notice'),
        actions: [
          if (link.isNotEmpty)
            IconButton(
              tooltip: 'Open on LU website',
              icon: const Icon(Icons.open_in_new_rounded, size: 20),
              onPressed: () => _open(link),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
        children: [
          if (image.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: CachedNetworkImage(
                  imageUrl: image,
                  width: double.infinity,
                  fit: BoxFit.fitWidth,
                  placeholder: (_, _) => Container(
                    height: 260,
                    color: AppColors.cardElevated,
                    child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent)),
                  ),
                  errorWidget: (_, _, _) => Container(
                    height: 160,
                    color: AppColors.cardElevated,
                    child: Center(
                        child: Icon(Icons.image_not_supported_outlined, color: AppColors.muted, size: 30)),
                  ),
                ),
              ),
            ),
          if (image.isNotEmpty) const SizedBox(height: 16),
          Text(title,
              style: TextStyle(
                  color: AppColors.textBright, fontWeight: FontWeight.w700, fontSize: 16, height: 1.4)),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.schedule, size: 14, color: AppColors.muted),
              const SizedBox(width: 6),
              Text(date, style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
            ],
          ),
          if (link.isNotEmpty) ...[
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () => _open(link),
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('Open on LU website'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accentBright,
                side: BorderSide(color: AppColors.borderAccent),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
