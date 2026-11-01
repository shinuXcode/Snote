import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../data/local/database.dart';

/// Append-only local change journal. Call inside the source mutation transaction.
class SyncJournal {
  SyncJournal._();
  static const _uuid = Uuid();
  static const _deviceIdKey = 'local_device_id';
  static const _sequenceKey = 'local_sequence';

  static Future<String> _ensureDeviceId(DatabaseExecutor db) async {
    final rows = await db.query('sync_metadata', columns: ['value'],
        where: 'key = ?', whereArgs: [_deviceIdKey], limit: 1);
    if (rows.isNotEmpty) return rows.first['value']! as String;
    final id = _uuid.v4();
    await db.insert('sync_metadata', {'key': _deviceIdKey, 'value': id});
    return id;
  }

  static Future<void> record(DatabaseExecutor db, {
    required String entityType, required String entityId, required String operation,
  }) async {
    final deviceId = await _ensureDeviceId(db);
    final rows = await db.query('sync_metadata', columns: ['value'],
        where: 'key = ?', whereArgs: [_sequenceKey], limit: 1);
    final previous = rows.isEmpty ? 0 : int.tryParse(rows.first['value'] as String? ?? '') ?? 0;
    final next = previous + 1;
    await db.insert('sync_metadata', {'key': _sequenceKey, 'value': '$next'},
        conflictAlgorithm: ConflictAlgorithm.replace);
    await db.insert('sync_operations', {
      'operation_id': _uuid.v4(), 'device_id': deviceId, 'sequence': next,
      'entity_type': entityType, 'entity_id': entityId, 'operation': operation,
      'created_at': DateTime.now().millisecondsSinceEpoch, 'status': 'pending',
      'attempts': 0, 'last_error': null,
    });
  }

  static Future<SyncJournalStatus> status() async {
    final db = await SnoteDatabase.open();
    return db.transaction((tx) async {
      final deviceId = await _ensureDeviceId(tx);
      final counts = await tx.rawQuery("SELECT COUNT(*) AS total FROM sync_operations WHERE status = 'pending'");
      final rows = await tx.query('sync_metadata', columns: ['value'],
          where: 'key = ?', whereArgs: [_sequenceKey], limit: 1);
      final sequence = rows.isEmpty ? 0 : int.tryParse(rows.first['value'] as String? ?? '') ?? 0;
      return SyncJournalStatus(deviceId: deviceId,
          pendingOperations: (counts.first['total'] as num?)?.toInt() ?? 0,
          lastSequence: sequence);
    });
  }

  static Future<List<Map<String, Object?>>> pending({int limit = 100}) async {
    final db = await SnoteDatabase.open();
    return db.query('sync_operations', where: "status = 'pending'",
        orderBy: 'sequence ASC', limit: limit.clamp(1, 1000).toInt());
  }
}

class SyncJournalStatus {
  const SyncJournalStatus({required this.deviceId, required this.pendingOperations, required this.lastSequence});
  final String deviceId;
  final int pendingOperations;
  final int lastSequence;
}
