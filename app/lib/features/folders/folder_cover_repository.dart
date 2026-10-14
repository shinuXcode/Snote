import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../data/local/database.dart';

class LocalFolderCover {
  final String id;
  final String name;
  final int createdAt;

  const LocalFolderCover({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  String get key => 'cover:' + id;
}

class FolderCoverRepository {
  FolderCoverRepository._();
  static final FolderCoverRepository instance = FolderCoverRepository._();
  static const _uuid = Uuid();

  final Map<String, Uint8List> _memoryCache = <String, Uint8List>{};
  final Map<String, Future<Uint8List?>> _pending = <String, Future<Uint8List?>>{};

  Future<Database> get _db => SnoteDatabase.open();

  Future<List<LocalFolderCover>> list() async {
    final db = await _db;
    final rows = await db.query(
      'folder_covers',
      columns: ['id', 'name', 'created_at'],
      orderBy: 'created_at DESC',
    );
    return rows.map((row) => LocalFolderCover(
      id: row['id']! as String,
      name: row['name']! as String,
      createdAt: (row['created_at']! as num).toInt(),
    )).toList(growable: false);
  }

  Future<String> add({
    required String name,
    required Uint8List imageBytes,
  }) async {
    if (imageBytes.isEmpty) throw ArgumentError('The cover image is empty.');
    final db = await _db;
    final id = 'custom-' + _uuid.v4();
    await db.insert('folder_covers', {
      'id': id,
      'name': name.trim().isEmpty ? 'My cover' : name.trim(),
      'image_data': imageBytes,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    _memoryCache[id] = imageBytes;
    _pending.remove(id);
    return id;
  }

  Future<Uint8List?> imageForKey(String coverKey) {
    if (!coverKey.startsWith('cover:custom-')) return Future.value(null);
    final id = coverKey.substring('cover:'.length);
    final cached = _memoryCache[id];
    if (cached != null) return Future.value(cached);
    return _pending.putIfAbsent(id, () async {
      final db = await _db;
      final rows = await db.query(
        'folder_covers',
        columns: ['image_data'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final raw = rows.first['image_data'];
      if (raw is Uint8List) {
        _memoryCache[id] = raw;
        return raw;
      }
      if (raw is List<int>) {
        final bytes = Uint8List.fromList(raw);
        _memoryCache[id] = bytes;
        return bytes;
      }
      return null;
    });
  }

  Future<void> delete(String id) async {
    final db = await _db;
    await db.delete('folder_covers', where: 'id = ?', whereArgs: [id]);
    _memoryCache.remove(id);
    _pending.remove(id);
  }
}
