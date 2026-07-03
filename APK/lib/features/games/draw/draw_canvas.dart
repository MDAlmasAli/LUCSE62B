import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Logical canvas size — identical to the website (800×550) so normalized
/// stroke/fill coordinates map 1:1 between app and web players.
const double kCanvasW = 800;
const double kCanvasH = 550;

class _Seg {
  final double x0, y0, x1, y1;
  final Color color;
  final double size;
  const _Seg(this.x0, this.y0, this.x1, this.y1, this.color, this.size);
}

/// Holds the painted picture for the Draw & Guess board. Live strokes are kept
/// as a cheap vector overlay and periodically rasterised into a [ui.Image]
/// "base" so the flood-fill tool (which needs real pixels) and late-join
/// snapshots work exactly like the web canvas.
class DrawCanvas extends ChangeNotifier {
  ui.Image? _base;
  List<_Seg> _pending = [];
  final List<ui.Image> _history = [];
  bool _disposed = false;

  ui.Image? get base => _base;
  bool get canUndo => _history.isNotEmpty;

  static final Paint _whitePaint = Paint()..color = Colors.white;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> ensureReady() async {
    if (_base == null) await _flatten();
  }

  // ── Live strokes ──
  void addSegment(double x0, double y0, double x1, double y1, Color color, double size) {
    _pending.add(_Seg(x0, y0, x1, y1, color, size));
    if (_pending.length > 600) {
      _flatten(); // fire-and-forget; keeps the overlay bounded
    }
    _notify();
  }

  // ── History / undo ──
  /// Snapshot the current picture (base + pending) for a later undo. Called at
  /// the start of each stroke, like the website's saveHistory().
  Future<void> pushHistory() async {
    await _flatten();
    if (_base != null) {
      _history.add(_base!);
      if (_history.length > 15) _history.removeAt(0);
    }
    _notify();
  }

  /// Undo to the previous snapshot. Returns the new picture as a data-URL so the
  /// caller can broadcast it (matches the web's snapshot-on-undo behaviour).
  Future<String?> undo() async {
    if (_history.isEmpty) return null;
    _base = _history.removeLast();
    _pending = [];
    _notify();
    return snapshotDataUrl();
  }

  // ── Fill ──
  Future<void> fill(int sx, int sy, Color color) async {
    await _flatten();
    final img = _base;
    if (img == null) return;
    final bytes = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (bytes == null) return;
    final data = bytes.buffer.asUint8List();
    _floodFill(data, sx, sy, color);
    _base = await _decode(data);
    _notify();
  }

  static void _floodFill(Uint8List data, int sx, int sy, Color color) {
    const w = 800, h = 550;
    if (sx < 0 || sx >= w || sy < 0 || sy >= h) return;
    final idx = (sy * w + sx) * 4;
    final tr = data[idx], tg = data[idx + 1], tb = data[idx + 2], ta = data[idx + 3];
    final fr = (color.r * 255).round();
    final fg = (color.g * 255).round();
    final fb = (color.b * 255).round();
    if (tr == fr && tg == fg && tb == fb) return;
    final stack = <int>[sx + sy * w];
    final visited = Uint8List(w * h);
    while (stack.isNotEmpty) {
      final pos = stack.removeLast();
      if (visited[pos] == 1) continue;
      visited[pos] = 1;
      final i4 = pos * 4;
      if (data[i4] != tr || data[i4 + 1] != tg || data[i4 + 2] != tb || data[i4 + 3] != ta) {
        continue;
      }
      data[i4] = fr;
      data[i4 + 1] = fg;
      data[i4 + 2] = fb;
      data[i4 + 3] = 255;
      final x = pos % w, y = pos ~/ w;
      if (x > 0) stack.add(pos - 1);
      if (x < w - 1) stack.add(pos + 1);
      if (y > 0) stack.add(pos - w);
      if (y < h - 1) stack.add(pos + w);
    }
  }

  // ── Clear ──
  Future<void> clearLocal() async {
    _pending = [];
    _base = await _white();
    _notify();
  }

  Future<void> clearWithHistory() async {
    await pushHistory();
    await clearLocal();
  }

  // ── Snapshots (late join / undo sync) ──
  Future<String?> snapshotDataUrl() async {
    await _flatten();
    final img = _base;
    if (img == null) return null;
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) return null;
    return 'data:image/png;base64,${base64Encode(png.buffer.asUint8List())}';
  }

  Future<void> applySnapshot(String dataUrl) async {
    try {
      final comma = dataUrl.indexOf(',');
      final b64 = comma >= 0 ? dataUrl.substring(comma + 1) : dataUrl;
      final bytes = base64Decode(b64);
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      _base = frame.image;
      _pending = [];
      _notify();
    } catch (_) {}
  }

  // ── Internals ──
  static void _paintSegs(Canvas canvas, List<_Seg> segs) {
    for (final s in segs) {
      final p = Paint()
        ..color = s.color
        ..strokeWidth = s.size
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(s.x0, s.y0), Offset(s.x1, s.y1), p);
    }
  }

  Future<ui.Image> _white() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(const Rect.fromLTWH(0, 0, kCanvasW, kCanvasH), _whitePaint);
    return recorder.endRecording().toImage(kCanvasW.toInt(), kCanvasH.toInt());
  }

  Future<void> _flatten() async {
    if (_pending.isEmpty && _base != null) return;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    if (_base != null) {
      canvas.drawImage(_base!, Offset.zero, Paint());
    } else {
      canvas.drawRect(const Rect.fromLTWH(0, 0, kCanvasW, kCanvasH), _whitePaint);
    }
    _paintSegs(canvas, _pending);
    final img = await recorder.endRecording().toImage(kCanvasW.toInt(), kCanvasH.toInt());
    _base = img;
    _pending = [];
  }

  Future<ui.Image> _decode(Uint8List rgba) {
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(rgba, 800, 550, ui.PixelFormat.rgba8888, c.complete);
    return c.future;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Paints [DrawCanvas] — the rasterised base plus the live vector overlay.
class DrawCanvasPainter extends CustomPainter {
  final DrawCanvas canvas;
  DrawCanvasPainter(this.canvas) : super(repaint: canvas);

  @override
  void paint(Canvas c, Size size) {
    final sx = size.width / kCanvasW;
    final sy = size.height / kCanvasH;
    final base = canvas.base;
    if (base != null) {
      c.drawImageRect(
        base,
        const Rect.fromLTWH(0, 0, kCanvasW, kCanvasH),
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint(),
      );
    } else {
      c.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), DrawCanvas._whitePaint);
    }
    c.save();
    c.scale(sx, sy);
    DrawCanvas._paintSegs(c, canvas._pending);
    c.restore();
  }

  @override
  bool shouldRepaint(covariant DrawCanvasPainter old) => true;
}
