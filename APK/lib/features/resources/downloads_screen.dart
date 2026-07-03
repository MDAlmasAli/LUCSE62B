import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_colors.dart';
import '../../data/download_service.dart';
import '../../shared/app_toast.dart';
import '../../shared/glass_card.dart';
import 'pdf_viewer_screen.dart';
import 'pptx_viewer_screen.dart';
import 'text_file_viewer_screen.dart';

/// All files saved on this device — available offline, opened with the phone's
/// default viewer. No internet or Drive needed once a file is here.
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  late Future<List<DownloadEntry>> _future = DownloadService.instance.list();

  void _reload() => setState(() => _future = DownloadService.instance.list());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Downloads'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
      ),
      body: FutureBuilder<List<DownloadEntry>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            );
          }
          final items = snap.data ?? const [];
          if (items.isEmpty) return _empty();
          return RefreshIndicator(
            color: AppColors.accent,
            backgroundColor: AppColors.card,
            onRefresh: () async => _reload(),
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

  Widget _empty() => ListView(
    children: const [
      SizedBox(height: 120),
      Icon(Icons.cloud_done_outlined, color: AppColors.muted, size: 42),
      SizedBox(height: 14),
      Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            'No downloads yet.\nOpen any file in Resources to save it here for offline use.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 13.5,
              height: 1.5,
            ),
          ),
        ),
      ),
    ],
  );

  Widget _card(DownloadEntry e) {
    final (icon, color, _) = _typeMeta(e.mime);
    final sub = [
      if (e.source.isNotEmpty) e.source,
      if (e.size > 0) DownloadService.prettySize(e.size),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: GlassCard(
        onTap: () async {
          if (DownloadService.isPdf(e.name, e.mime)) {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => PdfViewerScreen(entry: e)),
            );
            return;
          }
          if (DownloadService.isPptx(e.name, e.mime)) {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => PptxViewerScreen(entry: e)),
            );
            return;
          }
          if (DownloadService.isReadableText(e.name, e.mime)) {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => TextFileViewerScreen(entry: e)),
            );
            return;
          }
          final ok = await DownloadService.instance.open(e.fileId);
          if (!ok && mounted) {
            AppToast.show(context, 'Could not open this file', error: true);
          }
        },
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 19),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.name,
                    softWrap: true,
                    style: const TextStyle(
                      color: AppColors.text,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  if (sub.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              icon: const Icon(
                Icons.delete_outline_rounded,
                size: 20,
                color: AppColors.muted,
              ),
              tooltip: 'Delete',
              onPressed: () async {
                await DownloadService.instance.delete(e.fileId);
                _reload();
              },
            ),
          ],
        ),
      ),
    );
  }

  (IconData, Color, String) _typeMeta(String mime) {
    final m = mime.toLowerCase();
    if (m == 'application/pdf') {
      return (Icons.picture_as_pdf_rounded, const Color(0xFFF87171), 'PDF');
    }
    if (m.startsWith('video/')) {
      return (Icons.play_circle_rounded, const Color(0xFF38BDF8), 'Video');
    }
    if (m.contains('powerpoint') || m.contains('presentation')) {
      return (Icons.slideshow_rounded, const Color(0xFFD97706), 'Slides');
    }
    if (m.contains('zip') || m.contains('rar')) {
      return (Icons.folder_zip_rounded, const Color(0xFFFBBF24), 'Archive');
    }
    if (m.startsWith('image/')) {
      return (Icons.image_rounded, const Color(0xFF34D399), 'Image');
    }
    if (m.contains('word') || m.contains('document')) {
      return (Icons.description_rounded, const Color(0xFF60A5FA), 'Doc');
    }
    return (Icons.insert_drive_file_rounded, AppColors.accentBright, 'File');
  }
}
