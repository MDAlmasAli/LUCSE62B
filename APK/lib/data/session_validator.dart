import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/worker_api.dart';
import 'connectivity_service.dart';
import 'session.dart';

/// Keeps an existing APK session tied to the authoritative Main Sheet roster.
///
/// Validation runs at startup, every minute while the app is alive, and
/// immediately whenever the app returns to the foreground. Offline/server
/// failures are fail-open; only an explicit `active: false` revokes access.
class SessionValidator with WidgetsBindingObserver {
  SessionValidator._();
  static final instance = SessionValidator._();

  bool _checking = false;
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    Timer.periodic(const Duration(minutes: 1), (_) => validate());
    unawaited(validate());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(validate());
  }

  Future<void> validate() async {
    final student = Session.instance.student;
    if (_checking ||
        student == null ||
        student.isDemo ||
        !ConnectivityService.instance.online) {
      return;
    }

    _checking = true;
    try {
      final active = await WorkerApi.instance.sessionActive(
        student.id,
        sessionId: student.sessionId,
        sessionIssuedAt: student.sessionIssuedAt,
      );
      if (active == false && Session.instance.student?.id == student.id) {
        await Session.instance.signOut();
      }
    } finally {
      _checking = false;
    }
  }
}
