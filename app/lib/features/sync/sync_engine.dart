import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/local/database.dart';
import 'sync_change_pack.dart';
import 'sync_checkpoint_store.dart';
import 'sync_journal.dart';
import 'sync_object_integrity.dart';
import 'sync_transport.dart';

typedef SyncPackBuilder = Future<SyncChangePack> Function(
  List<Map<String, Object?>> journalOperations,
);

typedef SyncPackApplier = Future<void> Function(
  Transaction transaction,
  SyncChangePack pack,
);

/// Runs one complete encrypted transport cycle.
///
/// Domain serialization and domain-specific merge/apply rules are injected so
/// this coordinator never guesses how a note, page, stroke, or attachment is
/// represented. The builder must include all referenced binary data in the
/// encrypted pack; the applier must mutate only through the supplied
/// transaction. The encryption key must be shared securely by paired devices.
class SyncEngine {
  SyncEngine({
    required this.transport,
    required List<int> sharedEncryptionKey,
    required this.buildDelta,
    required this.applyRemotePack,
    Database? database,
    this.batchSize = 50,
    this.maximumRemotePages = 1000,
  })  : _key = Uint8List.fromList(sharedEncryptionKey),
        _database = database {
    if (_key.length != 32) {
      throw ArgumentError('A shared 256-bit sync key is required.');
    }
    if (batchSize < 1 || batchSize > 500) {
      throw ArgumentError.value(batchSize, 'batchSize', 'Must be between 1 and 500.');
    }
    if (maximumRemotePages < 1) {
      throw ArgumentError.value(maximumRemotePages, 'maximumRemotePages');
    }
  }

  final SyncTransport transport;
  final Uint8List _key;
  final SyncPackBuilder buildDelta;
  final SyncPackApplier applyRemotePack;
  final Database? _database;
  final int batchSize;
  final int maximumRemotePages;

  Future<SyncEngineResult> syncOnce() async {
    final db = _database ?? await SnoteDatabase.open();
    await SyncJournal.recoverExpiredLeases(database: db);
    final journalStatus = await SyncJournal.status(database: db);
    var uploadedPacks = 0;
    var uploadedOperations = 0;
    var downloadedPacks = 0;
    var appliedPacks = 0;
    var skippedPacks = 0;
    String? cursor;
    final seenCursors = <String>{};
    var pageCount = 0;

    try {
      await transport.connect();
      final lease = await SyncJournal.claimPending(
        limit: batchSize,
        database: db,
      );
      if (lease.operations.isNotEmpty) {
        var acknowledged = false;
        try {
          _validateContiguousLease(lease.operations, journalStatus.deviceId);
          final pack = await buildDelta(lease.operations);
          _validateBuiltPack(pack, lease.operations, journalStatus.deviceId);
          final encrypted = await pack.encrypt(_key);
          final digest = sha256.convert(encrypted).toString();
          await transport.uploadObject(
            objectId: pack.packId,
            encryptedBytes: Stream<List<int>>.value(encrypted),
            byteLength: encrypted.length,
            sha256: digest,
          );
          await SyncJournal.acknowledge(lease, database: db);
          acknowledged = true;
          uploadedPacks = 1;
          uploadedOperations = lease.operations.length;
        } catch (error) {
          if (!acknowledged) {
            await SyncJournal.release(
              lease,
              error: error.toString(),
              database: db,
            );
          }
          rethrow;
        }
      }

      // Fetch metadata first, then apply in per-device sequence order. Cloud
      // providers do not promise chronological listing order.
      final remoteObjects = <SyncRemoteObject>[];
      var listedBytes = 0;
      while (true) {
        final page = await transport.listObjects(cursor: cursor);
        remoteObjects.addAll(page.objects);
        if (remoteObjects.length > 5000) {
          throw StateError('Remote sync listing exceeded the 5000-object safety limit.');
        }
        for (final object in page.objects) {
          listedBytes += object.byteLength;
          if (listedBytes > 256 * 1024 * 1024) {
            throw StateError('Remote sync batch exceeded the 256 MiB safety limit.');
          }
        }
        final next = page.nextCursor;
        if (next == null || next.isEmpty) break;
        if (!seenCursors.add(next)) {
          throw StateError('Remote sync listing returned a repeated continuation cursor.');
        }
        cursor = next;
        pageCount++;
        if (pageCount >= maximumRemotePages) {
          throw StateError('Remote sync listing exceeded the configured page limit.');
        }
      }

      final verifiedPacks = <({SyncChangePack pack, String digest})>[];
      for (final remote in remoteObjects) {
        downloadedPacks++;
        if (remote.byteLength < 1 ||
            !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,179}

      return SyncEngineResult(
        uploadedPacks: uploadedPacks,
        uploadedOperations: uploadedOperations,
        downloadedPacks: downloadedPacks,
        appliedPacks: appliedPacks,
        skippedPacks: skippedPacks,
      );
    } finally {
      await transport.disconnect();
    }
  }

  void _validateContiguousLease(
    List<Map<String, Object?>> operations,
    String deviceId,
  ) {
    if (operations.isEmpty) return;
    final sorted = [...operations]
      ..sort((a, b) => (a['sequence'] as num).compareTo(b['sequence'] as num));
    for (var index = 0; index < sorted.length; index++) {
      if (sorted[index]['device_id'] != deviceId) {
        throw StateError('A sync lease contains operations from another device.');
      }
      final sequence = (sorted[index]['sequence'] as num).toInt();
      if (index > 0 &&
          sequence != (sorted[index - 1]['sequence'] as num).toInt() + 1) {
        throw StateError('A sync lease contains a sequence gap.');
      }
    }
  }

  void _validateBuiltPack(
    SyncChangePack pack,
    List<Map<String, Object?>> operations,
    String deviceId,
  ) {
    final sorted = [...operations]
      ..sort((a, b) => (a['sequence'] as num).compareTo(b['sequence'] as num));
    if (pack.kind != SyncChangePackKind.delta ||
        pack.deviceId != deviceId ||
        pack.fromSequence != (sorted.first['sequence'] as num).toInt() ||
        pack.toSequence != (sorted.last['sequence'] as num).toInt()) {
      throw StateError('The delta builder returned a pack outside the claimed journal range.');
    }
    final expectedIds = sorted.map((row) => row['operation_id']).toSet();
    final actualIds = pack.operations.map((row) => row['operationId']).toSet();
    if (expectedIds.length != actualIds.length ||
        !expectedIds.containsAll(actualIds)) {
      throw StateError('The encrypted pack does not represent every claimed journal operation.');
    }
  }
}

class SyncEngineResult {
  const SyncEngineResult({
    required this.uploadedPacks,
    required this.uploadedOperations,
    required this.downloadedPacks,
    required this.appliedPacks,
    required this.skippedPacks,
  });

  final int uploadedPacks;
  final int uploadedOperations;
  final int downloadedPacks;
  final int appliedPacks;
  final int skippedPacks;
}
).hasMatch(remote.objectId)) {
          throw const FormatException('Remote sync object metadata is invalid.');
        }
        final bytes = await SyncObjectIntegrity.collectAndVerify(
          await transport.downloadObject(remote.objectId),
          expectedByteLength: remote.byteLength,
          expectedSha256: remote.sha256,
        );
        final pack = await SyncChangePack.decrypt(bytes, _key);
        if (pack.packId != remote.objectId) {
          throw const FormatException('Remote object ID does not match its encrypted manifest.');
        }
        if (pack.deviceId == journalStatus.deviceId) {
          skippedPacks++;
          continue;
        }
        verifiedPacks.add((pack: pack, digest: remote.sha256));
      }

      verifiedPacks.sort((a, b) {
        final deviceOrder = a.pack.deviceId.compareTo(b.pack.deviceId);
        if (deviceOrder != 0) return deviceOrder;
        final sequenceOrder = a.pack.fromSequence.compareTo(b.pack.fromSequence);
        if (sequenceOrder != 0) return sequenceOrder;
        return a.pack.toSequence.compareTo(b.pack.toSequence);
      });

      for (final verified in verifiedPacks) {
        final pack = verified.pack;
        final applied = await SyncCheckpointStore.applyPackAtomically(
          packId: pack.packId,
          deviceId: pack.deviceId,
          fromSequence: pack.fromSequence,
          toSequence: pack.toSequence,
          verifiedSha256: verified.digest,
          checkpointId: pack.packId,
          isSnapshot: pack.kind == SyncChangePackKind.snapshot,
          database: db,
          applyChanges: (transaction) => applyRemotePack(transaction, pack),
        );
        if (applied) {
          appliedPacks++;
        } else {
          skippedPacks++;
        }
      }

      return SyncEngineResult(
        uploadedPacks: uploadedPacks,
        uploadedOperations: uploadedOperations,
        downloadedPacks: downloadedPacks,
        appliedPacks: appliedPacks,
        skippedPacks: skippedPacks,
      );
    } finally {
      await transport.disconnect();
    }
  }

  void _validateContiguousLease(
    List<Map<String, Object?>> operations,
    String deviceId,
  ) {
    if (operations.isEmpty) return;
    final sorted = [...operations]
      ..sort((a, b) => (a['sequence'] as num).compareTo(b['sequence'] as num));
    for (var index = 0; index < sorted.length; index++) {
      if (sorted[index]['device_id'] != deviceId) {
        throw StateError('A sync lease contains operations from another device.');
      }
      final sequence = (sorted[index]['sequence'] as num).toInt();
      if (index > 0 &&
          sequence != (sorted[index - 1]['sequence'] as num).toInt() + 1) {
        throw StateError('A sync lease contains a sequence gap.');
      }
    }
  }

  void _validateBuiltPack(
    SyncChangePack pack,
    List<Map<String, Object?>> operations,
    String deviceId,
  ) {
    final sorted = [...operations]
      ..sort((a, b) => (a['sequence'] as num).compareTo(b['sequence'] as num));
    if (pack.kind != SyncChangePackKind.delta ||
        pack.deviceId != deviceId ||
        pack.fromSequence != (sorted.first['sequence'] as num).toInt() ||
        pack.toSequence != (sorted.last['sequence'] as num).toInt()) {
      throw StateError('The delta builder returned a pack outside the claimed journal range.');
    }
    final expectedIds = sorted.map((row) => row['operation_id']).toSet();
    final actualIds = pack.operations.map((row) => row['operationId']).toSet();
    if (expectedIds.length != actualIds.length ||
        !expectedIds.containsAll(actualIds)) {
      throw StateError('The encrypted pack does not represent every claimed journal operation.');
    }
  }
}

class SyncEngineResult {
  const SyncEngineResult({
    required this.uploadedPacks,
    required this.uploadedOperations,
    required this.downloadedPacks,
    required this.appliedPacks,
    required this.skippedPacks,
  });

  final int uploadedPacks;
  final int uploadedOperations;
  final int downloadedPacks;
  final int appliedPacks;
  final int skippedPacks;
}
