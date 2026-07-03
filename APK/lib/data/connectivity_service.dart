import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../core/sheets_api.dart';
import '../core/worker_api.dart';

/// Tracks online/offline state for the whole app. When connectivity returns we
/// clear the session caches so screens reload fresh data automatically. Drives
/// the home online/offline indicator.
class ConnectivityService extends ChangeNotifier {
  ConnectivityService._();
  static final instance = ConnectivityService._();

  // Start pessimistically. On an offline launch this prevents startup services
  // from attempting long network calls before connectivity is known.
  bool _online = false;
  bool get online => _online;

  StreamSubscription<List<ConnectivityResult>>? _sub;

  Future<void> start() async {
    try {
      _set(_isOnline(await Connectivity().checkConnectivity()));
    } catch (_) {}
    _sub ??= Connectivity().onConnectivityChanged.listen(
      (r) => _set(_isOnline(r)),
    );
  }

  static bool _isOnline(List<ConnectivityResult> r) =>
      r.isNotEmpty && r.any((x) => x != ConnectivityResult.none);

  void _set(bool v) {
    if (v == _online) return;
    final cameOnline = v && !_online;
    _online = v;
    notifyListeners();
    if (cameOnline) {
      // Back online → drop cached data so the next screen fetch is fresh.
      SheetsApi.instance.clearCache();
      WorkerApi.instance.clearResultCache();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
