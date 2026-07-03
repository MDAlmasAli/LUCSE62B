import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfx/pdfx.dart';

import '../../core/app_colors.dart';
import '../../data/download_service.dart';

class PdfViewerScreen extends StatefulWidget {
  final DownloadEntry entry;
  const PdfViewerScreen({super.key, required this.entry});

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  late final PdfControllerPinch _controller = PdfControllerPinch(
    document: PdfDocument.openFile(widget.entry.path),
  );
  int _page = 1;
  int _count = 0;
  bool _landscape = false;

  @override
  void dispose() {
    _controller.dispose();
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

  Future<void> _askPage() async {
    if (_count < 1) return;
    final input = TextEditingController(text: '$_page');
    final target = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text(
          'Go to page',
          style: TextStyle(color: AppColors.textBright),
        ),
        content: TextField(
          controller: input,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            hintText: '1–$_count',
            suffixText: '/ $_count',
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
    if (target == null || target < 1 || target > _count) return;
    await _controller.animateToPage(
      pageNumber: target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(widget.entry.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Go to page',
            onPressed: _count > 0 ? _askPage : null,
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
      body: Column(
        children: [
          Expanded(
            child: PdfViewPinch(
              controller: _controller,
              backgroundDecoration: const BoxDecoration(color: AppColors.bg),
              onDocumentLoaded: (document) {
                if (mounted) setState(() => _count = document.pagesCount);
              },
              onPageChanged: (page) {
                if (mounted) setState(() => _page = page);
              },
              onDocumentError: (_) {
                if (mounted) setState(() => _count = 0);
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Material(
              color: AppColors.card,
              child: InkWell(
                onTap: _count > 0 ? _askPage : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 11,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.touch_app_outlined,
                        size: 16,
                        color: AppColors.muted,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        _count > 0 ? 'Page $_page of $_count' : 'Loading PDF…',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
