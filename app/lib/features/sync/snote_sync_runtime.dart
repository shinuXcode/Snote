import 'package:sqflite/sqflite.dart';

import '../../data/local/database.dart';
import 'snote_sync_pack_applier.dart';
import 'snote_sync_pack_builder.dart';
import 'sync_engine.dart';
import 'sync_transport.dart';

/// Application entry point for a provider-backed sync cycle. The caller owns
/// provider credentials and obtains the shared key from SyncKeyVault.
class SnoteSyncRuntime {
  SnoteSyncRuntime({
    required this.transport,
    required List<int> sharedKey,
    Database? database,
  })  : _sharedKey = List<int>.unmodifiable(sharedKey),
        _database = database;

  final SyncTransport transport;
  final List<int> _sharedKey;
  final Database? _database;

  Future<SyncEngineResult> synchronize() async {
    if (_sharedKey.length != 32) {
      throw ArgumentError('Pair this device before starting synchronization.');
    }
    final db = _database ?? await SnoteDatabase.open();
    final builder = SnoteSyncPackBuilder(database: db);
    final applier = SnoteSyncPackApplier();
    final engine = SyncEngine(
      transport: transport,
      sharedEncryptionKey: _sharedKey,
      database: db,
      buildDelta: builder.build,
      applyRemotePack: applier.apply,
    );
    return engine.syncOnce();
  }
}
