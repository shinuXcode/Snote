import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../data/local/database.dart';
import '../../data/local/local_file_store.dart';
import 'sync_change_pack.dart';
import 'sync_journal.dart';

/// Serializes the current local representation of journaled domain entities.
///
/// File paths are deliberately never exported: file bytes are embedded in the
/// encrypted pack and restored through the local file store. Missing files or
/// oversized payloads fail the build so a successful journal acknowledgement
/// can never silently discard user content.
///
/// This is the outbound half only. A matching transactional applier is still
/// required before SyncEngine can safely be enabled in the application.
class SnoteSyncPackBuilder {
  SnoteSyncPackBuilder({
    Database? database,
    this.maximumFileBytes = 12 * 1024 * 1024,
    this.maximumPackBinaryBytes = 40 * 1024 * 1024,
  }) : _database = database {
    if (maximumFileBytes < 1 || maximumPackBinaryBytes < maximumFileBytes) {
      throw ArgumentError('Invalid sync binary size limits.');
    }
  }

  static const _uuid = Uuid();
  final Database? _database;
  final int maximumFileBytes;
  final int maximumPackBinaryBytes;

  Future<SyncChangePack> build(
    List<Map<String, Object?>> journalOperations,
  ) async {
    if (journalOperations.isEmpty) {
      throw ArgumentError('Cannot build an empty delta pack.');
    }
    final db = _database ?? await SnoteDatabase.open();
    final sorted = [...journalOperations]
      ..sort((a, b) => (a['sequence'] as num).compareTo(b['sequence'] as num));
    final deviceId = sorted.first['device_id'] as String;
    var binaryBytes = 0;
    final operations = <Map<String, dynamic>>[];

    for (final row in sorted) {
      if (row['device_id'] != deviceId) {
        throw StateError('A delta pack cannot mix source devices.');
      }
      final type = row['entity_type'] as String;
      final id = row['entity_id'] as String;
      final operation = row['operation'] as String;
      final payload = await _readEntity(db, type, id, operation, (bytes) {
        binaryBytes += bytes.length;
        if (bytes.length > maximumFileBytes ||
            binaryBytes > maximumPackBinaryBytes) {
          throw StateError('Sync pack exceeds its configured binary size limit.');
        }
        return base64Encode(bytes);
      });
      operations.add({
        'operationId': row['operation_id'],
        'sequence': (row['sequence'] as num).toInt(),
        'entityType': type,
        'entityId': id,
        'operation': operation,
        'createdAt': (row['created_at'] as num).toInt(),
        'entity': payload,
      });
    }

    final first = (sorted.first['sequence'] as num).toInt();
    final last = (sorted.last['sequence'] as num).toInt();
    return SyncChangePack(
      packId: _uuid.v4(),
      deviceId: deviceId,
      kind: SyncChangePackKind.delta,
      fromSequence: first,
      toSequence: last,
      vectorClock: {deviceId: last},
      operations: operations,
    );
  }

  Future<Map<String, dynamic>?> _readEntity(
    DatabaseExecutor db,
    String type,
    String id,
    String operation,
    String Function(List<int>) encodeBinary,
  ) async {
    if (operation == 'delete' || operation == 'purge') {
      // Tombstones remain meaningful even after the source row is gone.
      return {'id': id, 'deleted': true};
    }

    switch (type) {
      case 'note':
        final rows = await db.query('notes', where: 'id = ?', whereArgs: [id], limit: 1);
        if (rows.isEmpty) return {'id': id, 'deleted': true};
        final row = Map<String, Object?>.from(rows.first)..remove('owner_id');
        return row.cast<String, dynamic>();

      case 'folder':
        final rows = await db.query('folders', where: 'id = ?', whereArgs: [id], limit: 1);
        if (rows.isEmpty) return {'id': id, 'deleted': true};
        final row = Map<String, Object?>.from(rows.first)..remove('owner_id');
        return row.cast<String, dynamic>();

      case 'page':
        final rows = await db.query('pages', where: 'id = ?', whereArgs: [id], limit: 1);
        if (rows.isEmpty) return {'id': id, 'deleted': true};
        final row = Map<String, Object?>.from(rows.first);
        final path = row.remove('stroke_file')?.toString();
        if (path != null && path.isNotEmpty) {
          final bytes = await readLocalFile(path);
          row['strokeFileName'] = path.replaceAll('\\\\', '/').split('/').last;
          row['strokeBytesBase64'] = encodeBinary(bytes);
        }
        return row.cast<String, dynamic>();

      case 'attachment':
        final rows = await db.query('attachments', where: 'id = ?', whereArgs: [id], limit: 1);
        if (rows.isEmpty) return {'id': id, 'deleted': true};
        final row = Map<String, Object?>.from(rows.first);
        final path = row.remove('local_path')?.toString();
        row.remove('remote_path');
        if (path == null || path.isEmpty) {
          throw StateError('Attachment $id has no local binary file.');
        }
        final bytes = await readLocalFile(path);
        row['contentBase64'] = encodeBinary(bytes);
        row['contentLength'] = bytes.length;
        return row.cast<String, dynamic>();

      default:
        throw UnsupportedError('Unsupported sync entity type: $type');
    }
  }
}
