import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../data/download_service.dart';

/// Lightweight in-app reader for text, notes, and source-code files.
class TextFileViewerScreen extends StatelessWidget {
  final DownloadEntry entry;

  const TextFileViewerScreen({super.key, required this.entry});

  Future<String> _read() async {
    const limit = 2 * 1024 * 1024;
    final file = File(entry.path);
    final length = await file.length();
    final handle = await file.open();
    try {
      final bytes = await handle.read(length > limit ? limit : length);
      final text = utf8.decode(bytes, allowMalformed: true);
      return length > limit ? '$text\n\n— Preview stopped after 2 MB —' : text;
    } finally {
      await handle.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('File reader'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 11),
            decoration: const BoxDecoration(
              color: AppColors.card,
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Text(
              entry.name,
              softWrap: true,
              style: const TextStyle(
                color: AppColors.textBright,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<String>(
              future: _read(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.accent),
                  );
                }
                if (snap.hasError) {
                  return const Center(
                    child: Text(
                      'Could not read this file.',
                      style: TextStyle(color: AppColors.muted),
                    ),
                  );
                }
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(14),
                  child: SelectableText(
                    snap.data ?? '',
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 12.5,
                      height: 1.45,
                      fontFamily: 'monospace',
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
