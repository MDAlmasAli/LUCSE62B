import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_colors.dart';
import '../../core/constants.dart';
import '../../data/admin_repository.dart';
import '../../data/models/app_notification.dart';
import '../../data/session.dart';
import '../../shared/app_toast.dart';

class AdminControlScreen extends StatefulWidget {
  const AdminControlScreen({super.key});

  @override
  State<AdminControlScreen> createState() => _AdminControlScreenState();
}

class _AdminControlScreenState extends State<AdminControlScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _link = TextEditingController(text: '/');
  final _repo = AdminRepository.instance;

  Map<String, dynamic>? _status;
  List<AppNotification> _notifications = [];
  String _category = 'general';
  bool _authorized = false;
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _authenticate());
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _link.dispose();
    super.dispose();
  }

  Future<void> _authenticate() async {
    if (Session.instance.student?.id != K.attendanceAdminId) {
      if (mounted) context.go('/');
      return;
    }
    final password = await _passwordDialog();
    if (password == null || !mounted) {
      if (mounted) context.pop();
      return;
    }
    final ok = await _repo.login(password);
    if (!mounted) return;
    if (!ok) {
      AppToast.show(context, 'Admin verification failed.', error: true);
      context.pop();
      return;
    }
    setState(() => _authorized = true);
    await _refresh();
  }

  Future<String?> _passwordDialog() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Admin verification'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Portal password',
            prefixIcon: Icon(Icons.lock_outline),
          ),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Verify'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _refresh() async {
    if (!_authorized) return;
    setState(() => _loading = true);
    final results = await Future.wait([_repo.status(), _repo.notifications()]);
    if (!mounted) return;
    setState(() {
      _status = results[0] as Map<String, dynamic>?;
      _notifications = results[1] as List<AppNotification>;
      _loading = false;
    });
  }

  Future<void> _send() async {
    if (_title.text.trim().isEmpty || _body.text.trim().isEmpty) {
      AppToast.show(context, 'Title and message are required.', error: true);
      return;
    }
    setState(() => _sending = true);
    final result = await _repo.sendAnnouncement(
      category: _category,
      title: _title.text.trim(),
      body: _body.text.trim(),
      link: _link.text.trim().isEmpty ? '/' : _link.text.trim(),
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (result == null) {
      AppToast.show(context, 'Announcement failed.', error: true);
      return;
    }
    _title.clear();
    _body.clear();
    AppToast.show(context, 'Announcement sent.');
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Admin Control Center'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _authorized ? _refresh : null,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: !_authorized || _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            )
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
                children: [
                  _statusGrid(),
                  const SizedBox(height: 14),
                  _actions(),
                  const SizedBox(height: 14),
                  _composer(),
                  const SizedBox(height: 18),
                  const Text(
                    'Recent public notifications',
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 9),
                  ..._notifications.map(_notificationTile),
                ],
              ),
            ),
    );
  }

  Widget _statusGrid() {
    final latest = _status?['latest_app'] as Map?;
    final cards = [
      ('Students', '${_status?['students'] ?? 0}', Icons.groups_rounded),
      (
        'Notifications',
        '${_status?['notifications'] ?? 0}',
        Icons.notifications_rounded,
      ),
      (
        'Web Push',
        '${_status?['web_push_subscriptions'] ?? 0}',
        Icons.language_rounded,
      ),
      (
        'FCM Devices',
        '${_status?['fcm_tokens'] ?? 0}',
        Icons.phone_android_rounded,
      ),
      (
        'Latest APK',
        '${latest?['version_name'] ?? '—'}',
        Icons.system_update_rounded,
      ),
      (
        'Monitor',
        _status?['heartbeat'] == null ? 'Unknown' : 'Healthy',
        Icons.monitor_heart_rounded,
      ),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 9,
      crossAxisSpacing: 9,
      childAspectRatio: 2.15,
      children: cards
          .map(
            (item) => Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Icon(item.$3, color: AppColors.accentBright, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.$2,
                          style: const TextStyle(
                            color: AppColors.textBright,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          item.$1,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _actions() => Row(
    children: [
      Expanded(
        child: OutlinedButton.icon(
          onPressed: () async {
            final url = _status?['main_sheet_url']?.toString() ?? '';
            if (url.isNotEmpty) {
              await launchUrl(
                Uri.parse(url),
                mode: LaunchMode.externalApplication,
              );
            }
          },
          icon: const Icon(Icons.table_chart_rounded),
          label: const Text('Main Sheet'),
        ),
      ),
      const SizedBox(width: 9),
      Expanded(
        child: OutlinedButton.icon(
          onPressed: () async {
            final ok = await _repo.runMonitor();
            if (mounted) {
              AppToast.show(
                context,
                ok ? 'Update monitor started.' : 'Could not start monitor.',
                error: !ok,
              );
            }
          },
          icon: const Icon(Icons.sync_rounded),
          label: const Text('Run Sync'),
        ),
      ),
    ],
  );

  Widget _composer() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Send announcement',
          style: TextStyle(
            color: AppColors.text,
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _category,
          dropdownColor: AppColors.cardElevated,
          decoration: const InputDecoration(labelText: 'Category'),
          items: const [
            DropdownMenuItem(value: 'general', child: Text('General')),
            DropdownMenuItem(value: 'notice', child: Text('Notice')),
            DropdownMenuItem(value: 'classwork', child: Text('Classwork')),
            DropdownMenuItem(value: 'routine', child: Text('Routine / Exam')),
            DropdownMenuItem(value: 'app_update', child: Text('App Update')),
          ],
          onChanged: (value) => setState(() => _category = value ?? 'general'),
        ),
        const SizedBox(height: 9),
        TextField(
          controller: _title,
          decoration: const InputDecoration(labelText: 'Title'),
        ),
        const SizedBox(height: 9),
        TextField(
          controller: _body,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Message'),
        ),
        const SizedBox(height: 9),
        TextField(
          controller: _link,
          decoration: const InputDecoration(labelText: 'Open link / route'),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_rounded),
            label: const Text('Send to students'),
          ),
        ),
      ],
    ),
  );

  Widget _notificationTile(AppNotification item) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.border),
    ),
    child: ListTile(
      title: Text(
        item.title,
        style: const TextStyle(
          color: AppColors.text,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        '${DateFormat('MMM d, h:mm a').format(item.createdAt)}\n${item.body}',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppColors.muted, fontSize: 10.5),
      ),
      isThreeLine: true,
      trailing: IconButton(
        tooltip: 'Delete',
        icon: const Icon(Icons.delete_outline_rounded, color: AppColors.red),
        onPressed: () async {
          if (await _repo.deleteNotification(item.id)) await _refresh();
        },
      ),
    ),
  );
}
