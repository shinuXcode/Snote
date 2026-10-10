import 'package:sqflite/sqflite.dart';

import '../../core/config/account_scope.dart';
import 'database.dart';

class AppNotification {
  final String id;
  final String category;
  final String title;
  final String body;
  final int createdAt;
  final int? readAt;
  final String? actionUrl;

  const AppNotification({
    required this.id,
    required this.category,
    required this.title,
    required this.body,
    required this.createdAt,
    this.readAt,
    this.actionUrl,
  });

  bool get isRead => readAt != null;

  factory AppNotification.fromMap(Map<String, Object?> row) => AppNotification(
        id: row['id']! as String,
        category: row['category']! as String,
        title: row['title']! as String,
        body: row['body']! as String,
        createdAt: (row['created_at']! as num).toInt(),
        readAt: (row['read_at'] as num?)?.toInt(),
        actionUrl: row['action_url'] as String?,
      );
}

/// A persistent local-first inbox. Stable identifiers make release checks
/// idempotent rather than adding the same notification on every refresh.
class NotificationRepository {
  Future<Database> get _db => SnoteDatabase.open();

  Future<void> addOnce({
    required String id,
    required String category,
    required String title,
    required String body,
    String? actionUrl,
  }) async {
    final db = await _db;
    await db.insert(
      'app_notifications',
      {
        'id': id,
        'owner_id': SnoteAccountScope.ownerId,
        'category': category,
        'title': title,
        'body': body,
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'read_at': null,
        'action_url': actionUrl,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<AppNotification>> list({int limit = 100}) async {
    final db = await _db;
    final rows = await db.query(
      'app_notifications',
      where: 'owner_id = ?',
      whereArgs: [SnoteAccountScope.ownerId],
      orderBy: 'created_at DESC',
      limit: limit.clamp(1, 500).toInt(),
    );
    return rows.map(AppNotification.fromMap).toList();
  }

  Future<void> markRead(String id) async {
    final db = await _db;
    await db.update(
      'app_notifications',
      {'read_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ? AND owner_id = ? AND read_at IS NULL',
      whereArgs: [id, SnoteAccountScope.ownerId],
    );
  }

  Future<void> markAllRead() async {
    final db = await _db;
    await db.update(
      'app_notifications',
      {'read_at': DateTime.now().millisecondsSinceEpoch},
      where: 'owner_id = ? AND read_at IS NULL',
      whereArgs: [SnoteAccountScope.ownerId],
    );
  }

  Future<void> dismiss(String id) async {
    final db = await _db;
    await db.delete(
      'app_notifications',
      where: 'id = ? AND owner_id = ?',
      whereArgs: [id, SnoteAccountScope.ownerId],
    );
  }
}
