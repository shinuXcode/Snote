import 'dart:convert';
import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'database.dart';
import '../../core/config/account_scope.dart';
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
      'e2e': encryption.isEncryptedBytes(encrypted),
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

  Future<DocumentAsset?> replaceBytes(DocumentAsset asset, List<int> bytes) async {
    final encryption = SnoteE2EEncryption.instance;
    final storedBytes = await encryption.encryptBytes(bytes);
    final path = await writeLocalFile(asset.id, asset.name, storedBytes);
    final updatedAt = DateTime.now().millisecondsSinceEpoch;
    final metadata = <String, dynamic>{
      ...asset.metadata,
      'name': asset.name,
      'updatedAt': updatedAt,
      'e2e': encryption.isEncryptedBytes(storedBytes),
    };
    final db = await _db;
    await db.update(
      'attachments',
      {
        'local_path': path,
        'size': bytes.length,
        'metadata_json': jsonEncode(metadata),
      },
      where: 'id = ?',
      whereArgs: [asset.id],
    );
    if (asset.localPath != path) {
      await deleteLocalFile(asset.localPath);
    }
    return DocumentAsset(
      id: asset.id,
      noteId: asset.noteId,
      type: asset.type,
      localPath: path,
      name: asset.name,
      size: bytes.length,
      isCover: asset.isCover,
      metadata: metadata,
    );
  }

  /// Encrypts existing attachment files without touching already-encrypted
  /// envelopes. The replacement is written before its database path is saved,
  /// so a failed write leaves the previous attachment intact.
  Future<int> encryptExistingAttachments() async {
    final encryption = SnoteE2EEncryption.instance;
    if (!await encryption.enabled) return 0;

    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT attachments.* FROM attachments '
      'INNER JOIN notes ON notes.id = attachments.note_id '
      'WHERE notes.owner_id = ?',
      <Object?>[SnoteAccountScope.ownerId],
    );
    var migrated = 0;

    for (final row in rows) {
      final asset = DocumentAsset.fromRow(row);
      final current = await readLocalFile(asset.localPath);
      if (encryption.isEncryptedBytes(current)) continue;

      final protected = await encryption.encryptBytes(current);
      final path = await writeLocalFile(asset.id, asset.name, protected);
      final metadata = <String, dynamic>{
        ...asset.metadata,
        'name': asset.name,
        'e2e': encryption.isEncryptedBytes(protected),
      };
      await db.update(
        'attachments',
        {
          'local_path': path,
          'size': current.length,
          'metadata_json': jsonEncode(metadata),
        },
        where: 'id = ?',
        whereArgs: <Object?>[asset.id],
      );
      if (asset.localPath != path) {
        await deleteLocalFile(asset.localPath);
      }
      migrated++;
    }
    return migrated;
  }

  /// Restores previously encrypted files before the vault key is removed.
  /// If any file fails authentication, this throws and the caller must retain
  /// the passphrase so no remaining encrypted attachment becomes inaccessible.
  Future<int> decryptExistingAttachments() async {
    final encryption = SnoteE2EEncryption.instance;
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT attachments.* FROM attachments '
      'INNER JOIN notes ON notes.id = attachments.note_id '
      'WHERE notes.owner_id = ?',
      <Object?>[SnoteAccountScope.ownerId],
    );
    var migrated = 0;

    for (final row in rows) {
      final asset = DocumentAsset.fromRow(row);
      final current = await readLocalFile(asset.localPath);
      if (!encryption.isEncryptedBytes(current)) continue;

      final clear = await encryption.decryptBytes(current);
      final path = await writeLocalFile(asset.id, asset.name, clear);
      final metadata = <String, dynamic>{
        ...asset.metadata,
        'name': asset.name,
        'e2e': false,
      };
      await db.update(
        'attachments',
        {
          'local_path': path,
          'size': clear.length,
          'metadata_json': jsonEncode(metadata),
        },
        where: 'id = ?',
        whereArgs: <Object?>[asset.id],
      );
      if (asset.localPath != path) {
        await deleteLocalFile(asset.localPath);
      }
      migrated++;
    }
    return migrated;
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
