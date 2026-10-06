import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../data/remote/note_sync_service.dart';
import '../data/remote/supabase_service.dart';

class SyncEngine {
  final Connectivity connectivity;
  final NoteSyncService? service;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _running = false;
  bool _flushing = false;

  SyncEngine({
    Connectivity? connectivity,
    NoteSyncService? service,
  })  : connectivity = connectivity ?? Connectivity(),
        service = service ??
            (SnoteSupabase.client == null
                ? null
                : NoteSyncService(SnoteSupabase.client!));

  Future<void> start() async {
    if (_running || service == null) return;
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
    if (_flushing || service == null) return;

    _flushing = true;
    try {
      await service!.flush();
      await service!.pullLatest();
    } finally {
      _flushing = false;
    }
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    _running = false;
  }
}
