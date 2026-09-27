import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../data/apk_installer.dart';
import '../../data/models/app_version.dart';
import '../../shared/gradient_button.dart';

/// Full-screen update prompt. When [status.forced] is true it is non-dismissible
/// (PopScope blocks back) — the app cannot be used until the user updates.
/// Shows the changelog (What's New + Bug Fixes) and installs via OTA.
class UpdateGate extends StatefulWidget {
  final UpdateStatus status;
  final VoidCallback? onSkip; // only for optional updates

  const UpdateGate({super.key, required this.status, this.onSkip});

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  double? _progress; // null = not started
  String _statusText = '';
  bool _failed = false;

  AppVersion get v => widget.status.latest!;

  Future<void> _install() async {
    if (v.apkUrl.isEmpty) {
      setState(() {
        _failed = true;
        _statusText = 'Download URL not configured yet.';
      });
      return;
    }
    setState(() {
      _progress = 0;
      _failed = false;
      _statusText = 'Starting download…';
    });

    final error = await ApkInstaller.downloadAndInstall(
      v.apkUrl,
      'lucse62b-${v.versionName}.apk',
      onProgress: (p) {
        if (!mounted) return;
        setState(() {
          _progress = p;
          _statusText = p >= 1.0
              ? 'Opening installer…'
              : 'Downloading… ${(p * 100).toStringAsFixed(0)}%';
        });
      },
    );

    if (!mounted) return;
    if (error != null) {
      setState(() {
        _failed = true;
        _progress = null;
        _statusText = error;
      });
    } else {
      setState(() => _statusText = 'Tap "Install" in the system prompt.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final forced = widget.status.forced;
    return PopScope(
      canPop: !forced,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        gradient: AppColors.accentGradient,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(Icons.system_update_rounded,
                          color: Colors.white, size: 34),
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: Text(
                        forced ? 'Update Required' : 'Update Available',
                        style: TextStyle(
                            color: AppColors.textBright,
                            fontSize: 24,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Center(
                      child: Text(
                        'Version ${v.versionName}',
                        style: TextStyle(
                            color: AppColors.accentBright, fontSize: 14),
                      ),
                    ),
                    if (forced) ...[
                      const SizedBox(height: 10),
                      Center(
                        child: Text(
                          'You must update to continue using the app.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: AppColors.textSecondary.withValues(alpha: 0.9),
                              fontSize: 13),
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    if (v.features.isNotEmpty)
                      _changelog("What's New", Icons.auto_awesome_rounded,
                          AppColors.accentBright, v.features),
                    if (v.fixes.isNotEmpty)
                      _changelog('Bug Fixes', Icons.bug_report_rounded,
                          AppColors.green, v.fixes),
                    const SizedBox(height: 12),
                    if (_progress != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: _progress == 0 ? null : _progress,
                          minHeight: 8,
                          backgroundColor: AppColors.border,
                          valueColor: AlwaysStoppedAnimation(AppColors.accent),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (_statusText.isNotEmpty)
                      Center(
                        child: Text(_statusText,
                            style: TextStyle(
                                color: _failed
                                    ? AppColors.red
                                    : AppColors.textSecondary,
                                fontSize: 12.5)),
                      ),
                    const SizedBox(height: 14),
                    GradientButton(
                      label: _progress == null ? 'Update Now' : 'Updating…',
                      icon: Icons.download_rounded,
                      busy: _progress != null && !_failed,
                      onPressed: (_progress == null || _failed) ? _install : null,
                    ),
                    if (!forced && widget.onSkip != null) ...[
                      const SizedBox(height: 6),
                      TextButton(
                        onPressed: widget.onSkip,
                        style: TextButton.styleFrom(
                            foregroundColor: AppColors.muted),
                        child: const Text('Later'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _changelog(String title, IconData icon, Color color, List<String> items) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 7),
            Text(title,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w700, fontSize: 13)),
          ]),
          const SizedBox(height: 10),
          ...items.map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('•  ',
                        style: TextStyle(color: color, fontSize: 13, height: 1.4)),
                    Expanded(
                      child: Text(t,
                          style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12.5,
                              height: 1.45)),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
