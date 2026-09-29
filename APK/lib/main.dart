import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/app_theme.dart';
import 'core/router.dart';
import 'core/supa.dart';
import 'data/connectivity_service.dart';
import 'data/class_reminder_service.dart';
import 'data/deadline_reminder_service.dart';
import 'data/notification_gate.dart';
import 'data/models/app_version.dart';
import 'data/notification_preferences.dart';
import 'data/push_service.dart';
import 'data/session.dart';
import 'data/session_validator.dart';
import 'data/theme_controller.dart';
import 'data/update_service.dart';
import 'features/update/update_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supa.init();
  await Session.instance.load();
  await NotificationPreferences.instance.load();
  await ThemeController.instance.load();
  await ClassReminderService.instance.initialize().catchError((_) {});
  // Reminders cover the next seven days, so re-arming them on launch is
  // enough; nothing needs to run in the background for this. Deadline
  // reminders are re-armed the same way, and again by the Classwork screen.
  unawaited(ClassReminderService.instance.refreshFromRoutine());
  unawaited(DeadlineReminderService.instance.refresh());
  // Turning "Classwork & deadlines" off has to take the pending reminders with
  // it, so re-run the scheduler whenever the preferences change.
  NotificationPreferences.instance.addListener(
    () => unawaited(DeadlineReminderService.instance.refresh()),
  );

  // Resolve connectivity before optional startup network work. This makes an
  // offline launch immediate instead of waiting for Supabase/Firebase timeouts.
  await ConnectivityService.instance.start().timeout(
    const Duration(seconds: 2),
    onTimeout: () {},
  );

  // Push notifications (FCM). Runs in the background; re-link the device token
  // whenever the login state changes so pushes target the right student.
  PushService.instance.init();
  Session.instance.addListener(() => PushService.instance.onAuthChanged());
  SessionValidator.instance.start();

  // Check for updates before anything else. A FORCED update blocks the whole
  // app; an optional one is surfaced on the home screen.
  UpdateStatus update = UpdateStatus.none;
  if (ConnectivityService.instance.online) {
    try {
      update = await UpdateService.instance.check().timeout(
        const Duration(seconds: 5),
      );
    } catch (_) {}
  }

  runApp(LucseApp(update: update));
}

class LucseApp extends StatefulWidget {
  final UpdateStatus update;
  const LucseApp({super.key, required this.update});

  @override
  State<LucseApp> createState() => _LucseAppState();
}

class _LucseAppState extends State<LucseApp> with WidgetsBindingObserver {
  late final _router = buildRouter();
  final _theme = ThemeController.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _theme.addListener(_onThemeChanged);
    final u = widget.update;
    if (!u.forced && u.updateAvailable && u.latest != null) {
      pendingOptionalUpdate = u;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _router.go('/update');
      });
    }
  }

  @override
  void dispose() {
    _theme.removeListener(_onThemeChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onThemeChanged() => setState(() {});

  /// The OS flipped dark/light; only matters while we follow the system.
  @override
  void didChangePlatformBrightness() => _theme.onPlatformBrightnessChanged();

  /// Someone may have just come back from the settings page they were sent to,
  /// so re-check whether notifications are allowed and clear the warning.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(NotificationGate.instance.refresh());
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.update;

    // Keep AppColors pointed at the palette we are about to build with, then
    // key the screens on it. AppColors.* are plain statics rather than
    // `Theme.of(context)` lookups, so a `const` widget would otherwise keep its
    // old colors forever; changing the key remounts the subtree and rebuilds
    // every element. The Router itself stays mounted, so GoRouter keeps the
    // current location and only per-screen state (scroll offset, form text) is
    // lost — an acceptable trade for a deliberate theme switch.
    _theme.apply();
    final isDark = _theme.isDark;
    final theme = AppTheme.build(_theme.palette);
    final key = ValueKey(isDark ? 'theme-dark' : 'theme-light');
    _applySystemBars(isDark);

    // Forced update → block the entire app behind the update gate.
    if (u.forced && u.latest != null) {
      return MaterialApp(
        key: key,
        title: 'CSE 62B Portal',
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: UpdateGate(status: u),
      );
    }

    return MaterialApp.router(
      title: 'CSE 62B Portal',
      debugShowCheckedModeBanner: false,
      theme: theme,
      routerConfig: _router,
      builder: (_, child) =>
          KeyedSubtree(key: key, child: child ?? const SizedBox.shrink()),
    );
  }

  /// Status/navigation bar icons have to flip with the theme, and not every
  /// screen has an AppBar to do it for us.
  void _applySystemBars(bool isDark) {
    final icons = isDark ? Brightness.light : Brightness.dark;
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: icons,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: _theme.palette.bg,
        systemNavigationBarIconBrightness: icons,
      ),
    );
  }
}
