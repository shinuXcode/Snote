import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:snote/data/local/schema.dart';
import 'package:snote/features/sync/sync_journal.dart';

Future<Database> _openTestDatabase() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  return openDatabase(
    inMemoryDatabasePath,
    version: 1,
    onCreate: (db, _) async {
      await db.execute(createSyncMetadataTable);
      await db.execute(createSyncOperationsTable);
    },
  );
}

void main() {
  late Database db;

  setUp(() async {
    db = await _openTestDatabase();
  });

  tearDown(() async {
    await db.close();
  });

  test('journal records monotonic per-device sequence numbers', () async {
    await SyncJournal.record(db, entityType: 'note', entityId: 'n1', operation: 'upsert');
    await SyncJournal.record(db, entityType: 'folder', entityId: 'f1', operation: 'delete');

    final rows = await db.query('sync_operations', orderBy: 'sequence ASC');
    expect(rows, hasLength(2));
    expect(rows.map((row) => row['sequence']), [1, 2]);
    expect(rows.map((row) => row['status']), ['pending', 'pending']);
    expect(rows[0]['device_id'], rows[1]['device_id']);
  });

  test('journal writes roll back with the source transaction', () async {
    await expectLater(
      db.transaction((tx) async {
        await SyncJournal.record(tx, entityType: 'note', entityId: 'rollback', operation: 'upsert');
        throw StateError('simulate source mutation failure');
      }),
      throwsA(isA<StateError>()),
    );
    expect(await db.query('sync_operations'), isEmpty);
    expect(await db.query('sync_metadata'), isEmpty);
  });

  test('claimed operations cannot be claimed twice and acknowledgement is idempotent', () async {
    await SyncJournal.record(db, entityType: 'note', entityId: 'n1', operation: 'upsert');
    await SyncJournal.record(db, entityType: 'note', entityId: 'n2', operation: 'upsert');

    final first = await SyncJournal.claimPending(limit: 1, database: db);
    expect(first.operations, hasLength(1));
    expect(first.operations.single['status'], 'in_progress');

    final second = await SyncJournal.claimPending(limit: 5, database: db);
    expect(second.operations, hasLength(1));
    expect(second.operations.single['entity_id'], isNot(first.operations.single['entity_id']));

    expect(await SyncJournal.acknowledge(first, database: db), 1);
    expect(await SyncJournal.acknowledge(first, database: db), 0);
    expect(await SyncJournal.pending(database: db), hasLength(0));

    final uploaded = await db.query('sync_operations', where: "status = 'uploaded'");
    expect(uploaded, hasLength(1));
  });

  test('released operation retains attempts and can be retried', () async {
    await SyncJournal.record(db, entityType: 'note', entityId: 'n1', operation: 'upsert');
    final lease = await SyncJournal.claimPending(database: db);
    expect(lease.operations.single['attempts'], 1);

    expect(
      await SyncJournal.release(lease, error: 'temporary network failure', database: db),
      1,
    );
    final pending = await SyncJournal.pending(database: db);
    expect(pending.single['status'], 'pending');
    expect(pending.single['attempts'], 1);
    expect(pending.single['last_error'], 'temporary network failure');

    final retry = await SyncJournal.claimPending(database: db);
    expect(retry.operations.single['attempts'], 2);
  });

  test('expired in-progress lease is recovered after a process crash', () async {
    final start = DateTime.utc(2026, 11, 1, 12);
    await SyncJournal.record(db, entityType: 'note', entityId: 'n1', operation: 'upsert');
    final lease = await SyncJournal.claimPending(
      database: db,
      now: start,
      leaseDuration: const Duration(seconds: 30),
    );
    expect(lease.operations.single['status'], 'in_progress');

    expect(
      await SyncJournal.recoverExpiredLeases(
        database: db,
        now: start.add(const Duration(seconds: 31)),
      ),
      1,
    );
    final pending = await SyncJournal.pending(database: db);
    expect(pending.single['status'], 'pending');
    expect(pending.single['lease_id'], isNull);
    expect(pending.single['lease_until'], isNull);
  });

  test('new schema includes durable lease columns', () async {
    final columns = await db.rawQuery('PRAGMA table_info(sync_operations)');
    final names = columns.map((row) => row['name']).toSet();
    expect(names, containsAll(['lease_id', 'lease_until', 'attempts', 'status']));
  });
}
