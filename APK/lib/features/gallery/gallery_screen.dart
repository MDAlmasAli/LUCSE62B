import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_colors.dart';
import '../../core/constants.dart';
import '../../core/worker_api.dart';

/// Class gallery — event folders from the Drive gallery (via Worker `/gallery`).
/// Like the website: the landing view shows folder cards with a cover preview;
/// tapping a folder opens that album's photo grid, and tapping a photo opens a
/// zoomable fullscreen viewer.
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  late Future<List<_Album>> _future = _load();

  Future<List<_Album>> _load() async {
    final files = await WorkerApi.instance.gallery(K.galleryFolderId);
    final byFolder = <String, List<String>>{};
    for (final f in files) {
      final id = (f['id'] ?? '').toString();
      final folder = (f['folder'] ?? 'Photos').toString();
      if (id.isEmpty) continue;
      byFolder.putIfAbsent(folder, () => []).add(id);
    }
    final albums = byFolder.entries
        .map((e) => _Album(name: e.key, ids: e.value))
        .toList();
    // Keep folders with photos first; stable otherwise.
    albums.sort((a, b) => b.ids.length.compareTo(a.ids.length));
    return albums;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Gallery'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
      ),
      body: FutureBuilder<List<_Album>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: AppColors.accent));
          }
          final albums = snap.data ?? const <_Album>[];
          if (albums.isEmpty) {
            return _empty();
          }
          return RefreshIndicator(
            color: AppColors.accent,
            backgroundColor: AppColors.card,
            onRefresh: () async => setState(() => _future = _load()),
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 0.82,
              ),
              itemCount: albums.length,
              itemBuilder: (_, i) => _folderCard(albums[i]),
            ),
          );
        },
      ),
    );
  }

  Widget _empty() => ListView(
        children: [
          SizedBox(height: 120),
          Icon(Icons.photo_library_outlined, color: AppColors.muted, size: 40),
          SizedBox(height: 12),
          Center(
            child: Text('No event albums yet.',
                style: TextStyle(color: AppColors.muted, fontSize: 14)),
          ),
        ],
      );

  Widget _folderCard(_Album album) {
    final cover = album.ids.isNotEmpty ? album.ids.first : null;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _AlbumScreen(album: album),
      )),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (cover != null)
                      CachedNetworkImage(
                        imageUrl: K.driveImage(cover, 400),
                        fit: BoxFit.cover,
                        placeholder: (_, _) => Container(color: AppColors.cardElevated),
                        errorWidget: (_, _, _) => _coverPlaceholder(),
                      )
                    else
                      _coverPlaceholder(),
                    // Bottom gradient so the count chip reads on any photo.
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Colors.black.withValues(alpha: 0.55), Colors.transparent],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.photo_rounded, size: 12, color: Colors.white),
                            const SizedBox(width: 4),
                            Text('${album.ids.length}',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(album.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: AppColors.textBright,
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.folder_open_rounded, size: 11, color: AppColors.accentBright),
                        SizedBox(width: 4),
                        Text('Tap to view photos',
                            style: TextStyle(color: AppColors.muted, fontSize: 11)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _coverPlaceholder() => Container(
        color: AppColors.cardElevated,
        child: Icon(Icons.photo_library_rounded, color: AppColors.muted, size: 30),
      );
}

class _Album {
  final String name;
  final List<String> ids;
  const _Album({required this.name, required this.ids});
}

/// A single event album's photo grid.
class _AlbumScreen extends StatelessWidget {
  final _Album album;
  const _AlbumScreen({required this.album});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(album.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(
              child: Text('${album.ids.length} photos',
                  style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
            ),
          ),
        ],
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
        ),
        itemCount: album.ids.length,
        itemBuilder: (_, i) {
          final id = album.ids[i];
          return GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => _PhotoViewer(ids: album.ids, initialIndex: i),
              fullscreenDialog: true,
            )),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: K.driveImage(id, 400),
                fit: BoxFit.cover,
                placeholder: (_, _) => Container(color: AppColors.cardElevated),
                errorWidget: (_, _, _) => Container(
                  color: AppColors.cardElevated,
                  child: Icon(Icons.broken_image_outlined,
                      color: AppColors.muted, size: 20),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PhotoViewer extends StatefulWidget {
  final List<String> ids;
  final int initialIndex;
  const _PhotoViewer({required this.ids, required this.initialIndex});

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final PageController _ctrl = PageController(initialPage: widget.initialIndex);
  late int _current = widget.initialIndex;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_current + 1} / ${widget.ids.length}',
            style: const TextStyle(fontSize: 14)),
      ),
      body: PageView.builder(
        controller: _ctrl,
        itemCount: widget.ids.length,
        onPageChanged: (i) => setState(() => _current = i),
        itemBuilder: (_, i) => InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Center(
            child: CachedNetworkImage(
              imageUrl: K.driveImage(widget.ids[i], 1080),
              fit: BoxFit.contain,
              placeholder: (_, _) => Center(
                  child: CircularProgressIndicator(color: AppColors.accent)),
              errorWidget: (_, _, _) =>
                  const Icon(Icons.broken_image_outlined, color: Colors.white38, size: 40),
            ),
          ),
        ),
      ),
    );
  }
}
