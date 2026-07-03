import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Live progress of an in-flight download (bytes received / total).
class DlProgress {
  final int received;
  final int total;
  final bool paused;
  final bool cancelling;
  const DlProgress(
    this.received,
    this.total, {
    this.paused = false,
    this.cancelling = false,
  });
  double get fraction => total > 0 ? (received / total).clamp(0.0, 1.0) : 0.0;
  bool get known => total > 0;
}

enum DownloadFinish { success, failed, cancelled }

class DownloadResult {
  final DownloadFinish finish;
  final DownloadEntry? entry;
  const DownloadResult._(this.finish, this.entry);
  const DownloadResult.success(DownloadEntry entry)
    : this._(DownloadFinish.success, entry);
  const DownloadResult.failed() : this._(DownloadFinish.failed, null);
  const DownloadResult.cancelled() : this._(DownloadFinish.cancelled, null);
}

class _DownloadTask {
  http.Client? client;
  StreamSubscription<List<int>>? subscription;
  IOSink? sink;
  File? file;
  Completer<void>? streamDone;
  bool pauseRequested = false;
  bool cancelled = false;
}

/// One downloaded file, recorded so it can be re-opened offline.
class DownloadEntry {
  final String fileId, name, path, mime, source;
  final int size;
  final DateTime savedAt;
  const DownloadEntry({
    required this.fileId,
    required this.name,
    required this.path,
    required this.mime,
    required this.source,
    required this.size,
    required this.savedAt,
  });

  Map<String, dynamic> toJson() => {
    'fileId': fileId,
    'name': name,
    'path': path,
    'mime': mime,
    'source': source,
    'size': size,
    'savedAt': savedAt.toIso8601String(),
  };

  static DownloadEntry fromJson(Map<String, dynamic> j) => DownloadEntry(
    fileId: '${j['fileId']}',
    name: '${j['name']}',
    path: '${j['path']}',
    mime: '${j['mime'] ?? ''}',
    source: '${j['source'] ?? ''}',
    size: (j['size'] is int)
        ? j['size'] as int
        : int.tryParse('${j['size']}') ?? 0,
    savedAt: DateTime.tryParse('${j['savedAt']}') ?? DateTime.now(),
  );
}

/// Downloads Google-Drive files into the app's storage and opens them with the
/// device's default viewer (PDF reader, etc.) via `open_filex`. Once saved, a
/// file opens instantly and works fully offline — no re-download, no Drive.
class DownloadService {
  DownloadService._();
  static final instance = DownloadService._();

  static const _indexKey = 'downloads_index_v1';

  /// Live progress of all in-flight downloads, keyed by fileId. Lives on the
  /// singleton (not a widget) so a download keeps running — and stays visible —
  /// even after you leave the screen. UIs listen to this to draw progress bars.
  final ValueNotifier<Map<String, DlProgress>> active = ValueNotifier({});
  final Map<String, _DownloadTask> _tasks = {};

  bool isActive(String fileId) => active.value.containsKey(fileId);

  void _setProgress(String fileId, DlProgress p) {
    active.value = {...active.value, fileId: p};
  }

  void _clearProgress(String fileId) {
    if (!active.value.containsKey(fileId)) return;
    final next = {...active.value}..remove(fileId);
    active.value = next;
  }

  void pause(String fileId) {
    final task = _tasks[fileId];
    final current = active.value[fileId];
    if (task == null || current == null || task.cancelled || current.paused) {
      return;
    }
    task.pauseRequested = true;
    task.subscription?.pause();
    _setProgress(
      fileId,
      DlProgress(current.received, current.total, paused: true),
    );
  }

  void resume(String fileId) {
    final task = _tasks[fileId];
    final current = active.value[fileId];
    if (task == null || current == null || task.cancelled || !current.paused) {
      return;
    }
    task.pauseRequested = false;
    task.subscription?.resume();
    _setProgress(fileId, DlProgress(current.received, current.total));
  }

  Future<void> cancel(String fileId) async {
    final task = _tasks[fileId];
    final current = active.value[fileId];
    if (task == null) return;
    task.cancelled = true;
    if (current != null) {
      _setProgress(
        fileId,
        DlProgress(current.received, current.total, cancelling: true),
      );
    }
    await task.subscription?.cancel();
    task.client?.close();
    try {
      await task.sink?.close();
    } catch (_) {}
    final done = task.streamDone;
    if (done != null && !done.isCompleted) done.complete();
  }

  Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/downloads');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<Map<String, dynamic>> _index() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_indexKey);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveIndex(Map<String, dynamic> idx) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_indexKey, jsonEncode(idx));
  }

  /// Ids of everything currently downloaded (and still present on disk).
  Future<Set<String>> downloadedIds() async {
    final idx = await _index();
    final out = <String>{};
    for (final e in idx.entries) {
      final p = (e.value as Map)['path']?.toString() ?? '';
      if (p.isNotEmpty && await File(p).exists()) out.add(e.key);
    }
    return out;
  }

  Future<DownloadEntry?> entry(String fileId) async {
    final idx = await _index();
    final e = idx[fileId];
    if (e == null) return null;
    final ent = DownloadEntry.fromJson((e as Map).cast<String, dynamic>());
    if (!await File(ent.path).exists()) return null;
    return ent;
  }

  Future<bool> isDownloaded(String fileId) async =>
      (await entry(fileId)) != null;

  /// Download [fileId] from Drive to local storage. Returns the saved entry, or
  /// null if it failed (e.g. a very large file that hits Drive's confirm page).
  Future<DownloadResult> download(
    String fileId,
    String name, {
    String mime = '',
    String source = '',
    void Function(double progress)? onProgress,
  }) async {
    // Already downloading this file → don't start a second stream.
    if (isActive(fileId)) return const DownloadResult.failed();
    final task = _DownloadTask();
    _tasks[fileId] = task;
    _setProgress(fileId, const DlProgress(0, 0));
    try {
      final dir = await _dir();
      if (task.cancelled) return const DownloadResult.cancelled();
      final exported = _exportMeta(fileId, name, mime);
      final safe = _ensureExt(
        _sanitize(exported.name.isEmpty ? fileId : exported.name),
        exported.mime,
      );
      final file = File('${dir.path}/${fileId}__$safe');
      final client = http.Client();
      task
        ..client = client
        ..file = file;
      try {
        final resp = await client
            .send(http.Request('GET', Uri.parse(exported.url)))
            .timeout(const Duration(seconds: 90));
        if (task.cancelled) return const DownloadResult.cancelled();
        if (resp.statusCode != 200) return const DownloadResult.failed();
        // A virus-scan / confirm interstitial comes back as HTML, not the file.
        final ct = (resp.headers['content-type'] ?? '').toLowerCase();
        final isHtmlFile =
            exported.mime.toLowerCase().startsWith('text/html') ||
            RegExp(r'\.html?$', caseSensitive: false).hasMatch(exported.name);
        if (ct.contains('text/html') && !isHtmlFile) {
          return const DownloadResult.failed();
        }
        final total = resp.contentLength ?? 0;
        final sink = file.openWrite();
        task.sink = sink;
        var received = 0;
        _setProgress(fileId, DlProgress(0, total));
        final streamDone = Completer<void>();
        task.streamDone = streamDone;
        task.subscription = resp.stream.listen(
          (chunk) {
            if (task.cancelled) return;
            sink.add(chunk);
            received += chunk.length;
            _setProgress(
              fileId,
              DlProgress(received, total, paused: task.pauseRequested),
            );
            if (total > 0) onProgress?.call(received / total);
          },
          onError: (Object error, StackTrace stack) {
            if (!streamDone.isCompleted) {
              streamDone.completeError(error, stack);
            }
          },
          onDone: () {
            if (!streamDone.isCompleted) streamDone.complete();
          },
          cancelOnError: true,
        );
        if (task.pauseRequested) task.subscription?.pause();
        await streamDone.future;
        if (task.cancelled) {
          try {
            await sink.close();
          } catch (_) {}
          try {
            if (await file.exists()) await file.delete();
          } catch (_) {}
          return const DownloadResult.cancelled();
        }
        await sink.flush();
        await sink.close();
        if (received == 0) {
          try {
            await file.delete();
          } catch (_) {}
          return const DownloadResult.failed();
        }
        final ent = DownloadEntry(
          fileId: fileId,
          name: exported.name,
          path: file.path,
          mime: exported.mime,
          source: source,
          size: received,
          savedAt: DateTime.now(),
        );
        final idx = await _index();
        idx[fileId] = ent.toJson();
        await _saveIndex(idx);
        return DownloadResult.success(ent);
      } finally {
        client.close();
      }
    } catch (_) {
      if (task.cancelled) {
        try {
          final file = task.file;
          if (file != null && await file.exists()) await file.delete();
        } catch (_) {}
        return const DownloadResult.cancelled();
      }
      return const DownloadResult.failed();
    } finally {
      _tasks.remove(fileId);
      _clearProgress(fileId);
    }
  }

  /// Save raw bytes we generated in-app (e.g. an exported routine PDF/PNG) into
  /// the downloads store so it opens with the device viewer and shows up in the
  /// Downloads list. A stable [fileId] lets a re-export overwrite the old copy.
  Future<DownloadEntry?> saveBytes(
    String fileId,
    String name,
    List<int> bytes, {
    String mime = '',
    String source = '',
  }) async {
    try {
      final dir = await _dir();
      final safe = _ensureExt(_sanitize(name.isEmpty ? fileId : name), mime);
      final file = File('${dir.path}/${fileId}__$safe');
      await file.writeAsBytes(bytes, flush: true);
      final ent = DownloadEntry(
        fileId: fileId,
        name: safe,
        path: file.path,
        mime: mime,
        source: source,
        size: bytes.length,
        savedAt: DateTime.now(),
      );
      final idx = await _index();
      idx[fileId] = ent.toJson();
      await _saveIndex(idx);
      return ent;
    } catch (_) {
      return null;
    }
  }

  /// Open an already-downloaded file with the device's default app.
  Future<bool> open(String fileId) async {
    final ent = await entry(fileId);
    if (ent == null) return false;
    final r = await OpenFilex.open(ent.path);
    return r.type == ResultType.done;
  }

  Future<List<DownloadEntry>> list() async {
    final idx = await _index();
    final out = <DownloadEntry>[];
    for (final e in idx.values) {
      try {
        final ent = DownloadEntry.fromJson((e as Map).cast<String, dynamic>());
        if (await File(ent.path).exists()) out.add(ent);
      } catch (_) {}
    }
    out.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return out;
  }

  Future<void> delete(String fileId) async {
    final idx = await _index();
    final e = idx.remove(fileId);
    if (e != null) {
      try {
        await File((e as Map)['path'].toString()).delete();
      } catch (_) {}
      await _saveIndex(idx);
    }
  }

  static String _sanitize(String name) => name
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
      .replaceAll(RegExp(r'[. ]+$'), '')
      .trim();

  static String _ensureExt(String name, String mime) {
    if (RegExp(r'\.[A-Za-z0-9]{1,10}$').hasMatch(name)) return name;
    final ext = _extFor(mime);
    return ext.isEmpty ? name : '$name.$ext';
  }

  static String _extFor(String mime) {
    final m = mime.toLowerCase();
    if (m == 'application/pdf') return 'pdf';
    if (m.contains('presentation') || m.contains('powerpoint')) return 'pptx';
    if (m.contains('word') || m.contains('document')) return 'docx';
    if (m.contains('sheet') || m.contains('excel')) return 'xlsx';
    if (m.startsWith('image/')) return m.split('/').last;
    if (m.contains('zip')) return 'zip';
    if (m.startsWith('video/')) return 'mp4';
    if (m.startsWith('audio/')) return 'mp3';
    if (m.startsWith('text/')) return 'txt';
    return '';
  }

  static ({String url, String name, String mime}) _exportMeta(
    String fileId,
    String name,
    String mime,
  ) {
    final id = Uri.encodeComponent(fileId);
    final m = mime.toLowerCase();
    if (m == 'application/vnd.google-apps.document') {
      return (
        url: 'https://docs.google.com/document/d/$id/export?format=pdf',
        name: _exportName(name, 'pdf'),
        mime: 'application/pdf',
      );
    }
    if (m == 'application/vnd.google-apps.presentation') {
      const outMime =
          'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      return (
        url: 'https://docs.google.com/presentation/d/$id/export/pptx',
        name: _exportName(name, 'pptx'),
        mime: outMime,
      );
    }
    if (m == 'application/vnd.google-apps.spreadsheet') {
      const outMime =
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      return (
        url: 'https://docs.google.com/spreadsheets/d/$id/export?format=xlsx',
        name: _exportName(name, 'xlsx'),
        mime: outMime,
      );
    }
    if (m == 'application/vnd.google-apps.drawing') {
      return (
        url: 'https://docs.google.com/drawings/d/$id/export/png',
        name: _exportName(name, 'png'),
        mime: 'image/png',
      );
    }
    return (
      url:
          'https://drive.usercontent.google.com/download?id=$id&export=download&confirm=t',
      name: name,
      mime: mime,
    );
  }

  static String _exportName(String name, String extension) {
    final base = name.trim().isEmpty ? 'file' : name.trim();
    return base.toLowerCase().endsWith('.$extension')
        ? base
        : '$base.$extension';
  }

  /// Plain-text and source-code files that can be read without another app.
  static bool isReadableText(String name, String mime) {
    if (mime.toLowerCase().startsWith('text/')) return true;
    final dot = name.lastIndexOf('.');
    final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
    const extensions = {
      'txt',
      'md',
      'log',
      'csv',
      'json',
      'xml',
      'yaml',
      'yml',
      'c',
      'cpp',
      'cc',
      'h',
      'hpp',
      'java',
      'py',
      'js',
      'jsx',
      'ts',
      'tsx',
      'dart',
      'kt',
      'kts',
      'cs',
      'go',
      'rb',
      'php',
      'swift',
      'rs',
      'sql',
      'html',
      'htm',
      'css',
      'scss',
      'sh',
      'bash',
      'ps1',
      'bat',
      'ini',
      'toml',
      'gradle',
      'properties',
      'r',
      'm',
    };
    return extensions.contains(ext);
  }

  static bool isPptx(String name, String mime) {
    final lower = name.toLowerCase();
    final m = mime.toLowerCase();
    return lower.endsWith('.pptx') ||
        m ==
            'application/vnd.openxmlformats-officedocument.presentationml.presentation';
  }

  static bool isPdf(String name, String mime) =>
      name.toLowerCase().endsWith('.pdf') ||
      mime.toLowerCase() == 'application/pdf';

  /// Human-readable size, e.g. "2.4 MB".
  static String prettySize(int bytes) {
    if (bytes <= 0) return '';
    const units = ['B', 'KB', 'MB', 'GB'];
    var v = bytes.toDouble();
    var u = 0;
    while (v >= 1024 && u < units.length - 1) {
      v /= 1024;
      u++;
    }
    return '${v.toStringAsFixed(v < 10 && u > 0 ? 1 : 0)} ${units[u]}';
  }
}
