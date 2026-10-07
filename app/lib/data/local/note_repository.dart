import 'dart:convert';

import 'package:flutter/foundation.dart' show compute;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'database.dart';
import '../../core/config/account_scope.dart';

String _encodeNoteContent(Map<String, Object?> content) => jsonEncode(content);

class LocalNote {
  final String id;
  final String title;
  final String? folderId;
  final String noteType;
  final String? contentJson;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;
  final int version;

  const LocalNote({
    required this.id,
    required this.title,
    this.folderId,
    required this.noteType,
    this.contentJson,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.version,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'owner_id': SnoteAccountScope.ownerId,
        'title': title,
        'folder_id': folderId,
        'note_type': noteType,
        'content_json': contentJson,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'deleted_at': deletedAt,
        'version': version,
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
        version: (m['version'] as num?)?.toInt() ?? 1,
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
        'version': version,
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
      title: title.trim().isEmpty ? 'Untitled note' : title.trim(),
      folderId: folderId,
      noteType: 'handwriting',
      createdAt: now,
      updatedAt: now,
      version: 1,
    );

    final db = await _db;

    await db.transaction((tx) async {
      await tx.insert('notes', note.toMap());
      await _queue(tx, note.id, 'upsert');
    });

    return note;
  }

  Future<LocalNote?> get(String id) async {
    final db = await _db;
    final rows = await db.query(
      'notes',
      where: 'id = ? AND owner_id = ?',
      whereArgs: [id, SnoteAccountScope.ownerId],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return LocalNote.fromMap(rows.first);
  }

  Future<List<LocalNote>> list({String? folderId}) async {
    final db = await _db;

    final whereParts = <String>['owner_id = ?', 'deleted_at IS NULL'];
    final args = <Object?>[SnoteAccountScope.ownerId];

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
      where: 'owner_id = ? AND deleted_at IS NULL',
      whereArgs: [SnoteAccountScope.ownerId],
      orderBy: 'updated_at DESC',
    );
    return rows.map(LocalNote.fromMap).toList();
  }

  Future<void> saveContent(
    String id,
    Map<String, Object?> content,
  ) async {
    final encoded = await compute(_encodeNoteContent, content);
    final db = await _db;

    await db.transaction((tx) async {
      final rows = await tx.query(
        'notes',
        columns: ['version'],
        where: 'id = ? AND owner_id = ?',
        whereArgs: [id, SnoteAccountScope.ownerId],
        limit: 1,
      );
      if (rows.isEmpty) return;

      final currentVersion =
          (rows.first['version'] as num?)?.toInt() ?? 1;

      await tx.update(
        'notes',
        {
          'owner_id': SnoteAccountScope.ownerId,
          'content_json': encoded,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
          'version': currentVersion + 1,
          'sync_state': 'pending',
          'deleted_at': null,
        },
        where: 'id = ? AND owner_id = ?',
        whereArgs: [id, SnoteAccountScope.ownerId],
      );

      await _queue(tx, id, 'upsert');
    });
  }

  Future<void> rename(String id, String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;

    final db = await _db;

    await db.transaction((tx) async {
      await tx.update(
        'notes',
        {
          'title': trimmed,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
          'sync_state': 'pending',
        },
        where: 'id = ? AND owner_id = ?',
        whereArgs: [id, SnoteAccountScope.ownerId],
      );
      await _queue(tx, id, 'upsert');
    });
  }

  Future<void> moveToFolder(String id, String? folderId) async {
    final db = await _db;

    await db.transaction((tx) async {
      await tx.update(
        'notes',
        {
          'folder_id': folderId,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
          'sync_state': 'pending',
        },
        where: 'id = ? AND owner_id = ?',
        whereArgs: [id, SnoteAccountScope.ownerId],
      );
      await _queue(tx, id, 'upsert');
    });
  }


  Future<List<LocalNote>> listTrash() async {
    final db = await _db;
    await purgeExpiredTrash();
    final rows = await db.query(
      'notes',
      where: 'owner_id = ? AND deleted_at IS NOT NULL',
      whereArgs: [SnoteAccountScope.ownerId],
      orderBy: 'deleted_at DESC',
    );
    return rows.map(LocalNote.fromMap).toList();
  }


  Future<void> permanentlyDelete(String id) async {
    final db = await _db;
    await db.transaction((tx) async {
      await tx.delete(
        'sync_queue',
        where: 'entity_id = ? AND owner_id = ?',
        whereArgs: [id, SnoteAccountScope.ownerId],
      );
      await tx.delete(
        'attachments',
        where: 'note_id = ?',
        whereArgs: [id],
      );
      await tx.delete(
        'pages',
        where: 'note_id = ?',
        whereArgs: [id],
      );
      await tx.delete(
        'notes',
        where: 'id = ? AND owner_id = ?',
        whereArgs: [id, SnoteAccountScope.ownerId],
      );
    });
  }

  Future<void> restore(String id) async {
    final db = await _db;
    await db.transaction((tx) async {
      await tx.update(
        'notes',
        {
          'deleted_at': null,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
          'sync_state': 'pending',
        },
        where: 'id = ? AND owner_id = ?',
        whereArgs: [id, SnoteAccountScope.ownerId],
      );
      await _queue(tx, id, 'upsert');
    });
  }

  Future<void> purgeExpiredTrash() async {
    final db = await _db;
    final cutoff = DateTime.now().subtract(const Duration(days: 30)).millisecondsSinceEpoch;
    await db.delete(
      'notes',
      where: 'owner_id = ? AND deleted_at IS NOT NULL AND deleted_at < ?',
      whereArgs: [SnoteAccountScope.ownerId, cutoff],
    );
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
        where: 'id = ? AND owner_id = ?',
        whereArgs: [id, SnoteAccountScope.ownerId],
      );
      await _queue(tx, id, 'delete');
    });
  }

  Future<List<Map<String, Object?>>> pendingQueue() async {
    final db = await _db;
    return db.query(
      'sync_queue',
      where: 'owner_id = ?',
      whereArgs: [SnoteAccountScope.ownerId],
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
        where: 'id = ? AND owner_id = ?',
        whereArgs: [noteId, SnoteAccountScope.ownerId],
      );
      await tx.delete(
        'sync_queue',
        where: 'entity_type = ? AND entity_id = ? AND owner_id = ?',
        whereArgs: ['note', noteId, SnoteAccountScope.ownerId],
      );
    });
  }

  Future<void> applyRemote(Map<String, dynamic> remote) async {
    final id = remote['id']?.toString();
    if (id == null || id.isEmpty) return;

    DateTime? parseDate(Object? value) =>
        value == null ? null : DateTime.tryParse(value.toString());

    final updatedDate = parseDate(remote['updated_at']);
    if (updatedDate == null) return;

    final updated = updatedDate.millisecondsSinceEpoch;
    final local = await get(id);

    if (local != null && local.updatedAt > updated) return;

    final created =
        parseDate(remote['created_at'])?.millisecondsSinceEpoch ?? updated;
    final deleted =
        parseDate(remote['deleted_at'])?.millisecondsSinceEpoch;

    final db = await _db;

    await db.insert(
      'notes',
      {
        'id': id,
        'owner_id': SnoteAccountScope.ownerId,
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
      where: 'entity_type = ? AND entity_id = ? AND owner_id = ?',
      whereArgs: ['note', id, SnoteAccountScope.ownerId],
    );
  }

  Future<void> _queue(
    DatabaseExecutor db,
    String id,
    String operation,
  ) async {
    await db.delete(
      'sync_queue',
      where: 'entity_type = ? AND entity_id = ? AND owner_id = ?',
      whereArgs: ['note', id, SnoteAccountScope.ownerId],
    );

    await db.insert(
      'sync_queue',
      {
        'id': _uuid.v4(),
        'owner_id': SnoteAccountScope.ownerId,
        'entity_type': 'note',
        'entity_id': id,
        'operation': operation,
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'attempts': 0,
      },
    );
  }
}
