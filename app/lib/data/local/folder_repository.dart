import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/config/account_scope.dart';
import 'database.dart';

const defaultFolderColor = 0xff5b6cf9;

class LocalFolder {
  final String id;
  final String? parentId;
  final String name;
  final int colorValue;
  final String iconKey;
  final int sortOrder;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;

  const LocalFolder({
    required this.id,
    this.parentId,
    required this.name,
    this.colorValue = defaultFolderColor,
    this.iconKey = 'folder',
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  factory LocalFolder.fromMap(Map<String, Object?> map) => LocalFolder(
        id: map['id']! as String,
        parentId: map['parent_id'] as String?,
        name: map['name']! as String,
        colorValue:
            (map['color_value'] as num?)?.toInt() ?? defaultFolderColor,
        iconKey: map['icon_key']?.toString() ?? 'folder',
        sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
        createdAt: (map['created_at']! as num).toInt(),
        updatedAt: (map['updated_at']! as num).toInt(),
        deletedAt: (map['deleted_at'] as num?)?.toInt(),
      );

  Map<String, Object?> toExport() => {
        'id': id,
        'parentId': parentId,
        'name': name,
        'colorValue': colorValue,
        'iconKey': iconKey,
        'sortOrder': sortOrder,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };
}

class FolderRepository {
  static const _uuid = Uuid();

  Future<Database> get _db => SnoteDatabase.open();

  Future<LocalFolder> create({
    required String name,
    String? parentId,
    int colorValue = defaultFolderColor,
    String iconKey = 'folder',
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Folder name cannot be empty.');
    }

    final db = await _db;
    final now = DateTime.now().millisecondsSinceEpoch;
    final folder = LocalFolder(
      id: _uuid.v4(),
      parentId: parentId,
      name: normalizedName,
      colorValue: colorValue,
      iconKey: _normalizeIconKey(iconKey),
      createdAt: now,
      updatedAt: now,
    );

    await db.transaction((tx) async {
      if (parentId != null) await _requireActiveFolder(tx, parentId);
      final siblings = await tx.rawQuery(
        'SELECT COALESCE(MAX(sort_order), -1) + 1 AS next_order '
        'FROM folders WHERE owner_id = ? AND parent_id IS ? AND deleted_at IS NULL',
        [SnoteAccountScope.ownerId, parentId],
      );
      final order = (siblings.first['next_order'] as num?)?.toInt() ?? 0;
      await tx.insert('folders', {
        'id': folder.id,
        'owner_id': SnoteAccountScope.ownerId,
        'parent_id': parentId,
        'name': folder.name,
        'color_value': folder.colorValue,
        'icon_key': folder.iconKey,
        'sort_order': order,
        'created_at': now,
        'updated_at': now,
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
          ? 'owner_id = ? AND parent_id IS NULL AND deleted_at IS NULL'
          : 'owner_id = ? AND parent_id = ? AND deleted_at IS NULL',
      whereArgs: parentId == null
          ? [SnoteAccountScope.ownerId]
          : [SnoteAccountScope.ownerId, parentId],
      orderBy: 'sort_order ASC, name COLLATE NOCASE ASC',
    );
    return rows.map(LocalFolder.fromMap).toList();
  }

  Future<List<LocalFolder>> listAllVisible() async {
    final db = await _db;
    final rows = await db.query(
      'folders',
      where: 'owner_id = ? AND deleted_at IS NULL',
      whereArgs: [SnoteAccountScope.ownerId],
      orderBy: 'sort_order ASC, name COLLATE NOCASE ASC',
    );
    return rows.map(LocalFolder.fromMap).toList();
  }

  Future<LocalFolder?> get(String id) async {
    final db = await _db;
    final rows = await db.query(
      'folders',
      where: 'id = ? AND owner_id = ? AND deleted_at IS NULL',
      whereArgs: [id, SnoteAccountScope.ownerId],
      limit: 1,
    );
    return rows.isEmpty ? null : LocalFolder.fromMap(rows.first);
  }

  Future<void> rename(String id, String name) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) return;
    final db = await _db;
    await db.transaction((tx) async {
      final count = await tx.update(
        'folders',
        {
          'name': normalizedName,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ? AND owner_id = ? AND deleted_at IS NULL',
        whereArgs: [id, SnoteAccountScope.ownerId],
      );
      if (count > 0) await _queue(tx, id, 'upsert');
    });
  }

  Future<void> updateAppearance(
    String id, {
    required int colorValue,
    required String iconKey,
  }) async {
    final db = await _db;
    await db.transaction((tx) async {
      final count = await tx.update(
        'folders',
        {
          'color_value': colorValue,
          'icon_key': _normalizeIconKey(iconKey),
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ? AND owner_id = ? AND deleted_at IS NULL',
        whereArgs: [id, SnoteAccountScope.ownerId],
      );
      if (count > 0) await _queue(tx, id, 'upsert');
    });
  }

  /// Moves a folder to the root or inside another folder, rejecting cycles.
  Future<void> move(String id, {String? parentId}) async {
    if (id == parentId) {
      throw ArgumentError('A folder cannot be moved inside itself.');
    }

    final db = await _db;
    await db.transaction((tx) async {
      await _requireActiveFolder(tx, id);
      if (parentId != null) {
        await _requireActiveFolder(tx, parentId);
        final visited = <String>{};
        String? ancestor = parentId;
        while (ancestor != null) {
          if (ancestor == id) {
            throw StateError('Moving this folder would create a cycle.');
          }
          if (!visited.add(ancestor)) {
            throw StateError('The folder hierarchy already contains a cycle.');
          }
          final rows = await tx.query(
            'folders',
            columns: ['parent_id'],
            where: 'id = ? AND owner_id = ? AND deleted_at IS NULL',
            whereArgs: [ancestor, SnoteAccountScope.ownerId],
            limit: 1,
          );
          if (rows.isEmpty) {
            throw StateError('The destination folder no longer exists.');
          }
          ancestor = rows.first['parent_id'] as String?;
        }
      }

      final siblings = await tx.rawQuery(
        'SELECT COALESCE(MAX(sort_order), -1) + 1 AS next_order '
        'FROM folders WHERE owner_id = ? AND parent_id IS ? AND deleted_at IS NULL',
        [SnoteAccountScope.ownerId, parentId],
      );
      final order = (siblings.first['next_order'] as num?)?.toInt() ?? 0;
      await tx.update(
        'folders',
        {
          'parent_id': parentId,
          'sort_order': order,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ? AND owner_id = ? AND deleted_at IS NULL',
        whereArgs: [id, SnoteAccountScope.ownerId],
      );
      await _queue(tx, id, 'upsert');
    });
  }

  Future<void> reorder(String id, int sortOrder) async {
    final db = await _db;
    await db.transaction((tx) async {
      final count = await tx.update(
        'folders',
        {
          'sort_order': sortOrder,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ? AND owner_id = ? AND deleted_at IS NULL',
        whereArgs: [id, SnoteAccountScope.ownerId],
      );
      if (count > 0) await _queue(tx, id, 'upsert');
    });
  }

  Future<void> delete(String id) async {
    final db = await _db;
    await db.transaction((tx) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final folderIds = <String>[];
      await _collectDescendants(tx, id, folderIds);
      if (folderIds.isEmpty) return;

      final placeholders = List.filled(folderIds.length, '?').join(',');
      final notes = await tx.query(
        'notes',
        columns: ['id'],
        where: 'owner_id = ? AND deleted_at IS NULL AND folder_id IN ($placeholders)',
        whereArgs: [SnoteAccountScope.ownerId, ...folderIds],
      );
      await tx.update(
        'notes',
        {
          'folder_id': null,
          'updated_at': now,
          'sync_state': 'pending',
        },
        where: 'owner_id = ? AND deleted_at IS NULL AND folder_id IN ($placeholders)',
        whereArgs: [SnoteAccountScope.ownerId, ...folderIds],
      );
      for (final row in notes) {
        await queueNote(tx, row['id']! as String, 'upsert');
      }
      await _deleteRecursive(tx, id, now, <String>{});
    });
  }

  Future<void> _collectDescendants(
    DatabaseExecutor tx,
    String id,
    List<String> output,
  ) async {
    if (output.contains(id)) return;
    final current = await tx.query(
      'folders',
      columns: ['id'],
      where: 'id = ? AND owner_id = ? AND deleted_at IS NULL',
      whereArgs: [id, SnoteAccountScope.ownerId],
      limit: 1,
    );
    if (current.isEmpty) return;
    output.add(id);
    final children = await tx.query(
      'folders',
      columns: ['id'],
      where: 'owner_id = ? AND parent_id = ? AND deleted_at IS NULL',
      whereArgs: [SnoteAccountScope.ownerId, id],
    );
    for (final child in children) {
      await _collectDescendants(tx, child['id']! as String, output);
    }
  }

  Future<void> _deleteRecursive(
    DatabaseExecutor tx,
    String id,
    int now,
    Set<String> visited,
  ) async {
    if (!visited.add(id)) return;
    final children = await tx.query(
      'folders',
      columns: ['id'],
      where: 'owner_id = ? AND parent_id = ? AND deleted_at IS NULL',
      whereArgs: [SnoteAccountScope.ownerId, id],
    );
    for (final child in children) {
      await _deleteRecursive(tx, child['id']! as String, now, visited);
    }
    await tx.update(
      'folders',
      {'deleted_at': now, 'updated_at': now},
      where: 'id = ? AND owner_id = ? AND deleted_at IS NULL',
      whereArgs: [id, SnoteAccountScope.ownerId],
    );
    await _queue(tx, id, 'delete');
  }

  Future<void> _requireActiveFolder(DatabaseExecutor tx, String id) async {
    final rows = await tx.query(
      'folders',
      columns: ['id'],
      where: 'id = ? AND owner_id = ? AND deleted_at IS NULL',
      whereArgs: [id, SnoteAccountScope.ownerId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw ArgumentError.value(id, 'folderId', 'Folder not found.');
    }
  }

  String _normalizeIconKey(String value) {
    const known = {
      'folder',
      'book',
      'science',
      'math',
      'star',
      'lightbulb',
      'work',
      'archive',
    };
    if (known.contains(value)) return value;
    final coverMatch = RegExp(r'^cover:(\d{1,2})$').firstMatch(value);
    final coverIndex = int.tryParse(coverMatch?.group(1) ?? '');
    if (coverIndex != null && coverIndex >= 0 && coverIndex < 100) {
      return 'cover:$coverIndex';
    }
    return 'folder';
  }

  Future<void> _queue(DatabaseExecutor db, String id, String operation) async {
    await db.delete(
      'sync_queue',
      where: 'entity_type = ? AND entity_id = ? AND owner_id = ?',
      whereArgs: ['folder', id, SnoteAccountScope.ownerId],
    );
    await db.insert('sync_queue', {
      'id': _uuid.v4(),
      'owner_id': SnoteAccountScope.ownerId,
      'entity_type': 'folder',
      'entity_id': id,
      'operation': operation,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'attempts': 0,
    });
  }

  Future<void> queueNote(
    DatabaseExecutor db,
    String noteId,
    String operation,
  ) async {
    await db.delete(
      'sync_queue',
      where: 'entity_type = ? AND entity_id = ? AND owner_id = ?',
      whereArgs: ['note', noteId, SnoteAccountScope.ownerId],
    );
    await db.insert('sync_queue', {
      'id': _uuid.v4(),
      'owner_id': SnoteAccountScope.ownerId,
      'entity_type': 'note',
      'entity_id': noteId,
      'operation': operation,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'attempts': 0,
    });
  }
}
