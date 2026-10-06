import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'database.dart';

class LocalFolder {
  final String id;
  final String? parentId;
  final String name;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;

  const LocalFolder({
    required this.id,
    this.parentId,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  factory LocalFolder.fromMap(Map<String, Object?> map) => LocalFolder(
        id: map['id']! as String,
        parentId: map['parent_id'] as String?,
        name: map['name']! as String,
        createdAt: (map['created_at']! as num).toInt(),
        updatedAt: (map['updated_at']! as num).toInt(),
        deletedAt: (map['deleted_at'] as num?)?.toInt(),
      );

  Map<String, Object?> toRemote(String userId) => {
        'id': id,
        'user_id': userId,
        'parent_id': parentId,
        'name': name,
        'created_at': DateTime.fromMillisecondsSinceEpoch(createdAt)
            .toUtc()
            .toIso8601String(),
        'updated_at': DateTime.fromMillisecondsSinceEpoch(updatedAt)
            .toUtc()
            .toIso8601String(),
        'deleted_at': deletedAt == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(deletedAt!)
                .toUtc()
                .toIso8601String(),
      };
}

class FolderRepository {
  static const _uuid = Uuid();

  Future<Database> get _db => SnoteDatabase.open();

  Future<LocalFolder> create({
    required String name,
    String? parentId,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Folder name cannot be empty.');
    }

    final now = DateTime.now().millisecondsSinceEpoch;

    final folder = LocalFolder(
      id: _uuid.v4(),
      parentId: parentId,
      name: trimmed,
      createdAt: now,
      updatedAt: now,
    );

    final db = await _db;

    await db.transaction((tx) async {
      await tx.insert('folders', {
        'id': folder.id,
        'parent_id': folder.parentId,
        'name': folder.name,
        'created_at': folder.createdAt,
        'updated_at': folder.updatedAt,
        'deleted_at': null,
      });
      await _queue(tx, folder.id, 'upsert');
    });

    return folder;
  }

  Future<List<LocalFolder>> list({String? parentId}) async {
    final db = await _db;

    final rows = await db.query(
      'folders',
      where: parentId == null
          ? 'parent_id IS NULL AND deleted_at IS NULL'
          : 'parent_id = ? AND deleted_at IS NULL',
      whereArgs: parentId == null ? null : [parentId],
      orderBy: 'name COLLATE NOCASE ASC',
    );

    return rows.map(LocalFolder.fromMap).toList();
  }

  Future<LocalFolder?> get(String id) async {
    final db = await _db;

    final rows = await db.query(
      'folders',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return LocalFolder.fromMap(rows.first);
  }

  Future<void> rename(String id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;

    final db = await _db;

    await db.transaction((tx) async {
      await tx.update(
        'folders',
        {
          'name': trimmed,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      await _queue(tx, id, 'upsert');
    });
  }

  Future<void> delete(String id) async {
    final db = await _db;

    await db.transaction((tx) async {
      final now = DateTime.now().millisecondsSinceEpoch;

      await tx.update(
        'folders',
        {'deleted_at': now, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [id],
      );
      await _queue(tx, id, 'delete');

      final childFolders = await tx.query(
        'folders',
        columns: ['id'],
        where: 'parent_id = ? AND deleted_at IS NULL',
        whereArgs: [id],
      );

      for (final child in childFolders) {
        final childId = child['id'] as String;
        await tx.update(
          'folders',
          {'deleted_at': now, 'updated_at': now},
          where: 'id = ?',
          whereArgs: [childId],
        );
        await _queue(tx, childId, 'delete');
      }

      final childNotes = await tx.query(
        'notes',
        columns: ['id'],
        where: 'folder_id = ? AND deleted_at IS NULL',
        whereArgs: [id],
      );

      for (final note in childNotes) {
        final noteId = note['id'] as String;
        await tx.update(
          'notes',
          {
            'deleted_at': now,
            'updated_at': now,
            'sync_state': 'pending',
          },
          where: 'id = ?',
          whereArgs: [noteId],
        );
        await _queue(tx, noteId, 'delete');
      }
    });
  }

  Future<void> _queue(
    DatabaseExecutor db,
    String id,
    String operation,
  ) async {
    await db.delete(
      'sync_queue',
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: ['folder', id],
    );
    await db.insert(
      'sync_queue',
      {
        'id': _uuid.v4(),
        'entity_type': 'folder',
        'entity_id': id,
        'operation': operation,
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'attempts': 0,
      },
    );
  }

  Future<void> queueNote(
    DatabaseExecutor db,
    String noteId,
    String operation,
  ) async {
    await db.delete(
      'sync_queue',
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: ['note', noteId],
    );
    await db.insert(
      'sync_queue',
      {
        'id': _uuid.v4(),
        'entity_type': 'note',
        'entity_id': noteId,
        'operation': operation,
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'attempts': 0,
      },
    );
  }
}
