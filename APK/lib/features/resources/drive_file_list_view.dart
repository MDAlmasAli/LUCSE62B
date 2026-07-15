import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_colors.dart';
import '../../core/worker_api.dart';
import '../../data/download_service.dart';
import '../../shared/app_toast.dart';
import '../../shared/glass_card.dart';
import 'pdf_viewer_screen.dart';
import 'pptx_viewer_screen.dart';
import 'text_file_viewer_screen.dart';

const _kFolderMime = 'application/vnd.google-apps.folder';

/// A reusable Google-Drive folder browser: lists sub-folders (tappable to open)
/// and files (download once → open in the device's default viewer, works for
/// PDF, Office docs, text, code, images, etc.). Used by the course materials
/// screen and by [DriveFolderScreen] for nested folders.
class DriveFileListView extends StatefulWidget {
  final String folderId;
  final String courseCode; // download "source" tag
  final EdgeInsets padding;
  const DriveFileListView({
    super.key,
    required this.folderId,
    required this.courseCode,
    this.padding = const EdgeInsets.fromLTRB(14, 4, 14, 24),
  });

  @override
  State<DriveFileListView> createState() => _DriveFileListViewState();
}

class _DriveFileListViewState extends State<DriveFileListView> {
  late Future<List<Map<String, dynamic>>> _future;
  final _search = TextEditingController();
  Map<String, DownloadEntry> _entries = {};
  String _filter = 'all';
  String _sort = 'name';

  @override
  void initState() {
    super.initState();
    _future = WorkerApi.instance.driveFolder(widget.folderId);
    _refreshDownloaded();
    DownloadService.instance.active.addListener(_refreshDownloaded);
  }

  @override
  void dispose() {
    DownloadService.instance.active.removeListener(_refreshDownloaded);
    _search.dispose();
    super.dispose();
  }

  Future<void> _refreshDownloaded() async {
    final list = await DownloadService.instance.list();
    if (mounted) setState(() => _entries = {for (final e in list) e.fileId: e});
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.accent),
          );
        }
        final all = _visible(snap.data ?? []);
        final folders = all
            .where((f) => '${f['mimeType']}' == _kFolderMime)
            .toList();
        final files = all
            .where((f) => '${f['mimeType']}' != _kFolderMime)
            .toList();
        if (folders.isEmpty && files.isEmpty) {
          return const Center(
            child: Text(
              'No files in this folder yet.',
              style: TextStyle(color: AppColors.muted, fontSize: 14),
            ),
          );
        }
        return RefreshIndicator(
          color: AppColors.accent,
          backgroundColor: AppColors.card,
          onRefresh: () async {
            setState(() {
              _future = WorkerApi.instance.driveFolder(widget.folderId);
            });
            await _future;
            await _refreshDownloaded();
          },
          child: ListView(
            padding: widget.padding,
            children: [
              _tools(),
              ...folders.map(_folderCard),
              ...files.map(_fileCard),
            ],
          ),
        );
      },
    );
  }

  List<Map<String, dynamic>> _visible(List<Map<String, dynamic>> all) {
    final q = _search.text.trim().toLowerCase();
    final filtered = all.where((f) {
      final name = (f['name'] ?? '').toString();
      final mime = (f['mimeType'] ?? '').toString();
      final isFolder = mime == _kFolderMime;
      if (q.isNotEmpty && !name.toLowerCase().contains(q)) return false;
      if (_filter == 'saved' &&
          !_entries.containsKey((f['id'] ?? '').toString())) {
        return false;
      }
      if (_filter != 'all' && _filter != 'saved' && !isFolder) {
        if (_filter == 'text' && DownloadService.isReadableText(name, mime)) {
          return true;
        }
        final meta = _typeMeta(mime, name).$3.toLowerCase();
        if (meta != _filter) return false;
      }
      return true;
    }).toList();
    filtered.sort((a, b) {
      final am = (a['mimeType'] ?? '').toString();
      final bm = (b['mimeType'] ?? '').toString();
      final af = am == _kFolderMime, bf = bm == _kFolderMime;
      if (af != bf) return af ? -1 : 1;
      if (_sort == 'type') {
        final t = _typeMeta(
          am,
          (a['name'] ?? '').toString(),
        ).$3.compareTo(_typeMeta(bm, (b['name'] ?? '').toString()).$3);
        if (t != 0) return t;
      } else if (_sort == 'saved') {
        final ae = _entries[(a['id'] ?? '').toString()];
        final be = _entries[(b['id'] ?? '').toString()];
        if (ae != null || be != null) {
          if (ae == null) return 1;
          if (be == null) return -1;
          return be.savedAt.compareTo(ae.savedAt);
        }
      }
      return (a['name'] ?? '').toString().toLowerCase().compareTo(
        (b['name'] ?? '').toString().toLowerCase(),
      );
    });
    return filtered;
  }

  Widget _tools() => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      children: [
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(color: AppColors.text, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Search files in this folder...',
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
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _filterChip('all', 'All'),
              _filterChip('saved', 'Saved offline'),
              _filterChip('pdf', 'PDF'),
              _filterChip('slides', 'Slides'),
              _filterChip('document', 'Docs'),
              _filterChip('text', 'Text/code'),
              const SizedBox(width: 8),
              _sortChip('name', 'Name'),
              _sortChip('type', 'Type'),
              _sortChip('saved', 'Recent saved'),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _filterChip(String value, String label) => Padding(
    padding: const EdgeInsets.only(right: 7),
    child: ChoiceChip(
      selected: _filter == value,
      label: Text(label),
      onSelected: (_) => setState(() => _filter = value),
      selectedColor: AppColors.accent.withValues(alpha: 0.22),
      backgroundColor: AppColors.card,
      side: BorderSide(
        color: _filter == value ? AppColors.accent : AppColors.border,
      ),
      labelStyle: TextStyle(
        color: _filter == value ? AppColors.text : AppColors.textSecondary,
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _sortChip(String value, String label) => Padding(
    padding: const EdgeInsets.only(right: 7),
    child: ActionChip(
      label: Text(label),
      onPressed: () => setState(() => _sort = value),
      backgroundColor: _sort == value
          ? AppColors.accent.withValues(alpha: 0.18)
          : AppColors.card,
      side: BorderSide(
        color: _sort == value ? AppColors.accent : AppColors.border,
      ),
      labelStyle: TextStyle(
        color: _sort == value ? AppColors.text : AppColors.textSecondary,
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _folderCard(Map<String, dynamic> f) {
    final name = (f['name'] ?? 'Folder').toString();
    final id = (f['id'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: GlassCard(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DriveFolderScreen(
              folderId: id,
              title: name,
              courseCode: widget.courseCode,
            ),
          ),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFFBBF24).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.folder_rounded,
                color: Color(0xFFFBBF24),
                size: 21,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name,
                style: const TextStyle(
                  color: AppColors.text,
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.muted,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Widget _fileCard(Map<String, dynamic> f) {
    final name = (f['name'] ?? 'File').toString();
    final id = (f['id'] ?? '').toString();
    final mime = (f['mimeType'] ?? '').toString();
    final (icon, color, label) = _typeMeta(mime, name);

    return ValueListenableBuilder<Map<String, DlProgress>>(
      valueListenable: DownloadService.instance.active,
      builder: (context, active, _) {
        final prog = active[id];
        final downloading = prog != null;
        final entry = _entries[id];
        final isDown = entry != null;

        return Padding(
          padding: const EdgeInsets.only(bottom: 9),
          child: GlassCard(
            onTap: downloading ? null : () => _onTap(id, name, mime),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                          // Full file name — wraps, never truncated.
                          Text(
                            name,
                            softWrap: true,
                            style: const TextStyle(
                              color: AppColors.text,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Text(
                                label,
                                style: TextStyle(color: color, fontSize: 11),
                              ),
                              if (isDown) ...[
                                const SizedBox(width: 8),
                                const Icon(
                                  Icons.offline_pin_rounded,
                                  size: 12,
                                  color: Color(0xFF34D399),
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  entry.size > 0
                                      ? 'Saved · ${DownloadService.prettySize(entry.size)}'
                                      : 'Saved offline',
                                  style: const TextStyle(
                                    color: Color(0xFF34D399),
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    _trailing(id, isDown, downloading, prog),
                  ],
                ),
                if (downloading) ...[
                  const SizedBox(height: 10),
                  _progressBar(prog),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _progressBar(DlProgress p) {
    final pct = p.known ? '${(p.fraction * 100).round()}%' : '';
    final sizeText = p.known
        ? '${DownloadService.prettySize(p.received)} / ${DownloadService.prettySize(p.total)}'
        : (p.received > 0
              ? DownloadService.prettySize(p.received)
              : 'Starting…');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: p.known ? p.fraction : null,
            minHeight: 6,
            backgroundColor: AppColors.border,
            valueColor: const AlwaysStoppedAnimation(AppColors.accentBright),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              p.cancelling
                  ? 'Stopping…'
                  : p.paused
                  ? 'Paused · $sizeText'
                  : sizeText,
              style: const TextStyle(color: AppColors.muted, fontSize: 10.5),
            ),
            if (pct.isNotEmpty)
              Text(
                pct,
                style: const TextStyle(
                  color: AppColors.accentBright,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _trailing(
    String id,
    bool isDown,
    bool downloading,
    DlProgress? progress,
  ) {
    if (downloading) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: progress?.paused == true
                ? 'Resume download'
                : 'Pause download',
            onPressed: progress?.cancelling == true
                ? null
                : () {
                    if (progress?.paused == true) {
                      DownloadService.instance.resume(id);
                    } else {
                      DownloadService.instance.pause(id);
                    }
                  },
            icon: Icon(
              progress?.paused == true
                  ? Icons.play_arrow_rounded
                  : Icons.pause_rounded,
              size: 21,
              color: AppColors.accentBright,
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Stop download',
            onPressed: progress?.cancelling == true
                ? null
                : () => DownloadService.instance.cancel(id),
            icon: const Icon(
              Icons.stop_circle_outlined,
              size: 21,
              color: AppColors.red,
            ),
          ),
        ],
      );
    }
    if (isDown) {
      return PopupMenuButton<String>(
        icon: const Icon(
          Icons.more_vert_rounded,
          size: 20,
          color: AppColors.muted,
        ),
        color: AppColors.card,
        onSelected: (v) {
          if (v == 'open') _open(id);
          if (v == 'drive') _openInDrive(id);
          if (v == 'delete') _deleteDownload(id);
        },
        itemBuilder: (_) => const [
          PopupMenuItem(
            value: 'open',
            child: Text('Open', style: TextStyle(color: AppColors.text)),
          ),
          PopupMenuItem(
            value: 'drive',
            child: Text(
              'Open in Drive',
              style: TextStyle(color: AppColors.text),
            ),
          ),
          PopupMenuItem(
            value: 'delete',
            child: Text(
              'Delete download',
              style: TextStyle(color: AppColors.red),
            ),
          ),
        ],
      );
    }
    return const Icon(Icons.download_rounded, size: 20, color: AppColors.muted);
  }

  (IconData, Color, String) _typeMeta(String mime, String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    if (mime == 'application/pdf' || ext == 'pdf') {
      return (Icons.picture_as_pdf_rounded, const Color(0xFFF87171), 'PDF');
    }
    if (mime.startsWith('video/') ||
        ['mp4', 'mkv', 'mov', 'avi', 'webm'].contains(ext)) {
      return (Icons.play_circle_rounded, const Color(0xFF38BDF8), 'Video');
    }
    if (mime.contains('powerpoint') ||
        mime.contains('presentation') ||
        ['ppt', 'pptx'].contains(ext)) {
      return (Icons.slideshow_rounded, const Color(0xFFD97706), 'Slides');
    }
    if (mime.contains('sheet') ||
        mime.contains('excel') ||
        ['xls', 'xlsx', 'csv'].contains(ext)) {
      return (Icons.table_chart_rounded, const Color(0xFF22C55E), 'Sheet');
    }
    if (mime.contains('zip') ||
        mime.contains('rar') ||
        ['zip', 'rar', '7z'].contains(ext)) {
      return (Icons.folder_zip_rounded, const Color(0xFFFBBF24), 'Archive');
    }
    if (mime.startsWith('image/') ||
        ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'].contains(ext)) {
      return (Icons.image_rounded, const Color(0xFF34D399), 'Image');
    }
    if (mime.contains('word') ||
        mime.contains('document') ||
        ['doc', 'docx', 'rtf', 'odt'].contains(ext)) {
      return (Icons.description_rounded, const Color(0xFF60A5FA), 'Document');
    }
    const codeExt = {
      'c',
      'cpp',
      'h',
      'hpp',
      'java',
      'py',
      'js',
      'ts',
      'dart',
      'kt',
      'cs',
      'go',
      'rb',
      'php',
      'swift',
      'rs',
      'sql',
      'html',
      'css',
      'json',
      'xml',
      'sh',
      'ipynb',
      'm',
      'r',
    };
    if (codeExt.contains(ext)) {
      return (Icons.code_rounded, const Color(0xFFA78BFA), ext.toUpperCase());
    }
    if (mime.startsWith('text/') || ['txt', 'md', 'log'].contains(ext)) {
      return (Icons.notes_rounded, const Color(0xFF94A3B8), 'Text');
    }
    return (
      Icons.insert_drive_file_rounded,
      AppColors.accentBright,
      ext.isEmpty ? 'File' : ext.toUpperCase(),
    );
  }

  Future<void> _onTap(String id, String name, String mime) async {
    if (id.isEmpty || DownloadService.instance.isActive(id)) return;
    if (_entries.containsKey(id)) {
      await _open(id);
      return;
    }
    final result = await DownloadService.instance.download(
      id,
      name,
      mime: mime,
      source: widget.courseCode,
    );
    if (!mounted) return;
    await _refreshDownloaded();
    if (!mounted) return;
    if (result.finish == DownloadFinish.success) {
      AppToast.show(context, 'Saved for offline · opening…');
      await _open(id);
    } else if (result.finish == DownloadFinish.cancelled) {
      AppToast.show(context, 'Download stopped');
    } else {
      AppToast.show(context, 'Opening in Drive…');
      await _openInDrive(id);
    }
  }

  Future<void> _open(String id) async {
    final entry = await DownloadService.instance.entry(id);
    if (entry != null &&
        DownloadService.isPdf(entry.name, entry.mime) &&
        mounted) {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => PdfViewerScreen(entry: entry)));
      return;
    }
    if (entry != null &&
        DownloadService.isPptx(entry.name, entry.mime) &&
        mounted) {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => PptxViewerScreen(entry: entry)));
      return;
    }
    if (entry != null &&
        DownloadService.isReadableText(entry.name, entry.mime) &&
        mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => TextFileViewerScreen(entry: entry)),
      );
      return;
    }
    final ok = await DownloadService.instance.open(id);
    if (!ok && mounted) await _openInDrive(id);
  }

  Future<void> _openInDrive(String id) async {
    if (id.isEmpty) return;
    final uri = Uri.parse('https://drive.google.com/file/d/$id/view');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _deleteDownload(String id) async {
    await DownloadService.instance.delete(id);
    if (mounted) setState(() => _entries.remove(id));
  }
}

/// Full-screen browser for a nested Drive sub-folder.
class DriveFolderScreen extends StatelessWidget {
  final String folderId, title, courseCode;
  const DriveFolderScreen({
    super.key,
    required this.folderId,
    required this.title,
    required this.courseCode,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Folder'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.folder_rounded,
                  color: Color(0xFFFBBF24),
                  size: 20,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    title,
                    softWrap: true,
                    style: const TextStyle(
                      color: AppColors.textBright,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: DriveFileListView(
              folderId: folderId,
              courseCode: courseCode,
            ),
          ),
        ],
      ),
    );
  }
}
