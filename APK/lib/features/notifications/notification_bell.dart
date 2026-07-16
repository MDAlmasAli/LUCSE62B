import 'package:flutter/material.dart';
import '../../core/app_colors.dart';
import '../../data/models/app_notification.dart';
import '../../data/notifications_repository.dart';
import 'notifications_sheet.dart';

/// Bell icon with an unread badge for the home app bar. Fetches on mount and
/// mirrors notifications.js badge/seen logic.
class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  final _repo = NotificationsRepository.instance;
  List<AppNotification> _items = [];
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await _repo.fetch();
      final seen = await _repo.lastSeen();
      if (!mounted) return;
      setState(() {
        _items = items;
        _unread = _repo.unreadCount(items, seen);
      });
    } catch (_) {/* silent */}
  }

  Future<void> _open() async {
    // Persist immediately: closing/killing the app while the sheet is open
    // must not make the same notifications unread again on the next launch.
    try {
      await _repo.markAllSeen(_items);
    } catch (_) {
      // The notification list should still open if local persistence fails.
    }
    if (!mounted) return;
    setState(() => _unread = 0);

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => NotificationsSheet(items: _items),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: _open,
      tooltip: 'Notifications',
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.notifications_outlined, color: AppColors.textSecondary),
          if (_unread > 0)
            Positioned(
              right: -3,
              top: -3,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                constraints: const BoxConstraints(minWidth: 15, minHeight: 15),
                decoration: BoxDecoration(
                  color: AppColors.red,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.bg, width: 2),
                ),
                child: Text(
                  _unread > 9 ? '9+' : '$_unread',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      height: 1.1),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
