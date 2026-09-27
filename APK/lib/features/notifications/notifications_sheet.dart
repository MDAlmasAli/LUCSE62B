import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/app_colors.dart';
import '../../data/models/app_notification.dart';

/// Bottom sheet listing notifications — the mobile equivalent of the web
/// notification dropdown.
class NotificationsSheet extends StatelessWidget {
  final List<AppNotification> items;
  const NotificationsSheet({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.muted,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
                child: Row(
                  children: [
                    Icon(Icons.notifications,
                        color: AppColors.accentBright, size: 18),
                    const SizedBox(width: 8),
                    Text('Notifications',
                        style: TextStyle(
                            color: AppColors.text,
                            fontWeight: FontWeight.w700,
                            fontSize: 15)),
                    const Spacer(),
                    Text('${items.length}',
                        style: TextStyle(
                            color: AppColors.muted, fontSize: 13)),
                  ],
                ),
              ),
              Divider(height: 1, color: AppColors.border),
              Expanded(
                child: items.isEmpty
                    ? _empty()
                    : ListView.separated(
                        controller: scrollController,
                        padding: EdgeInsets.zero,
                        itemCount: items.length,
                        separatorBuilder: (_, _) =>
                            Divider(height: 1, color: AppColors.border),
                        itemBuilder: (_, i) => _tile(context, items[i]),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _empty() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_off_outlined,
                color: AppColors.muted, size: 34),
            SizedBox(height: 10),
            Text('No notifications yet',
                style: TextStyle(color: AppColors.muted, fontSize: 13)),
          ],
        ),
      );

  Widget _tile(BuildContext context, AppNotification n) {
    final route = _route(n.link);
    return InkWell(
      onTap: route == null
          ? null
          : () {
              final router = GoRouter.of(context);
              Navigator.of(context).pop(); // close the sheet
              router.push(route);
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(n.title,
                      style: TextStyle(
                          color: AppColors.text,
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5)),
                  const SizedBox(height: 4),
                  Text(n.body,
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 12, height: 1.5)),
                  const SizedBox(height: 5),
                  Text(_relTime(n.createdAt),
                      style: TextStyle(color: AppColors.muted, fontSize: 11)),
                ],
              ),
            ),
            if (route != null)
              Padding(
                padding: EdgeInsets.only(left: 8, top: 2),
                child: Icon(Icons.chevron_right, color: AppColors.muted, size: 20),
              ),
          ],
        ),
      ),
    );
  }

  /// Map a website notification link (e.g. "/pages/result-dashboard.html",
  /// "/pages/category.html?cat=lab+report") to the matching app route.
  static String? _route(String link) {
    if (link.isEmpty) return null;
    final l = link.toLowerCase();

    final cat = RegExp(r'category\.html\?cat=([^&]+)').firstMatch(l);
    if (cat != null) {
      final slug = Uri.decodeComponent(cat.group(1)!)
          .replaceAll('+', '-')
          .replaceAll(' ', '-')
          .trim();
      return slug.isEmpty ? null : '/category/$slug';
    }

    if (l.contains('result-dashboard') || l.contains('result')) return '/results';
    if (l.contains('classwork')) return '/classwork';
    if (l.contains('notice')) return '/notice';
    if (l.contains('resources')) return '/resources';
    if (l.contains('cover-page')) return '/cover-page';
    if (l.contains('gallery')) return '/gallery';
    if (l.contains('whats-new')) return '/'; // What's New page removed → home
    if (l.contains('students')) return '/students';
    if (l.contains('attendance')) return '/attendance';
    if (l.contains('user-guide')) return '/user-guide';
    if (l.contains('retake')) return '/info/retake';
    if (l.contains('routine')) return '/info/routine';
    if (l.contains('exam')) return '/info/exam';
    if (l.contains('info')) return '/info';
    if (l.contains('profile')) return '/profile';
    if (l.contains('index') || l == '/' || l.endsWith('/')) return '/';
    return null;
  }

  static String _relTime(DateTime t) {
    final s = DateTime.now().difference(t).inSeconds;
    if (s < 60) return 'Just now';
    if (s < 3600) return '${s ~/ 60} min ago';
    if (s < 86400) return '${s ~/ 3600} hr ago';
    final d = s ~/ 86400;
    if (d < 7) return '$d day${d > 1 ? 's' : ''} ago';
    return DateFormat('MMM d, y').format(t);
  }
}
