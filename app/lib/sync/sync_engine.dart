import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

class SyncEngine {
  final Connectivity connectivity;

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _running = false;

  SyncEngine({Connectivity? connectivity})
      : connectivity = connectivity ?? Connectivity();

  Future<void> start() async {
    if (_running) return;
    _running = true;

    _subscription = connectivity.onConnectivityChanged.listen((states) {
      if (states.any((s) => s != ConnectivityResult.none)) {
        unawaited(flush());
      }
    });

    final states = await connectivity.checkConnectivity();
    if (states.any((s) => s != ConnectivityResult.none)) {
      await flush();
    }
  }

  Future<void> flush() async {
    // Phase 1 intentionally keeps this idempotent.
    // Queue reads, conflict resolution and blob upload are added next.
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    _running = false;
  }
}
