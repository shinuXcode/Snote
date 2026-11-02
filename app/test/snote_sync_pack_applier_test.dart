import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:snote/data/local/schema.dart';
import 'package:snote/features/sync/snote_sync_pack_applier.dart';
import 'package:snote/features/sync/sync_change_pack.dart';
import 'package:snote/features/sync/sync_checkpoint_store.dart';

Future<Database> _openDatabase() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  return openDatabase(
    inMemoryDatabasePath,
    version: databaseVersion,
    onCreate: (db, _) async {
      await db.execute(createFoldersTable);
      await db.execute(createNotesTable);
      await db.execute(createPagesTable);
      await db.execute(createAttachmentsTable);
      await db.execute(createSyncDeviceCursorsTable);
      await db.execute(createSyncAppliedPacksTable);
      await db.execute(createSyncConflictsTable);
    },
  );
}

void main() {
  late Database db;
  late SnoteSyncPackApplier applier;
  const digest = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  setUp(() async {
    db = await _openDatabase();
    applier = SnoteSyncPackApplier();
  });

  tearDown(() async => db.close());

  test('restores a remote note and advances its checkpoint atomically', () async {
    final pack = SyncChangePack(
      packId: 'remote-note-pack',
      deviceId: 'remote-device',
      kind: SyncChangePackKind.delta,
      fromSequence: 1,
      toSequence: 1,
      vectorClock: const {'remote-device': 1},
      operations: const [{
        'operationId': 'remote-op-1',
        'sequence': 1,
        'entityType': 'note',
        'entityId': 'note-remote',
        'operation': 'upsert',
        'entity': {
          'id': 'note-remote',
          'title': 'Synced notebook',
          'folder_id': null,
          'note_type': 'handwriting',
          'content_json': '{"version":5,"pages":[]}',
          'created_at': 100,
          'updated_at': 200,
          'deleted_at': null,
          'version': 1,
          'is_favorite': 0,
        },
      }],
    );

    final applied = await SyncCheckpointStore.applyPackAtomically(
      packId: pack.packId,
      deviceId: pack.deviceId,
      fromSequence: pack.fromSequence,
      toSequence: pack.toSequence,
      verifiedSha256: digest,
      checkpointId: pack.packId,
      database: db,
      applyChanges: (tx) => applier.apply(tx, pack),
    );

    expect(applied, isTrue);
    final row = (await db.query('notes')).single;
    expect(row['id'], 'note-remote');
    expect(row['title'], 'Synced notebook');
    expect(row['owner_id'], 'local');
    expect((await SyncCheckpointStore.readCursor('remote-device', database: db))?.lastSequence, 1);
  });

  test('preserves local and remote revisions instead of overwriting a conflict', () async {
    await db.insert('notes', {
      'id': 'same-note',
      'owner_id': 'local',
      'title': 'Local title',
      'note_type': 'handwriting',
      'created_at': 100,
      'updated_at': 300,
      'version': 2,
      'is_favorite': 0,
      'sync_state': 'pending',
    });
    final pack = SyncChangePack(
      packId: 'conflicting-pack',
      deviceId: 'remote-device',
      kind: SyncChangePackKind.delta,
      fromSequence: 1,
      toSequence: 1,
      vectorClock: const {'remote-device': 1},
      operations: const [{
        'operationId': 'remote-op-2',
        'sequence': 1,
        'entityType': 'note',
        'entityId': 'same-note',
        'operation': 'upsert',
        'entity': {
          'id': 'same-note',
          'title': 'Remote title',
          'note_type': 'handwriting',
          'created_at': 100,
          'updated_at': 250,
          'version': 2,
          'is_favorite': 0,
        },
      }],
    );

    await SyncCheckpointStore.applyPackAtomically(
      packId: pack.packId,
      deviceId: pack.deviceId,
      fromSequence: 1,
      toSequence: 1,
      verifiedSha256: digest,
      checkpointId: pack.packId,
      database: db,
      applyChanges: (tx) => applier.apply(tx, pack),
    );

    expect((await db.query('notes')).single['title'], 'Local title');
    final conflict = (await db.query('sync_conflicts')).single;
    expect(conflict['status'], 'open');
    expect(conflict['local_revision_json'], contains('Local title'));
    expect(conflict['remote_revision_json'], contains('Remote title'));
  });

  test('remote tombstones mark notes deleted without generating local edits', () async {
    await db.insert('notes', {
      'id': 'delete-me',
      'owner_id': 'local',
      'title': 'Old note',
      'note_type': 'handwriting',
      'created_at': 100,
      'updated_at': 200,
      'version': 1,
      'is_favorite': 0,
    });
    final pack = SyncChangePack(
      packId: 'delete-pack',
      deviceId: 'remote-device',
      kind: SyncChangePackKind.delta,
      fromSequence: 1,
      toSequence: 1,
      vectorClock: const {'remote-device': 1},
      operations: const [{
        'operationId': 'delete-op',
        'sequence': 1,
        'entityType': 'note',
        'entityId': 'delete-me',
        'operation': 'delete',
        'entity': {'id': 'delete-me', 'deleted': true},
      }],
    );

    await SyncCheckpointStore.applyPackAtomically(
      packId: pack.packId,
      deviceId: pack.deviceId,
      fromSequence: 1,
      toSequence: 1,
      verifiedSha256: digest,
      checkpointId: pack.packId,
      database: db,
      applyChanges: (tx) => applier.apply(tx, pack),
    );

    expect((await db.query('notes')).single['deleted_at'], isNotNull);
  });
}
