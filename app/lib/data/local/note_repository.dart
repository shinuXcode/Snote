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

  Future<List<LocalNote>> list({
    String? folderId,
    int? limit,
    int offset = 0,
  }) async {
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
      limit: limit == null ? null : limit.clamp(1, 10000).toInt(),
      offset: offset > 0 ? offset : null,
    );

    return rows.map(LocalNote.fromMap).toList();
  }

  Future<List<LocalNote>> listAllVisible({int? limit, int offset = 0}) async {
    final db = await _db;
    final rows = await db.query(
      'notes',
      where: 'owner_id = ? AND deleted_at IS NULL',
      whereArgs: [SnoteAccountScope.ownerId],
      orderBy: 'updated_at DESC',
      limit: limit == null ? null : limit.clamp(1, 10000).toInt(),
      offset: offset > 0 ? offset : null,
    );
    return rows.map(LocalNote.fromMap).toList();
  }

  /// Searches titles inside SQLite to avoid scanning and filtering every note
  /// in the UI isolate on each keystroke.
  Future<List<LocalNote>> searchVisible(String query, {int limit = 10000, int offset = 0}) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return listAllVisible(limit: limit, offset: offset);
    final db = await _db;
    final rows = await db.query(
      'notes',
      where: 'owner_id = ? AND deleted_at IS NULL AND title LIKE ?',
      whereArgs: [SnoteAccountScope.ownerId, '%$normalized%'],
      orderBy: 'updated_at DESC',
      limit: limit.clamp(1, 10000).toInt(),
      offset: offset > 0 ? offset : null,
    );
    return rows.map(LocalNote.fromMap).toList(growable: false);
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
                    'deleted_at': null,
        },
        where: 'id = ? AND owner_id = ?',
        whereArgs: [id, SnoteAccountScope.ownerId],
      );

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
                  },
        where: 'id = ? AND owner_id = ?',
        whereArgs: [id, SnoteAccountScope.ownerId],
      );
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
                  },
        where: 'id = ? AND owner_id = ?',
        whereArgs: [id, SnoteAccountScope.ownerId],
      );
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
                  },
        where: 'id = ? AND owner_id = ?',
        whereArgs: [id, SnoteAccountScope.ownerId],
      );
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
                  },
        where: 'id = ? AND owner_id = ?',
        whereArgs: [id, SnoteAccountScope.ownerId],
      );
    });
  }

}