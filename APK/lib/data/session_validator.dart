import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/worker_api.dart';
import 'connectivity_service.dart';
import 'models/student.dart';
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
        return;
      }
      await Session.instance.touch();
      await _resolveSection(student);
    } finally {
      _checking = false;
    }
  }

  /// A session saved before guest access existed carries no section, so it
  /// reads as the class's own 62 / B — right for 62B, wrong for anybody else,
  /// who would go on being shown this class's routine. Asked once, because
  /// /lookup is rate limited and the answer does not change day to day.
  bool _sectionAsked = false;

  Future<void> _resolveSection(Student student) async {
    if (_sectionAsked || student.sectionKnown) return;
    _sectionAsked = true;
    final data = await WorkerApi.instance.lookup(student.id);
    if (data == null || data['found'] != true) {
      _sectionAsked = false; // a failed call is worth retrying
      return;
    }
    if (Session.instance.student?.id != student.id) return;
    await Session.instance.applySection(
      (data['batch']?.toString().trim().isNotEmpty ?? false)
          ? data['batch'].toString().trim()
          : Student.homeBatch,
      (data['section']?.toString().trim().isNotEmpty ?? false)
          ? data['section'].toString().trim()
          : Student.homeSection,
    );
  }
}
