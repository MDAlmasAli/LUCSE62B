import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/app_colors.dart';

/// Scaffold for a Google-Sheet-backed screen: handles the loading spinner,
/// error + retry, and pull-to-refresh, then hands the parsed rows to [builder].
class SheetScaffold extends StatefulWidget {
  final String title;
  final IconData icon;
  final Future<List<List<String>>> Function() load;
  final Widget Function(List<List<String>> rows) builder;

  const SheetScaffold({
    super.key,
    required this.title,
    required this.icon,
    required this.load,
    required this.builder,
  });

  @override
  State<SheetScaffold> createState() => _SheetScaffoldState();
}

class _SheetScaffoldState extends State<SheetScaffold> {
  late Future<List<List<String>>> _future = widget.load();

  void _reload() => setState(() => _future = widget.load());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(widget.title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/info'),
        ),
      ),
      body: FutureBuilder<List<List<String>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(
                child: CircularProgressIndicator(color: AppColors.accent));
          }
          if (snap.hasError || !snap.hasData) {
            return _error();
          }
          return RefreshIndicator(
            color: AppColors.accent,
            backgroundColor: AppColors.card,
            onRefresh: () async => _reload(),
            child: widget.builder(snap.data!),
          );
        },
      ),
    );
  }

  Widget _error() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.icon, color: AppColors.muted, size: 34),
            const SizedBox(height: 12),
            Text('Unable to load right now.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
            const SizedBox(height: 14),
            OutlinedButton(onPressed: _reload, child: const Text('Retry')),
          ],
        ),
      );
}

/// Centered empty-state used inside a [SheetScaffold] builder.
class SheetEmpty extends StatelessWidget {
  final String message;
  const SheetEmpty({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 120),
        Center(
          child: Text(message,
              style: TextStyle(color: AppColors.muted, fontSize: 14)),
        ),
      ],
    );
  }
}
