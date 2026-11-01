import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:snote/data/local/schema.dart';
import 'package:snote/features/sync/sync_change_pack.dart';
import 'package:snote/features/sync/sync_engine.dart';
import 'package:snote/features/sync/sync_journal.dart';
import 'package:snote/features/sync/sync_transport.dart';

class _MemoryTransport implements SyncTransport {
  final Map<String, Uint8List> objects = {};
  bool connected = false;

  @override
  SyncProviderKind get kind => SyncProviderKind.localNetwork;

  @override
  SyncTransportCapabilities get capabilities => const SyncTransportCapabilities(
        supportsResumableUpload: false,
        supportsConditionalWrite: true,
        supportsBackgroundOperation: false,
      );

  @override
  Future<void> connect() async => connected = true;

  @override
  Future<void> disconnect() async => connected = false;

  @override
  Future<SyncRemotePage> listObjects({String? cursor}) async {
    final values = objects.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return SyncRemotePage(objects: values.map((entry) => SyncRemoteObject(
      objectId: entry.key,
      sha256: sha256.convert(entry.value).toString(),
      byteLength: entry.value.length,
      createdAt: DateTime.now().toUtc(),
    )).toList());
  }

  @override
  Future<void> uploadObject({
    required String objectId,
    required Stream<List<int>> encryptedBytes,
    required int byteLength,
    required String sha256,
  }) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in encryptedBytes) {
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    if (bytes.length != byteLength ||
        sha256.convert(bytes).toString() != sha256) {
      throw StateError('Test transport received invalid upload bytes.');
    }
    objects[objectId] = Uint8List.fromList(bytes);
  }

  @override
  Future<Stream<List<int>>> downloadObject(String objectId) async {
    final bytes = objects[objectId];
    if (bytes == null) throw StateError('Missing test object.');
    return Stream<List<int>>.value(bytes);
  }
}

Future<Database> _openDb() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  return openDatabase(
    inMemoryDatabasePath,
    version: databaseVersion,
    onCreate: (db, _) async {
      await db.execute(createSyncMetadataTable);
      await db.execute(createSyncOperationsTable);
      await db.execute(createSyncDeviceCursorsTable);
      await db.execute(createSyncAppliedPacksTable);
      await db.execute(createSyncConflictsTable);
      await db.execute('CREATE TABLE sync_test_entities (id TEXT PRIMARY KEY, value TEXT NOT NULL)');
    },
  );
}

void main() {
  late Database db;
  const key = <int>[
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
    17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32,
  ];

  setUp(() async => db = await _openDb());
  tearDown(() async => db.close());

  test('uploads encrypted journal changes and atomically applies remote packs', () async {
    final localOperation = await db.transaction((tx) async {
      await SyncJournal.record(
        tx,
        entityType: 'note',
        entityId: 'local-note',
        operation: 'update',
      );
      return tx.query('sync_operations', limit: 1);
    });
    final localDevice = localOperation.single['device_id'] as String;

    final remotePack = SyncChangePack(
      packId: 'remote-pack-1',
      deviceId: 'remote-device',
      kind: SyncChangePackKind.delta,
      fromSequence: 1,
      toSequence: 1,
      vectorClock: const {'remote-device': 1},
      operations: const [
        {
          'operationId': 'remote-op-1',
          'sequence': 1,
          'entityType': 'note',
          'entityId': 'remote-note',
          'operation': 'create',
        },
      ],
    );
    final remoteBytes = await remotePack.encrypt(key);
    final transport = _MemoryTransport()
      ..objects['remote-pack-1'] = remoteBytes;

    final engine = SyncEngine(
      transport: transport,
      sharedEncryptionKey: key,
      database: db,
      buildDelta: (operations) async => SyncChangePack(
        packId: 'local-pack-1',
        deviceId: localDevice,
        kind: SyncChangePackKind.delta,
        fromSequence: 1,
        toSequence: 1,
        vectorClock: {localDevice: 1},
        operations: [
          {
            'operationId': operations.single['operation_id'],
            'sequence': operations.single['sequence'],
            'entityType': operations.single['entity_type'],
            'entityId': operations.single['entity_id'],
            'operation': operations.single['operation'],
          },
        ],
      ),
      applyRemotePack: (transaction, pack) async {
        await transaction.insert('sync_test_entities', {
          'id': pack.operations.single['entityId'],
          'value': pack.operations.single['operation'],
        });
      },
    );

    final result = await engine.syncOnce();

    expect(result.uploadedPacks, 1);
    expect(result.uploadedOperations, 1);
    expect(result.downloadedPacks, 2);
    expect(result.appliedPacks, 1);
    expect(result.skippedPacks, 1);
    expect(transport.connected, isFalse);
    expect(transport.objects, contains('local-pack-1'));
    expect((await db.query('sync_operations')).single['status'], 'uploaded');
    expect((await db.query('sync_test_entities')).single['id'], 'remote-note');
    expect(await db.query('sync_applied_packs'), hasLength(1));
    expect((await SyncJournal.status(database: db)).pendingOperations, 0);
  });

  test('releases local journal lease if pack construction fails', () async {
    await db.transaction((tx) => SyncJournal.record(
      tx,
      entityType: 'note',
      entityId: 'note-1',
      operation: 'update',
    ));
    final engine = SyncEngine(
      transport: _MemoryTransport(),
      sharedEncryptionKey: key,
      database: db,
      buildDelta: (_) async => throw StateError('serialization failed'),
      applyRemotePack: (_, __) async {},
    );

    await expectLater(engine.syncOnce(), throwsA(isA<StateError>()));
    final row = (await db.query('sync_operations')).single;
    expect(row['status'], 'pending');
    expect(row['lease_id'], isNull);
    expect(row['next_attempt_at'], isNotNull);
  });
}
