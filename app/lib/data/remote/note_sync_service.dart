import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../local/database.dart';
import '../../core/config/account_scope.dart';

class NoteSyncService {
  final SupabaseClient client;

  const NoteSyncService(this.client);

  Future<void> flush() async {
    final user = client.auth.currentUser;
    if (user == null) return;

    final db = await SnoteDatabase.open();
    final queue = await db.query(
      'sync_queue',
      where: 'owner_id = ?',
      whereArgs: [SnoteAccountScope.ownerId],
      orderBy: 'created_at ASC',
      limit: 50,
    );

    for (final item in queue) {
      try {
        final processed = await _process(db, user.id, item);

        if (processed) {
          await db.delete(
            'sync_queue',
            where: 'id = ? AND owner_id = ?',
            whereArgs: [item['id'], SnoteAccountScope.ownerId],
          );
        }
      } catch (e) {
        await db.update(
          'sync_queue',
          {
            'attempts':
                ((item['attempts'] as num?)?.toInt() ?? 0) + 1,
            'last_error': e.toString(),
          },
          where: 'id = ? AND owner_id = ?',
          whereArgs: [item['id'], SnoteAccountScope.ownerId],
        );
      }
    }
  }

  Future<bool> _process(
    Database db,
    String userId,
    Map<String, Object?> item,
  ) async {
    final type = item['entity_type']?.toString();
    final id = item['entity_id']?.toString();

    if (id == null || id.isEmpty) return true;

    switch (type) {
      case 'note':
        return _pushNote(db, userId, id);
      case 'folder':
        return _pushFolder(db, userId, id);
      default:
        return true;
    }
  }

  Future<bool> _pushNote(
    Database db,
    String userId,
    String id,
  ) async {
    final rows = await db.query(
      'notes',
      where: 'id = ? AND owner_id = ?',
      whereArgs: [id, SnoteAccountScope.ownerId],
      limit: 1,
    );

    if (rows.isEmpty) return true;

    final n = rows.first;
    final createdAt = DateTime.fromMillisecondsSinceEpoch(
      (n['created_at']! as num).toInt(),
    ).toUtc();

    final updatedAt = DateTime.fromMillisecondsSinceEpoch(
      (n['updated_at']! as num).toInt(),
    ).toUtc();

    final deleted = n['deleted_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            (n['deleted_at']! as num).toInt(),
          ).toUtc();

    final payload = {
      'id': id,
      'user_id': userId,
      'title': n['title'],
      'folder_id': n['folder_id'],
      'note_type': n['note_type'],
      'content_json': n['content_json'] == null
          ? null
          : jsonDecode(n['content_json']! as String),
      'created_at': createdAt.toIso8601String(),
      'version':
          (n['version'] as num?)?.toInt() ?? 1,
      'updated_at': updatedAt.toIso8601String(),
      'deleted_at': deleted?.toIso8601String(),
    };

    await client.from('notes').upsert(
      payload,
      onConflict: 'id',
    );

    if (deleted != null) {
      await db.delete(
        'notes',
        where: 'id = ? AND owner_id = ? AND deleted_at IS NOT NULL',
        whereArgs: [id, SnoteAccountScope.ownerId],
      );
    } else {
      await db.update(
        'notes',
        {'sync_state': 'synced'},
        where: 'id = ? AND owner_id = ?',
        whereArgs: [id, SnoteAccountScope.ownerId],
      );
    }

    return true;
  }

  Future<bool> _pushFolder(
    Database db,
    String userId,
    String id,
  ) async {
    final rows = await db.query(
      'folders',
      where: 'id = ? AND owner_id = ?',
      whereArgs: [id, SnoteAccountScope.ownerId],
      limit: 1,
    );

    if (rows.isEmpty) return true;

    final folder = rows.first;

    final createdAt = DateTime.fromMillisecondsSinceEpoch(
      (folder['created_at']! as num).toInt(),
    ).toUtc();

    final updatedAt = DateTime.fromMillisecondsSinceEpoch(
      (folder['updated_at']! as num).toInt(),
    ).toUtc();

    final deleted = folder['deleted_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            (folder['deleted_at']! as num).toInt(),
          ).toUtc();

    await client.from('folders').upsert(
      {
        'id': id,
        'user_id': userId,
        'parent_id': folder['parent_id'],
        'name': folder['name'],
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'deleted_at': deleted?.toIso8601String(),
      },
      onConflict: 'id',
    );

    return true;
  }

  Future<void> pullLatest() async {
    final user = client.auth.currentUser;
    if (user == null) return;

    final db = await SnoteDatabase.open();

    final remoteNotes = await client
        .from('notes')
        .select()
        .eq('user_id', user.id)
        .order('updated_at', ascending: true);

    for (final remote
        in (remoteNotes as List).whereType<Map<String, dynamic>>()) {
      await _applyRemoteNote(db, remote);
    }

    final remoteFolders = await client
        .from('folders')
        .select()
        .eq('user_id', user.id)
        .order('updated_at', ascending: true);

    for (final remote
        in (remoteFolders as List).whereType<Map<String, dynamic>>()) {
      await _applyRemoteFolder(db, remote);
    }
  }

  Future<void> _applyRemoteNote(
    Database db,
    Map<String, dynamic> remote,
  ) async {
    final id = remote['id']?.toString();
    if (id == null || id.isEmpty) return;

    DateTime? parseDate(Object? value) =>
        value == null ? null : DateTime.tryParse(value.toString());

    final updatedDate = parseDate(remote['updated_at']);
    if (updatedDate == null) return;

    final updated = updatedDate.millisecondsSinceEpoch;

    final local = await db.query(
      'notes',
      where: 'id = ? AND owner_id = ?',
      whereArgs: [id, SnoteAccountScope.ownerId],
      limit: 1,
    );

    if (local.isNotEmpty &&
        (local.first['updated_at'] as num).toInt() >= updated) {
      return;
    }

    final created =
        parseDate(remote['created_at'])?.millisecondsSinceEpoch ?? updated;

    await db.insert(
      'notes',
      {
        'id': id,
        'owner_id': SnoteAccountScope.ownerId,
        'title': remote['title']?.toString() ?? 'Untitled note',
        'folder_id': remote['folder_id'],
        'note_type':
            remote['note_type']?.toString() ?? 'handwriting',
        'content_json': remote['content_json'] == null
            ? null
            : jsonEncode(remote['content_json']),
        'created_at': local.isNotEmpty
            ? (local.first['created_at'] as num).toInt()
            : created,
        'updated_at': updated,
        'deleted_at': remote['deleted_at'] == null
            ? null
            : parseDate(remote['deleted_at'])?.millisecondsSinceEpoch,
        'version':
            (remote['version'] as num?)?.toInt() ?? 1,
        'sync_state': 'synced',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _applyRemoteFolder(
    Database db,
    Map<String, dynamic> remote,
  ) async {
    final id = remote['id']?.toString();
    if (id == null || id.isEmpty) return;

    DateTime? parseDate(Object? value) =>
        value == null ? null : DateTime.tryParse(value.toString());

    final updatedDate = parseDate(remote['updated_at']);
    if (updatedDate == null) return;

    final updated = updatedDate.millisecondsSinceEpoch;

    final local = await db.query(
      'folders',
      where: 'id = ? AND owner_id = ?',
      whereArgs: [id, SnoteAccountScope.ownerId],
      limit: 1,
    );

    if (local.isNotEmpty &&
        (local.first['updated_at'] as num).toInt() >= updated) {
      return;
    }

    final created =
        parseDate(remote['created_at'])?.millisecondsSinceEpoch ?? updated;

    await db.insert(
      'folders',
      {
        'id': id,
        'owner_id': SnoteAccountScope.ownerId,
        'parent_id': remote['parent_id'],
        'name': remote['name']?.toString() ?? 'Folder',
        'created_at': local.isNotEmpty
            ? (local.first['created_at'] as num).toInt()
            : created,
        'updated_at': updated,
        'deleted_at': remote['deleted_at'] == null
            ? null
            : parseDate(remote['deleted_at'])?.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String> exportRemoteNotes() async {
    final user = client.auth.currentUser;

    if (user == null) {
      throw StateError('Authentication required');
    }

    final rows = await client
        .from('notes')
        .select()
        .eq('user_id', user.id)
        .order('updated_at', ascending: false);

    return const JsonEncoder.withIndent('  ').convert({
      'format': 'snote-json-v1',
      'exportedAt':
          DateTime.now().toUtc().toIso8601String(),
      'notes': rows,
    });
  }
}
