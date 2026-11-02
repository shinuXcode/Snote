import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../data/local/local_file_store.dart';

/// Applies decrypted Snotee change packs without generating new local journal
/// events. The caller must run this inside SyncCheckpointStore's transaction.
class SnoteSyncPackApplier {
  SnoteSyncPackApplier({this.localOwnerId = 'local'});

  static const _uuid = Uuid();
  final String localOwnerId;

  Future<void> apply(Transaction transaction, dynamic pack) async {
    final operations = pack.operations;
    final stagedFiles = <String>[];
    try {
      for (final operation in operations) {
        final type = operation['entityType']?.toString();
        final id = operation['entityId']?.toString();
        final action = operation['operation']?.toString();
        final entity = operation['entity'];
        if (type == null || id == null || id.isEmpty || action == null ||
            entity is! Map<String, dynamic>) {
          throw const FormatException('Remote change operation is malformed.');
        }
        await _applyOne(
          transaction,
          type: type,
          id: id,
          action: action,
          entity: Map<String, dynamic>.from(entity),
          stagedFiles: stagedFiles,
        );
      }
    } catch (_) {
      // Files are staged before their SQLite references. Roll back staged
      // files when the enclosing database transaction rejects the pack.
      for (final path in stagedFiles) {
        try { await deleteLocalFile(path); } catch (_) {}
      }
      rethrow;
    }
  }

  Future<void> _applyOne(
    Transaction tx, {
    required String type,
    required String id,
    required String action,
    required Map<String, dynamic> entity,
    required List<String> stagedFiles,
  }) async {
    if (entity['id']?.toString() != id) {
      throw const FormatException('Remote entity ID does not match its operation.');
    }
    final deleted = entity['deleted'] == true ||
        action == 'delete' || action == 'purge';

    switch (type) {
      case 'note':
        await _applyRow(tx, table: 'notes', id: id, entity: entity,
            deleted: deleted, softDelete: true, stagedFiles: stagedFiles);
        return;
      case 'folder':
        await _applyRow(tx, table: 'folders', id: id, entity: entity,
            deleted: deleted, softDelete: true, stagedFiles: stagedFiles);
        return;
      case 'page':
        await _applyPage(tx, id: id, entity: entity, deleted: deleted,
            stagedFiles: stagedFiles);
        return;
      case 'attachment':
        await _applyAttachment(tx, id: id, entity: entity, deleted: deleted,
            stagedFiles: stagedFiles);
        return;
      default:
        throw UnsupportedError('Unsupported remote entity type: $type');
    }
  }

  Future<void> _applyRow(
    Transaction tx, {
    required String table,
    required String id,
    required Map<String, dynamic> entity,
    required bool deleted,
    required bool softDelete,
    required List<String> stagedFiles,
  }) async {
    final existing = await tx.query(table, where: 'id = ?', whereArgs: [id], limit: 1);
    if (deleted) {
      if (existing.isEmpty) return;
      if (softDelete) {
        await tx.update(table, {'deleted_at': DateTime.now().millisecondsSinceEpoch},
            where: 'id = ?', whereArgs: [id]);
      } else {
        await tx.delete(table, where: 'id = ?', whereArgs: [id]);
      }
      return;
    }
    final row = Map<String, Object?>.from(entity);
    row.remove('deleted');
    row['owner_id'] = localOwnerId;
    if (table == 'notes') row['sync_state'] = 'synced';
    if (existing.isNotEmpty && !_sameRevision(existing.first, row)) {
      await _recordConflict(tx, table, id, existing.first, row);
      return;
    }
    await tx.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _applyPage(
    Transaction tx, {
    required String id,
    required Map<String, dynamic> entity,
    required bool deleted,
    required List<String> stagedFiles,
  }) async {
    final existing = await tx.query('pages', where: 'id = ?', whereArgs: [id], limit: 1);
    if (deleted) {
      await tx.delete('pages', where: 'id = ?', whereArgs: [id]);
      return;
    }
    final row = Map<String, Object?>.from(entity);
    final encoded = row.remove('strokeBytesBase64')?.toString();
    final filename = row.remove('strokeFileName')?.toString();
    if (encoded != null) {
      final bytes = base64Decode(encoded);
      final path = await writeLocalFile('sync_pages', '${id}_${filename ?? 'strokes.bin'}', bytes);
      stagedFiles.add(path);
      row['stroke_file'] = path;
    } else {
      row['stroke_file'] = existing.isEmpty ? null : existing.first['stroke_file'];
    }
    if (existing.isNotEmpty && !_sameRevision(existing.first, row)) {
      await _recordConflict(tx, 'page', id, existing.first, row);
      return;
    }
    await tx.insert('pages', row, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _applyAttachment(
    Transaction tx, {
    required String id,
    required Map<String, dynamic> entity,
    required bool deleted,
    required List<String> stagedFiles,
  }) async {
    final existing = await tx.query('attachments', where: 'id = ?', whereArgs: [id], limit: 1);
    if (deleted) {
      await tx.delete('attachments', where: 'id = ?', whereArgs: [id]);
      return;
    }
    final row = Map<String, Object?>.from(entity);
    final encoded = row.remove('contentBase64')?.toString();
    row.remove('contentLength');
    if (encoded == null) {
      throw const FormatException('Remote attachment is missing its binary content.');
    }
    final bytes = base64Decode(encoded);
    final name = 'attachment_${id}_${_uuid.v4()}.bin';
    final path = await writeLocalFile('sync_attachments', name, bytes);
    stagedFiles.add(path);
    row['local_path'] = path;
    row.remove('remote_path');
    if (existing.isNotEmpty && !_sameRevision(existing.first, row)) {
      await _recordConflict(tx, 'attachment', id, existing.first, row);
      return;
    }
    await tx.insert('attachments', row, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  bool _sameRevision(Map<String, Object?> local, Map<String, Object?> incoming) {
    final left = Map<String, Object?>.from(local)
      ..remove('owner_id')
      ..remove('sync_state')
      ..remove('local_path')
      ..remove('stroke_file');
    final right = Map<String, Object?>.from(incoming)
      ..remove('owner_id')
      ..remove('sync_state')
      ..remove('local_path')
      ..remove('stroke_file');
    return jsonEncode(left) == jsonEncode(right);
  }

  Future<void> _recordConflict(
    Transaction tx,
    String type,
    String id,
    Map<String, Object?> local,
    Map<String, Object?> remote,
  ) async {
    await tx.insert('sync_conflicts', {
      'conflict_id': _uuid.v4(),
      'entity_type': type,
      'entity_id': id,
      'local_revision_json': jsonEncode(local),
      'remote_revision_json': jsonEncode(remote),
      'reason': 'Concurrent revision preserved for manual resolution.',
      'status': 'open',
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'resolved_at': null,
      'resolution_json': null,
    });
  }
}
