import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:snote/data/local/schema.dart';
import 'package:snote/features/sync/sync_checkpoint_store.dart';

Future<Database> openTestDatabase() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  return openDatabase(
    inMemoryDatabasePath,
    version: 1,
    onCreate: (db, _) async {
      await db.execute(createSyncDeviceCursorsTable);
      await db.execute(createSyncAppliedPacksTable);
      await db.execute(createSyncConflictsTable);
      await db.execute('CREATE TABLE test_entities (id TEXT PRIMARY KEY, value TEXT NOT NULL)');
    },
  );
}

void main() {
  late Database db;
  const sha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  setUp(() async => db = await openTestDatabase());
  tearDown(() async => db.close());

  test('remote changes and source cursor commit atomically', () async {
    final applied = await SyncCheckpointStore.applyPackAtomically(
      packId: 'pack-1',
      deviceId: 'device-remote',
      fromSequence: 1,
      toSequence: 2,
      verifiedSha256: sha,
      checkpointId: 'checkpoint-2',
      database: db,
      applyChanges: (tx) async {
        await tx.insert('test_entities', {'id': 'n1', 'value': 'remote'});
      },
    );

    expect(applied, isTrue);
    final cursor = await SyncCheckpointStore.readCursor('device-remote', database: db);
    expect(cursor?.lastSequence, 2);
    expect(cursor?.checkpointId, 'checkpoint-2');
    expect(await db.query('sync_applied_packs'), hasLength(1));
    expect(await db.query('test_entities'), hasLength(1));
  });

  test('replaying the same pack never applies its mutations twice', () async {
    var applyCount = 0;
    Future<void> apply(Transaction tx) async {
      applyCount++;
      await tx.insert('test_entities', {'id': 'n1', 'value': 'remote'});
    }

    final first = await SyncCheckpointStore.applyPackAtomically(
      packId: 'pack-1', deviceId: 'device-remote',
      fromSequence: 1, toSequence: 1, verifiedSha256: sha,
      checkpointId: 'checkpoint-1', database: db, applyChanges: apply,
    );
    final second = await SyncCheckpointStore.applyPackAtomically(
      packId: 'pack-1', deviceId: 'device-remote',
      fromSequence: 1, toSequence: 1, verifiedSha256: sha,
      checkpointId: 'checkpoint-1', database: db, applyChanges: apply,
    );

    expect(first, isTrue);
    expect(second, isFalse);
    expect(applyCount, 1);
    expect(await db.query('test_entities'), hasLength(1));
  });

  test('a failed domain mutation rolls back the pack record and cursor', () async {
    await expectLater(
      SyncCheckpointStore.applyPackAtomically(
        packId: 'pack-fail', deviceId: 'device-remote',
        fromSequence: 1, toSequence: 1, verifiedSha256: sha,
        checkpointId: 'checkpoint-1', database: db,
        applyChanges: (tx) async {
          await tx.insert('test_entities', {'id': 'n1', 'value': 'partial'});
          throw StateError('simulated apply failure');
        },
      ),
      throwsA(isA<StateError>()),
    );

    expect(await db.query('test_entities'), isEmpty);
    expect(await db.query('sync_applied_packs'), isEmpty);
    expect(await db.query('sync_device_cursors'), isEmpty);
  });

  test('rejects a missing sequence range instead of advancing the cursor', () async {
    await expectLater(
      SyncCheckpointStore.applyPackAtomically(
        packId: 'pack-gap', deviceId: 'device-remote',
        fromSequence: 2, toSequence: 3, verifiedSha256: sha,
        checkpointId: 'checkpoint-3', database: db,
        applyChanges: (_) async {},
      ),
      throwsA(isA<StateError>()),
    );
    expect(await db.query('sync_device_cursors'), isEmpty);
  });

  test('persists and resolves a manual conflict record', () async {
    await SyncCheckpointStore.recordConflict(
      conflictId: 'conflict-1',
      entityType: 'note',
      entityId: 'note-1',
      localRevision: const {'deviceA': 3, 'title': 'Local'},
      remoteRevision: const {'deviceB': 2, 'title': 'Remote'},
      reason: 'Concurrent title edits',
      database: db,
    );
    expect(await SyncCheckpointStore.resolveConflict(
      conflictId: 'conflict-1',
      resolution: const {'choice': 'keep_both'},
      database: db,
    ), 1);
    final row = (await db.query('sync_conflicts')).single;
    expect(row['status'], 'resolved');
    expect(row['resolution_json'], contains('keep_both'));
  });
}
