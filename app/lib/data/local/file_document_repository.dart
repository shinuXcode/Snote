import 'dart:convert';
import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'database.dart';
import '../../core/security/e2e_encryption_service.dart';
import 'local_file_store.dart';

class DocumentAsset {
  final String id;
  final String noteId;
  final String type;
  final String localPath;
  final String name;
  final int size;
  final bool isCover;
  final Map<String, dynamic> metadata;

  const DocumentAsset({
    required this.id,
    required this.noteId,
    required this.type,
    required this.localPath,
    required this.name,
    required this.size,
    required this.isCover,
    required this.metadata,
  });

  factory DocumentAsset.fromRow(Map<String, Object?> row) {
    final metadata = <String, dynamic>{};
    final raw = row['metadata_json']?.toString();
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) metadata.addAll(decoded.cast<String, dynamic>());
      } catch (_) {}
    }
    return DocumentAsset(
      id: row['id']! as String,
      noteId: row['note_id']! as String,
      type: row['type']! as String,
      localPath: row['local_path']! as String,
      name: metadata['name']?.toString() ?? 'Document',
      size: (row['size'] as num?)?.toInt() ?? 0,
      isCover: metadata['isCover'] == true,
      metadata: metadata,
    );
  }
}

class FileDocumentRepository {
  static const _uuid = Uuid();
  Future<Database> get _db => SnoteDatabase.open();

  Future<DocumentAsset> saveBytes({
    required String noteId,
    required String name,
    required String type,
    required List<int> bytes,
    Map<String, dynamic>? metadata,
  }) async {
    final id = _uuid.v4();
    final encryption = SnoteE2EEncryption.instance;
    final encrypted = await encryption.encryptBytes(bytes);
    final path = await writeLocalFile(id, name, encrypted);
    final data = <String, dynamic>{
      ...(metadata ?? <String, dynamic>{}),
      'name': name,
      'e2e': encrypted.length != bytes.length || await encryption.enabled,
    };
    final db = await _db;
    await db.insert('attachments', {
      'id': id,
      'note_id': noteId,
      'type': type,
      'local_path': path,
      'remote_path': null,
      'size': bytes.length,
      'metadata_json': jsonEncode(data),
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    return DocumentAsset(
      id: id,
      noteId: noteId,
      type: type,
      localPath: path,
      name: name,
      size: bytes.length,
      isCover: data['isCover'] == true,
      metadata: data,
    );
  }

  Future<List<DocumentAsset>> listForNote(String noteId) async {
    final db = await _db;
    final rows = await db.query(
      'attachments',
      where: 'note_id = ?',
      whereArgs: [noteId],
      orderBy: 'created_at ASC',
    );
    return rows.map(DocumentAsset.fromRow).toList();
  }

  Future<Uint8List> readBytes(DocumentAsset asset) async {
    final bytes = await readLocalFile(asset.localPath);
    return Uint8List.fromList(await SnoteE2EEncryption.instance.decryptBytes(bytes));
  }

  Future<void> setCover(String id, bool value) async {
    final db = await _db;
    final rows = await db.query('attachments', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return;
    final current = DocumentAsset.fromRow(rows.first);
    final metadata = <String, dynamic>{...current.metadata, 'isCover': value};
    await db.update(
      'attachments',
      {'metadata_json': jsonEncode(metadata)},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> delete(DocumentAsset asset) async {
    final db = await _db;
    await db.delete('attachments', where: 'id = ?', whereArgs: [asset.id]);
    await deleteLocalFile(asset.localPath);
  }

  Future<DocumentAsset?> duplicate(DocumentAsset asset, String newNoteId) async {
    final bytes = await readBytes(asset);
    return saveBytes(
      noteId: newNoteId,
      name: asset.name,
      type: asset.type,
      bytes: bytes,
      metadata: asset.metadata,
    );
  }

  Future<void> cutToNote(DocumentAsset asset, String newNoteId) async {
    final db = await _db;
    await db.update(
      'attachments',
      {'note_id': newNoteId},
      where: 'id = ?',
      whereArgs: [asset.id],
    );
  }
}
