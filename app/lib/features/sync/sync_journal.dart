import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../data/local/database.dart';

/// Append-only local change journal. Call inside the source mutation transaction.
class SyncJournal {
  SyncJournal._();

  static const _uuid = Uuid();
  static const _deviceIdKey = 'local_device_id';
  static const _sequenceKey = 'local_sequence';
  static const _maximumRetryDelay = Duration(minutes: 15);

  static Future<String> _ensureDeviceId(DatabaseExecutor db) async {
    final rows = await db.query(
      'sync_metadata',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_deviceIdKey],
      limit: 1,
    );
    if (rows.isNotEmpty) return rows.first['value']! as String;
    final id = _uuid.v4();
    await db.insert('sync_metadata', {'key': _deviceIdKey, 'value': id});
    return id;
  }

  static Future<void> record(
    DatabaseExecutor db, {
    required String entityType,
    required String entityId,
    required String operation,
  }) async {
    final deviceId = await _ensureDeviceId(db);
    final rows = await db.query(
      'sync_metadata',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_sequenceKey],
      limit: 1,
    );
    final previous = rows.isEmpty
        ? 0
        : int.tryParse(rows.first['value'] as String? ?? '') ?? 0;
    final next = previous + 1;
    await db.insert(
      'sync_metadata',
      {'key': _sequenceKey, 'value': '$next'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await db.insert('sync_operations', {
      'operation_id': _uuid.v4(),
      'device_id': deviceId,
      'sequence': next,
      'entity_type': entityType,
      'entity_id': entityId,
      'operation': operation,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'status': 'pending',
      'attempts': 0,
      'last_error': null,
      'next_attempt_at': null,
    });
  }

  static Future<SyncJournalStatus> status({Database? database}) async {
    final db = database ?? await SnoteDatabase.open();
    return db.transaction((tx) async {
      final deviceId = await _ensureDeviceId(tx);
      final counts = await tx.rawQuery(
        "SELECT COUNT(*) AS total FROM sync_operations WHERE status = 'pending'",
      );
      final rows = await tx.query(
        'sync_metadata',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: [_sequenceKey],
        limit: 1,
      );
      final sequence = rows.isEmpty
          ? 0
          : int.tryParse(rows.first['value'] as String? ?? '') ?? 0;
      return SyncJournalStatus(
        deviceId: deviceId,
        pendingOperations: (counts.first['total'] as num?)?.toInt() ?? 0,
        lastSequence: sequence,
      );
    });
  }

  /// Requeues leases left behind by a killed process.
  static Future<int> recoverExpiredLeases({
    DateTime? now,
    Database? database,
  }) async {
    final db = database ?? await SnoteDatabase.open();
    final timestamp = (now ?? DateTime.now()).millisecondsSinceEpoch;
    return db.update(
      'sync_operations',
      {'status': 'pending', 'lease_id': null, 'lease_until': null},
      where: "status = 'in_progress' AND lease_until <= ?",
      whereArgs: [timestamp],
    );
  }

  /// Atomically reserves only operations whose retry delay has elapsed.
  static Future<SyncJournalLease> claimPending({
    int limit = 50,
    Duration leaseDuration = const Duration(minutes: 2),
    DateTime? now,
    Database? database,
  }) async {
    final db = database ?? await SnoteDatabase.open();
    final timestamp = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final leaseId = _uuid.v4();
    return db.transaction((tx) async {
      await tx.update(
        'sync_operations',
        {'status': 'pending', 'lease_id': null, 'lease_until': null},
        where: "status = 'in_progress' AND lease_until <= ?",
        whereArgs: [timestamp],
      );
      // Never skip an earlier unacknowledged operation: doing so would
      // create a sequence gap that a remote device cannot safely checkpoint.
      final outstanding = await tx.query(
        'sync_operations',
        where: "status != 'uploaded'",
        orderBy: 'sequence ASC',
        limit: 500,
      );
      if (outstanding.isEmpty ||
          outstanding.first['status'] != 'pending' ||
          ((outstanding.first['next_attempt_at'] as num?)?.toInt() ?? 0) > timestamp) {
        return SyncJournalLease(id: leaseId, operations: const []);
      }

      final firstSequence = (outstanding.first['sequence'] as num).toInt();
      final rows = <Map<String, Object?>>[];
      var expectedSequence = firstSequence;
      for (final operation in outstanding) {
        final sequence = (operation['sequence'] as num).toInt();
        if (sequence != expectedSequence || operation['status'] != 'pending') break;
        final retryAt = (operation['next_attempt_at'] as num?)?.toInt() ?? 0;
        if (retryAt > timestamp) break;
        rows.add(operation);
        expectedSequence++;
        if (rows.length >= limit.clamp(1, 500).toInt()) break;
      }
      if (rows.isEmpty) {
        return SyncJournalLease(id: leaseId, operations: const []);
      }
      final ids = rows.map((row) => row['operation_id'] as String).toList();
      final placeholders = List.filled(ids.length, '?').join(',');
      await tx.rawUpdate(
        "UPDATE sync_operations SET status = 'in_progress', lease_id = ?, lease_until = ?, next_attempt_at = NULL, attempts = attempts + 1 WHERE status = 'pending' AND operation_id IN ($placeholders)",
        [leaseId, timestamp + leaseDuration.inMilliseconds, ...ids],
      );
      final claimed = await tx.query(
        'sync_operations',
        where: 'lease_id = ? AND status = ?',
        whereArgs: [leaseId, 'in_progress'],
        orderBy: 'sequence ASC',
      );
      return SyncJournalLease(id: leaseId, operations: claimed);
    });
  }

  /// Extends a live lease. A worker must renew before the old expiry.
  static Future<int> renewLease(
    SyncJournalLease lease, {
    Duration leaseDuration = const Duration(minutes: 2),
    DateTime? now,
    Database? database,
  }) async {
    if (lease.operations.isEmpty) return 0;
    final db = database ?? await SnoteDatabase.open();
    final ids = lease.operations.map((row) => row['operation_id'] as String).toList();
    final placeholders = List.filled(ids.length, '?').join(',');
    final timestamp = (now ?? DateTime.now()).millisecondsSinceEpoch;
    return db.rawUpdate(
      "UPDATE sync_operations SET lease_until = ? WHERE lease_id = ? AND status = 'in_progress' AND lease_until > ? AND operation_id IN ($placeholders)",
      [timestamp + leaseDuration.inMilliseconds, lease.id, timestamp, ...ids],
    );
  }

  /// Acknowledge only rows owned by this lease; repeated acknowledgements are safe.
  static Future<int> acknowledge(
    SyncJournalLease lease, {
    Database? database,
  }) async {
    if (lease.operations.isEmpty) return 0;
    final db = database ?? await SnoteDatabase.open();
    final ids = lease.operations.map((row) => row['operation_id'] as String).toList();
    final placeholders = List.filled(ids.length, '?').join(',');
    return db.rawUpdate(
      "UPDATE sync_operations SET status = 'uploaded', lease_id = NULL, lease_until = NULL, next_attempt_at = NULL, last_error = NULL WHERE lease_id = ? AND operation_id IN ($placeholders)",
      [lease.id, ...ids],
    );
  }

  /// Return a failed batch to pending with capped exponential backoff.
  static Future<int> release(
    SyncJournalLease lease, {
    required String error,
    DateTime? now,
    Database? database,
  }) async {
    if (lease.operations.isEmpty) return 0;
    final db = database ?? await SnoteDatabase.open();
    final safeError = error.length > 1000 ? error.substring(0, 1000) : error;
    final timestamp = (now ?? DateTime.now()).millisecondsSinceEpoch;
    return db.transaction((tx) async {
      var released = 0;
      for (final operation in lease.operations) {
        final id = operation['operation_id'] as String;
        final attempts = (operation['attempts'] as num?)?.toInt() ?? 1;
        final exponent = (attempts - 1).clamp(0, 10);
        final delayMs = (1000 * (1 << exponent))
            .clamp(1000, _maximumRetryDelay.inMilliseconds)
            .toInt();
        released += await tx.update(
          'sync_operations',
          {
            'status': 'pending',
            'lease_id': null,
            'lease_until': null,
            'next_attempt_at': timestamp + delayMs,
            'last_error': safeError,
          },
          where: "lease_id = ? AND operation_id = ? AND status = 'in_progress'",
          whereArgs: [lease.id, id],
        );
      }
      return released;
    });
  }

  static Future<List<Map<String, Object?>>> pending({
    int limit = 100,
    Database? database,
  }) async {
    final db = database ?? await SnoteDatabase.open();
    return db.query(
      'sync_operations',
      where: "status = 'pending'",
      orderBy: 'sequence ASC',
      limit: limit.clamp(1, 1000).toInt(),
    );
  }
}

class SyncJournalStatus {
  const SyncJournalStatus({
    required this.deviceId,
    required this.pendingOperations,
    required this.lastSequence,
  });

  final String deviceId;
  final int pendingOperations;
  final int lastSequence;
}

class SyncJournalLease {
  const SyncJournalLease({required this.id, required this.operations});
  final String id;
  final List<Map<String, Object?>> operations;
}
