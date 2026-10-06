import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'database.dart';

class LocalNote {
  final String id;
  final String title;
  final String? folderId;
  final String noteType;
  final String? contentJson;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;

  const LocalNote({
    required this.id,
    required this.title,
    this.folderId,
    required this.noteType,
    this.contentJson,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'folder_id': folderId,
        'note_type': noteType,
        'content_json': contentJson,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'deleted_at': deletedAt,
        'version': 1,
        'sync_state': 'pending',
      };

  factory LocalNote.fromMap(Map<String, Object?> m) => LocalNote(
        id: m['id']! as String,
        title: m['title']! as String,
        folderId: m['folder_id'] as String?,
        noteType: m['note_type']! as String,
        contentJson: m['content_json'] as String?,
        createdAt: (m['created_at']! as num).toInt(),
        updatedAt: (m['updated_at']! as num).toInt(),
        deletedAt: (m['deleted_at'] as num?)?.toInt(),
      );

  Map<String, Object?> toRemote(String userId) => {
        'id': id,
        'user_id': userId,
        'title': title,
        'folder_id': folderId,
        'note_type': noteType,
        'content_json':
            contentJson == null ? null : jsonDecode(contentJson!),
        'created_at': DateTime.fromMillisecondsSinceEpoch(
          createdAt,
        ).toUtc().toIso8601String(),
        'updated_at': DateTime.fromMillisecondsSinceEpoch(
          updatedAt,
        ).toUtc().toIso8601String(),
        'version': 1,
        'deleted_at': deletedAt == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                deletedAt!,
              ).toUtc().toIso8601String(),
      };
}

class NoteRepository {
  static const _uuid = Uuid();

  Future<Database> get _db => SnoteDatabase.open();

  Future<LocalNote> create({
    String title = 'Untitled note',
    String? folderId,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final note = LocalNote(
      id: _uuid.v4(),
      title: title,
      folderId: folderId,
      noteType: 'handwriting',
      createdAt: now,
      updatedAt: now,
    );

    final db = await _db;

    await db.transaction((tx) async {
      await tx.insert('notes', note.toMap());
      await _queue(
        tx,
        note.id,
        'upsert',
      );
    });

    return note;
  }

  Future<LocalNote?> get(String id) async {
    final db = await _db;

    final rows = await db.query(
      'notes',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return LocalNote.fromMap(rows.first);
  }

  Future<List<LocalNote>> list({
    String? folderId,
  }) async {
    final db = await _db;

    final whereParts = <String>[
      'deleted_at IS NULL',
    ];
    final args = <Object?>[];

    if (folderId == null) {
      whereParts.add('folder_id IS NULL');
    } else {
      whereParts.add('folder_id = ?');
      args.add(folderId);
    }

    final rows = await db.query(
      'notes',
      where: whereParts.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'updated_at DESC',
    );

    return rows.map(LocalNote.fromMap).toList();
  }

  Future<List<LocalNote>> listAllVisible() async {
    final db = await _db;

    final rows = await db.query(
      'notes',
      where: 'deleted_at IS NULL',
      orderBy: 'updated_at DESC',
    );

    return rows.map(LocalNote.fromMap).toList();
  }

  Future<void> saveContent(
    String id,
    Map<String, Object?> content,
  ) async {
    final db = await _db;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((tx) async {
      await tx.update(
        'notes',
        {
          'content_json': jsonEncode(content),
          'updated_at': now,
          'version': 'version + 1',
          'sync_state': 'pending',
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      await _queue(tx, id, 'upsert');
    });
  }

  Future<void> rename(String id, String title) async {
    final db = await _db;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((tx) async {
      await tx.update(
        'notes',
        {
          'title': title.trim(),
          'updated_at': now,
          'sync_state': 'pending',
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      await _queue(tx, id, 'upsert');
    });
  }

  Future<void> moveToFolder(String id, String? folderId) async {
    final db = await _db;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((tx) async {
      await tx.update(
        'notes',
        {
          'folder_id': folderId,
          'updated_at': now,
          'sync_state': 'pending',
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      await _queue(tx, id, 'upsert');
    });
  }

  Future<void> delete(String id) async {
    final db = await _db;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((tx) async {
      await tx.update(
        'notes',
        {
          'deleted_at': now,
          'updated_at': now,
          'sync_state': 'pending',
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      await _queue(tx, id, 'delete');
    });
  }

  Future<List<Map<String, Object?>>> pendingQueue() async {
    final db = await _db;

    return db.query(
      'sync_queue',
      orderBy: 'created_at ASC',
      limit: 100,
    );
  }

  Future<void> markSynced(String noteId) async {
    final db = await _db;

    await db.transaction((tx) async {
      await tx.update(
        'notes',
        {'sync_state': 'synced'},
        where: 'id = ?',
        whereArgs: [noteId],
      );

      await tx.delete(
        'sync_queue',
        where: 'entity_type = ? AND entity_id = ?',
        whereArgs: ['note', noteId],
      );
    });
  }

  Future<void> applyRemote(Map<String, dynamic> remote) async {
    final id = remote['id']?.toString();
    if (id == null || id.isEmpty) return;

    final db = await _db;

    DateTime? parseDate(Object? value) {
      if (value == null) return null;
      return DateTime.tryParse(value.toString());
    }

    final updated =
        parseDate(remote['updated_at'])?.millisecondsSinceEpoch;
    if (updated == null) return;

    final local = await get(id);
    if (local != null && local.updatedAt > updated) return;

    final created =
        parseDate(remote['created_at'])?.millisecondsSinceEpoch ?? updated;
    final deleted =
        parseDate(remote['deleted_at'])?.millisecondsSinceEpoch;

    await db.insert(
      'notes',
      {
        'id': id,
        'title': remote['title']?.toString() ?? 'Untitled note',
        'folder_id': remote['folder_id']?.toString(),
        'note_type':
            remote['note_type']?.toString() ?? 'handwriting',
        'content_json': remote['content_json'] == null
            ? null
            : jsonEncode(remote['content_json']),
        'created_at': local?.createdAt ?? created,
        'updated_at': updated,
        'deleted_at': deleted,
        'version':
            (remote['version'] as num?)?.toInt() ?? 1,
        'sync_state': 'synced',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await db.delete(
      'sync_queue',
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: ['note', id],
    );
  }

  Future<void> _queue(
    DatabaseExecutor db,
    String id,
    String operation,
  ) async {
    await db.delete(
      'sync_queue',
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: ['note', id],
    );

    await db.insert(
      'sync_queue',
      {
        'id': _uuid.v4(),
        'entity_type': 'note',
        'entity_id': id,
        'operation': operation,
        'created_at':
            DateTime.now().millisecondsSinceEpoch,
        'attempts': 0,
      },
    );
  }
}
