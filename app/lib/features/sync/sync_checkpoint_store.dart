import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/local/database.dart';

class SyncDeviceCursor {
  const SyncDeviceCursor({
    required this.deviceId,
    required this.lastSequence,
    this.checkpointId,
    required this.updatedAt,
  });

  final String deviceId;
  final int lastSequence;
  final String? checkpointId;
  final int updatedAt;
}

/// Commits remote domain changes, pack de-duplication and source-device cursor
/// advancement in one SQLite transaction.
class SyncCheckpointStore {
  SyncCheckpointStore._();

  static Future<SyncDeviceCursor?> readCursor(
    String deviceId, {
    Database? database,
  }) async {
    final db = database ?? await SnoteDatabase.open();
    final rows = await db.query(
      'sync_device_cursors',
      where: 'device_id = ?',
      whereArgs: [deviceId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return SyncDeviceCursor(
      deviceId: deviceId,
      lastSequence: (row['last_sequence'] as num).toInt(),
      checkpointId: row['checkpoint_id']?.toString(),
      updatedAt: (row['updated_at'] as num).toInt(),
    );
  }

  static Future<bool> applyPackAtomically({
    required String packId,
    required String deviceId,
    required int fromSequence,
    required int toSequence,
    required String verifiedSha256,
    required String? checkpointId,
    required Future<void> Function(Transaction transaction) applyChanges,
    DateTime? now,
    Database? database,
    bool isSnapshot = false,
  }) async {
    if (packId.isEmpty || deviceId.isEmpty ||
        fromSequence < 0 || toSequence < fromSequence ||
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(verifiedSha256)) {
      throw ArgumentError('Invalid verified sync checkpoint metadata.');
    }
    final db = database ?? await SnoteDatabase.open();
    final timestamp = (now ?? DateTime.now()).millisecondsSinceEpoch;
    return db.transaction((tx) async {
      final alreadyApplied = await tx.query(
        'sync_applied_packs',
        columns: ['pack_id'],
        where: 'pack_id = ?',
        whereArgs: [packId],
        limit: 1,
      );
      if (alreadyApplied.isNotEmpty) return false;

      final cursorRows = await tx.query(
        'sync_device_cursors',
        columns: ['last_sequence'],
        where: 'device_id = ?',
        whereArgs: [deviceId],
        limit: 1,
      );
      final lastSequence = cursorRows.isEmpty
          ? 0
          : (cursorRows.single['last_sequence'] as num).toInt();

      if (!isSnapshot && fromSequence != lastSequence + 1) {
        throw StateError(
          'Remote sync sequence gap: expected ${lastSequence + 1}, received $fromSequence.',
        );
      }
      if (!isSnapshot && toSequence <= lastSequence) {
        return false;
      }
      if (isSnapshot && toSequence < lastSequence) {
        throw StateError('A snapshot cannot move a device cursor backwards.');
      }

      // Any exception rolls back both the domain mutations and the checkpoint.
      await applyChanges(tx);
      await tx.insert('sync_applied_packs', {
        'pack_id': packId,
        'device_id': deviceId,
        'from_sequence': fromSequence,
        'to_sequence': toSequence,
        'sha256': verifiedSha256.toLowerCase(),
        'applied_at': timestamp,
      });
      await tx.insert(
        'sync_device_cursors',
        {
          'device_id': deviceId,
          'last_sequence': toSequence,
          'checkpoint_id': checkpointId,
          'updated_at': timestamp,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return true;
    });
  }

  static Future<String> fingerprint(List<int> verifiedPayload) async =>
      sha256.convert(verifiedPayload).toString();

  static Future<void> recordConflict({
    required String conflictId,
    required String entityType,
    required String entityId,
    required Map<String, Object?> localRevision,
    required Map<String, Object?> remoteRevision,
    required String reason,
    Database? database,
    DateTime? now,
  }) async {
    final db = database ?? await SnoteDatabase.open();
    await db.insert('sync_conflicts', {
      'conflict_id': conflictId,
      'entity_type': entityType,
      'entity_id': entityId,
      'local_revision_json': _encode(localRevision),
      'remote_revision_json': _encode(remoteRevision),
      'reason': reason,
      'status': 'open',
      'created_at': (now ?? DateTime.now()).millisecondsSinceEpoch,
      'resolved_at': null,
      'resolution_json': null,
    });
  }

  static Future<int> resolveConflict({
    required String conflictId,
    required Map<String, Object?> resolution,
    Database? database,
    DateTime? now,
  }) async {
    final db = database ?? await SnoteDatabase.open();
    return db.update(
      'sync_conflicts',
      {
        'status': 'resolved',
        'resolved_at': (now ?? DateTime.now()).millisecondsSinceEpoch,
        'resolution_json': _encode(resolution),
      },
      where: "conflict_id = ? AND status = 'open'",
      whereArgs: [conflictId],
    );
  }

  static String _encode(Map<String, Object?> value) => jsonEncode(value);
}
