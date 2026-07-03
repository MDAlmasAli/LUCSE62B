import 'dart:async';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xml/xml.dart';

import '../../core/app_colors.dart';
import '../../data/download_service.dart';

class _PptxElement {
  final String kind;
  final String text;
  final Uint8List? image;
  final double x, y, width, height, fontSize;
  final int color, fill;
  final bool bold;
  final TextAlign align;

  const _PptxElement({
    required this.kind,
    required this.text,
    required this.image,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.fontSize,
    required this.color,
    required this.fill,
    required this.bold,
    required this.align,
  });

  factory _PptxElement.fromMap(Map<Object?, Object?> map) => _PptxElement(
    kind: '${map['kind']}',
    text: '${map['text'] ?? ''}',
    image: map['image'] as Uint8List?,
    x: (map['x'] as num).toDouble(),
    y: (map['y'] as num).toDouble(),
    width: (map['w'] as num).toDouble(),
    height: (map['h'] as num).toDouble(),
    fontSize: (map['fontSize'] as num).toDouble(),
    color: map['color'] as int,
    fill: map['fill'] as int,
    bold: map['bold'] == true,
    align: switch (map['align']) {
      'center' => TextAlign.center,
      'right' => TextAlign.right,
      'justify' => TextAlign.justify,
      _ => TextAlign.left,
    },
  );
}

class _PptxSlide {
  final int background;
  final List<_PptxElement> elements;
  const _PptxSlide(this.background, this.elements);
}

class _PptxDeck {
  final double aspectRatio;
  final List<_PptxSlide> slides;
  const _PptxDeck(this.aspectRatio, this.slides);
}

Future<Map<String, Object>> _parsePptxFile(String path) async {
  final input = InputFileStream(path);
  try {
    final archive = ZipDecoder().decodeStream(input, verify: true);
    final files = <String, ArchiveFile>{
      for (final file in archive.files) file.name.replaceAll('\\', '/'): file,
    };

    var slideWidth = 12192000.0;
    var slideHeight = 6858000.0;
    final presentation = _xml(files, 'ppt/presentation.xml');
    final size = presentation?.descendants
        .whereType<XmlElement>()
        .where((node) => node.name.local == 'sldSz')
        .firstOrNull;
    slideWidth = _number(size?.getAttribute('cx'), slideWidth);
    slideHeight = _number(size?.getAttribute('cy'), slideHeight);

    final slideFiles =
        files.keys
            .where(
              (name) => RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(name),
            )
            .toList()
          ..sort((a, b) => _slideNumber(a).compareTo(_slideNumber(b)));

    final slides = <Map<String, Object>>[];
    for (final slidePath in slideFiles) {
      final slide = _xml(files, slidePath);
      if (slide == null) continue;
      final rels = _relationships(
        files,
        'ppt/slides/_rels/${slidePath.split('/').last}.rels',
      );
      final layoutTarget = rels.values
          .where((rel) => rel.type.endsWith('/slideLayout'))
          .firstOrNull
          ?.target;
      final layoutPath = layoutTarget == null
          ? null
          : _resolveZipPath('ppt/slides', layoutTarget);
      final layout = layoutPath == null ? null : _xml(files, layoutPath);
      final placeholders = _placeholderGeometry(layout);

      final elements = <Map<String, Object>>[];
      final tree = slide.descendants
          .whereType<XmlElement>()
          .where((node) => node.name.local == 'spTree')
          .firstOrNull;
      if (tree != null) {
        for (final node in tree.childElements) {
          switch (node.name.local) {
            case 'sp':
            case 'cxnSp':
              final parsed = _shape(
                node,
                placeholders,
                slideWidth,
                slideHeight,
              );
              if (parsed != null) elements.add(parsed);
            case 'pic':
              final parsed = _picture(
                node,
                rels,
                files,
                slideWidth,
                slideHeight,
              );
              if (parsed != null) elements.add(parsed);
            case 'graphicFrame':
              final parsed = _table(node, slideWidth, slideHeight);
              if (parsed != null) elements.add(parsed);
          }
        }
      }
      slides.add({
        'background': _background(slide, layout),
        'elements': elements,
      });
    }
    return {'aspectRatio': slideWidth / slideHeight, 'slides': slides};
  } finally {
    input.closeSync();
  }
}

XmlDocument? _xml(Map<String, ArchiveFile> files, String path) {
  final bytes = files[path]?.readBytes();
  if (bytes == null) return null;
  try {
    return XmlDocument.parse(utf8.decode(bytes, allowMalformed: true));
  } catch (_) {
    return null;
  }
}

typedef _Relationship = ({String target, String type});

Map<String, _Relationship> _relationships(
  Map<String, ArchiveFile> files,
  String path,
) {
  final doc = _xml(files, path);
  if (doc == null) return {};
  return {
    for (final node in doc.descendants.whereType<XmlElement>())
      if (node.name.local == 'Relationship' &&
          node.getAttribute('Id') != null &&
          node.getAttribute('Target') != null)
        node.getAttribute('Id')!: (
          target: node.getAttribute('Target')!,
          type: node.getAttribute('Type') ?? '',
        ),
  };
}

Map<String, ({double x, double y, double w, double h})> _placeholderGeometry(
  XmlDocument? layout,
) {
  if (layout == null) return {};
  final result = <String, ({double x, double y, double w, double h})>{};
  for (final shape in layout.descendants.whereType<XmlElement>().where(
    (node) => node.name.local == 'sp',
  )) {
    final key = _placeholderKey(shape);
    final geometry = _geometry(shape);
    if (key != null && geometry != null) {
      result[key] = geometry;
      result['idx:${key.split(':').last}'] = geometry;
    }
  }
  return result;
}

Map<String, Object>? _shape(
  XmlElement shape,
  Map<String, ({double x, double y, double w, double h})> placeholders,
  double slideWidth,
  double slideHeight,
) {
  final paragraphs = shape.descendants
      .whereType<XmlElement>()
      .where((node) => node.name.local == 'p')
      .map(
        (paragraph) => paragraph.descendants
            .whereType<XmlElement>()
            .where((node) => node.name.local == 't')
            .map((node) => node.innerText)
            .join(),
      )
      .where((text) => text.trim().isNotEmpty)
      .toList();
  if (paragraphs.isEmpty) return null;

  final key = _placeholderKey(shape);
  final placeholderType = key?.split(':').first ?? '';
  final geometry =
      _geometry(shape) ??
      (key == null ? null : placeholders[key]) ??
      (key == null ? null : placeholders['idx:${key.split(':').last}']) ??
      _defaultGeometry(placeholderType);
  final runProps = shape.descendants
      .whereType<XmlElement>()
      .where(
        (node) =>
            node.name.local == 'rPr' ||
            node.name.local == 'defRPr' ||
            node.name.local == 'endParaRPr',
      )
      .firstOrNull;
  final paragraphProps = shape.descendants
      .whereType<XmlElement>()
      .where((node) => node.name.local == 'pPr')
      .firstOrNull;
  final size = _number(
    runProps?.getAttribute('sz'),
    placeholderType.contains('title') || placeholderType == 'ctrTitle'
        ? 2800
        : 1800,
  );
  final spPr = _direct(shape, 'spPr');
  final fill = _solidColor(spPr, fallback: 0x00000000);
  final textColor = _solidColor(runProps, fallback: 0xFF111827);
  return {
    'kind': 'text',
    'text': paragraphs.join('\n'),
    'x': (geometry.x / slideWidth).clamp(0.0, 1.0),
    'y': (geometry.y / slideHeight).clamp(0.0, 1.0),
    'w': (geometry.w / slideWidth).clamp(0.01, 1.0),
    'h': (geometry.h / slideHeight).clamp(0.01, 1.0),
    'fontSize': size / 100,
    'color': textColor,
    'fill': fill,
    'bold': runProps?.getAttribute('b') == '1',
    'align': switch (paragraphProps?.getAttribute('algn')) {
      'ctr' => 'center',
      'r' => 'right',
      'just' => 'justify',
      _ => 'left',
    },
  };
}

Map<String, Object>? _picture(
  XmlElement picture,
  Map<String, _Relationship> rels,
  Map<String, ArchiveFile> files,
  double slideWidth,
  double slideHeight,
) {
  final blip = picture.descendants
      .whereType<XmlElement>()
      .where((node) => node.name.local == 'blip')
      .firstOrNull;
  final relationshipId =
      blip?.getAttribute('embed') ??
      blip?.attributes
          .where((attr) => attr.name.local == 'embed')
          .firstOrNull
          ?.value;
  final target = relationshipId == null ? null : rels[relationshipId]?.target;
  final geometry = _geometry(picture);
  if (target == null || geometry == null) return null;
  final bytes = files[_resolveZipPath('ppt/slides', target)]?.readBytes();
  if (bytes == null) return null;
  return {
    'kind': 'image',
    'text': '',
    'image': bytes,
    'x': (geometry.x / slideWidth).clamp(0.0, 1.0),
    'y': (geometry.y / slideHeight).clamp(0.0, 1.0),
    'w': (geometry.w / slideWidth).clamp(0.01, 1.0),
    'h': (geometry.h / slideHeight).clamp(0.01, 1.0),
    'fontSize': 12.0,
    'color': 0xFF111827,
    'fill': 0x00000000,
    'bold': false,
    'align': 'left',
  };
}

Map<String, Object>? _table(
  XmlElement frame,
  double slideWidth,
  double slideHeight,
) {
  final geometry = _geometry(frame);
  if (geometry == null) return null;
  final rows = frame.descendants
      .whereType<XmlElement>()
      .where((node) => node.name.local == 'tr')
      .map(
        (row) => row.childElements
            .where((node) => node.name.local == 'tc')
            .map(
              (cell) => cell.descendants
                  .whereType<XmlElement>()
                  .where((node) => node.name.local == 't')
                  .map((node) => node.innerText)
                  .join(),
            )
            .join('   |   '),
      )
      .where((row) => row.trim().isNotEmpty)
      .toList();
  if (rows.isEmpty) return null;
  return {
    'kind': 'text',
    'text': rows.join('\n'),
    'x': (geometry.x / slideWidth).clamp(0.0, 1.0),
    'y': (geometry.y / slideHeight).clamp(0.0, 1.0),
    'w': (geometry.w / slideWidth).clamp(0.01, 1.0),
    'h': (geometry.h / slideHeight).clamp(0.01, 1.0),
    'fontSize': 14.0,
    'color': 0xFF111827,
    'fill': 0x33FFFFFF,
    'bold': false,
    'align': 'left',
  };
}

({double x, double y, double w, double h})? _geometry(XmlElement node) {
  final xfrm = node.descendants
      .whereType<XmlElement>()
      .where((element) => element.name.local == 'xfrm')
      .firstOrNull;
  if (xfrm == null) return null;
  final off = xfrm.childElements
      .where((element) => element.name.local == 'off')
      .firstOrNull;
  final ext = xfrm.childElements
      .where((element) => element.name.local == 'ext')
      .firstOrNull;
  if (off == null || ext == null) return null;
  return (
    x: _number(off.getAttribute('x'), 0),
    y: _number(off.getAttribute('y'), 0),
    w: _number(ext.getAttribute('cx'), 1),
    h: _number(ext.getAttribute('cy'), 1),
  );
}

({double x, double y, double w, double h}) _defaultGeometry(String type) {
  if (type == 'title' || type == 'ctrTitle') {
    return (x: 900000, y: 420000, w: 10300000, h: 1250000);
  }
  if (type == 'subTitle') {
    return (x: 1200000, y: 2200000, w: 9700000, h: 2100000);
  }
  return (x: 900000, y: 1750000, w: 10300000, h: 4400000);
}

String? _placeholderKey(XmlElement shape) {
  final placeholder = shape.descendants
      .whereType<XmlElement>()
      .where((node) => node.name.local == 'ph')
      .firstOrNull;
  if (placeholder == null) return null;
  return '${placeholder.getAttribute('type') ?? 'body'}:${placeholder.getAttribute('idx') ?? '0'}';
}

int _background(XmlDocument slide, XmlDocument? layout) {
  final slideBackground = slide.descendants
      .whereType<XmlElement>()
      .where((node) => node.name.local == 'bgPr')
      .firstOrNull;
  if (slideBackground != null) {
    return _solidColor(slideBackground, fallback: 0xFFFFFFFF);
  }
  final layoutBackground = layout?.descendants
      .whereType<XmlElement>()
      .where((node) => node.name.local == 'bgPr')
      .firstOrNull;
  return _solidColor(layoutBackground, fallback: 0xFFFFFFFF);
}

int _solidColor(XmlElement? parent, {required int fallback}) {
  if (parent == null) return fallback;
  final solidFill = parent.descendants
      .whereType<XmlElement>()
      .where((node) => node.name.local == 'solidFill')
      .firstOrNull;
  if (solidFill == null) return fallback;
  final rgb = solidFill.descendants
      .whereType<XmlElement>()
      .where((node) => node.name.local == 'srgbClr')
      .firstOrNull
      ?.getAttribute('val');
  if (rgb != null && rgb.length == 6) {
    return 0xFF000000 | (int.tryParse(rgb, radix: 16) ?? 0);
  }
  final scheme = solidFill.descendants
      .whereType<XmlElement>()
      .where((node) => node.name.local == 'schemeClr')
      .firstOrNull
      ?.getAttribute('val');
  return switch (scheme) {
    'dk1' || 'tx1' => 0xFF111827,
    'dk2' || 'tx2' => 0xFF334155,
    'lt1' || 'bg1' => 0xFFFFFFFF,
    'lt2' || 'bg2' => 0xFFF1F5F9,
    'accent1' => 0xFF4472C4,
    'accent2' => 0xFFED7D31,
    'accent3' => 0xFFA5A5A5,
    'accent4' => 0xFFFFC000,
    'accent5' => 0xFF5B9BD5,
    'accent6' => 0xFF70AD47,
    _ => fallback,
  };
}

XmlElement? _direct(XmlElement parent, String localName) => parent.childElements
    .where((element) => element.name.local == localName)
    .firstOrNull;

double _number(String? value, double fallback) =>
    double.tryParse(value ?? '') ?? fallback;

int _slideNumber(String path) =>
    int.tryParse(
      RegExp(r'slide(\d+)\.xml$').firstMatch(path)?.group(1) ?? '',
    ) ??
    0;

String _resolveZipPath(String base, String target) {
  final parts = <String>[
    if (!target.startsWith('/')) ...base.split('/'),
    ...target.replaceFirst(RegExp(r'^/+'), '').split('/'),
  ];
  final normalized = <String>[];
  for (final part in parts) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (normalized.isNotEmpty) normalized.removeLast();
    } else {
      normalized.add(part);
    }
  }
  return normalized.join('/');
}

class PptxViewerScreen extends StatefulWidget {
  final DownloadEntry entry;
  const PptxViewerScreen({super.key, required this.entry});

  @override
  State<PptxViewerScreen> createState() => _PptxViewerScreenState();
}

class _PptxViewerScreenState extends State<PptxViewerScreen> {
  late final Future<_PptxDeck> _deck = _load();
  final PageController _pages = PageController();
  int _current = 0;
  bool _landscape = false;

  Future<_PptxDeck> _load() async {
    final parsed = await compute(_parsePptxFile, widget.entry.path);
    final slides = (parsed['slides'] as List)
        .cast<Map<Object?, Object?>>()
        .map(
          (slide) => _PptxSlide(
            slide['background'] as int,
            (slide['elements'] as List)
                .cast<Map<Object?, Object?>>()
                .map(_PptxElement.fromMap)
                .toList(),
          ),
        )
        .toList();
    return _PptxDeck((parsed['aspectRatio'] as num).toDouble(), slides);
  }

  @override
  void dispose() {
    _pages.dispose();
    unawaited(SystemChrome.setPreferredOrientations(DeviceOrientation.values));
    super.dispose();
  }

  Future<void> _toggleLandscape() async {
    final next = !_landscape;
    await SystemChrome.setPreferredOrientations(
      next
          ? const [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]
          : DeviceOrientation.values,
    );
    if (mounted) setState(() => _landscape = next);
  }

  Future<void> _askSlide(int count) async {
    final input = TextEditingController(text: '${_current + 1}');
    final target = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text(
          'Go to slide',
          style: TextStyle(color: AppColors.textBright),
        ),
        content: TextField(
          controller: input,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            hintText: '1–$count',
            suffixText: '/ $count',
          ),
          onSubmitted: (value) =>
              Navigator.of(context).pop(int.tryParse(value)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(int.tryParse(input.text)),
            child: const Text('Go'),
          ),
        ],
      ),
    );
    input.dispose();
    if (target == null || target < 1 || target > count) return;
    await _pages.animateToPage(
      target - 1,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_PptxDeck>(
      future: _deck,
      builder: (context, snap) {
        final deck = snap.data;
        final count = deck?.slides.length ?? 0;
        return Scaffold(
          backgroundColor: AppColors.bg,
          appBar: AppBar(
            title: Text(widget.entry.name, overflow: TextOverflow.ellipsis),
            actions: [
              IconButton(
                tooltip: 'Go to slide',
                onPressed: count > 0 ? () => _askSlide(count) : null,
                icon: const Icon(Icons.pin_drop_outlined),
              ),
              IconButton(
                tooltip: _landscape ? 'Auto rotate' : 'Landscape view',
                onPressed: _toggleLandscape,
                icon: Icon(
                  _landscape
                      ? Icons.screen_rotation_alt_rounded
                      : Icons.screen_rotation_rounded,
                ),
              ),
            ],
          ),
          body: _body(snap),
        );
      },
    );
  }

  Widget _body(AsyncSnapshot<_PptxDeck> snap) {
    if (snap.connectionState == ConnectionState.waiting) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      );
    }
    final deck = snap.data;
    if (snap.hasError || deck == null || deck.slides.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Text(
            'This presentation could not be read.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 14),
          ),
        ),
      );
    }
    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _pages,
            itemCount: deck.slides.length,
            onPageChanged: (page) => setState(() => _current = page),
            itemBuilder: (_, index) =>
                _slide(deck.slides[index], deck.aspectRatio),
          ),
        ),
        _pager(deck.slides.length),
      ],
    );
  }

  Widget _slide(_PptxSlide slide, double aspectRatio) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: InteractiveViewer(
        minScale: 0.75,
        maxScale: 5,
        child: Center(
          child: AspectRatio(
            aspectRatio: aspectRatio,
            child: LayoutBuilder(
              builder: (context, box) => Container(
                clipBehavior: Clip.hardEdge,
                decoration: BoxDecoration(
                  color: Color(slide.background),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    for (final element in slide.elements)
                      Positioned(
                        left: element.x * box.maxWidth,
                        top: element.y * box.maxHeight,
                        width: element.width * box.maxWidth,
                        height: element.height * box.maxHeight,
                        child: _element(element, box.maxWidth),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _element(_PptxElement element, double canvasWidth) {
    if (element.kind == 'image' && element.image != null) {
      return Image.memory(
        element.image!,
        fit: BoxFit.fill,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      );
    }
    final fontSize = (element.fontSize * canvasWidth / 960).clamp(5.0, 64.0);
    return ColoredBox(
      color: Color(element.fill),
      child: ClipRect(
        child: Align(
          alignment: switch (element.align) {
            TextAlign.center => Alignment.center,
            TextAlign.right => Alignment.centerRight,
            _ => Alignment.centerLeft,
          },
          child: Text(
            element.text,
            textAlign: element.align,
            softWrap: true,
            style: TextStyle(
              color: Color(element.color),
              fontSize: fontSize,
              height: 1.08,
              fontWeight: element.bold ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }

  Widget _pager(int count) => SafeArea(
    top: false,
    child: Material(
      color: AppColors.card,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Previous slide',
              onPressed: _current > 0
                  ? () => _pages.previousPage(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                    )
                  : null,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: InkWell(
                onTap: () => _askSlide(count),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Text(
                    'Slide ${_current + 1} of $count · tap to jump',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Next slide',
              onPressed: _current < count - 1
                  ? () => _pages.nextPage(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                    )
                  : null,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
      ),
    ),
  );
}
