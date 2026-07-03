import 'package:flutter/material.dart';

import 'core/app_theme.dart';
import 'core/router.dart';
import 'core/supa.dart';
import 'data/connectivity_service.dart';
import 'data/models/app_version.dart';
import 'data/push_service.dart';
import 'data/session.dart';
import 'data/session_validator.dart';
import 'data/update_service.dart';
import 'features/update/update_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supa.init();
  await Session.instance.load();

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

class _LucseAppState extends State<LucseApp> {
  late final _router = buildRouter();

  @override
  void initState() {
    super.initState();
    final u = widget.update;
    if (!u.forced && u.updateAvailable && u.latest != null) {
      pendingOptionalUpdate = u;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _router.go('/update');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.update;

    // Forced update → block the entire app behind the update gate.
    if (u.forced && u.latest != null) {
      return MaterialApp(
        title: 'CSE 62B Portal',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        home: UpdateGate(status: u),
      );
    }

    return MaterialApp.router(
      title: 'CSE 62B Portal',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: _router,
    );
  }
}
