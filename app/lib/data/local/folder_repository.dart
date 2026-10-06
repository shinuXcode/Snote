import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'database.dart';

class LocalFolder {
  final String id;
  final String? parentId;
  final String name;
  final int createdAt;
  final int updatedAt;

  const LocalFolder({
    required this.id,
    this.parentId,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
  });

  factory LocalFolder.fromMap(Map<String, Object?> map) => LocalFolder(
    id: map['id']! as String,
    parentId: map['parent_id'] as String?,
    name: map['name']! as String,
    createdAt: (map['created_at']! as num).toInt(),
    updatedAt: (map['updated_at']! as num).toInt(),
  );
}

class FolderRepository {
  static const _uuid = Uuid();

  Future<Database> get _db => SnoteDatabase.open();

  Future<LocalFolder> create({
    required String name,
    String? parentId,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final folder = LocalFolder(
      id: _uuid.v4(),
      parentId: parentId,
      name: name.trim(),
      createdAt: now,
      updatedAt: now,
    );

    final db = await _db;
    await db.insert('folders', {
      'id': folder.id,
      'parent_id': folder.parentId,
      'name': folder.name,
      'created_at': folder.createdAt,
      'updated_at': folder.updatedAt,
      'deleted_at': null,
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

  Future<void> rename(String id, String name) async {
    final db = await _db;
    await db.update(
      'folders',
      {
        'name': name.trim(),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
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

      await tx.update(
        'notes',
        {'deleted_at': now, 'updated_at': now},
        where: 'folder_id = ?',
        whereArgs: [id],
      );
    });
  }
}
