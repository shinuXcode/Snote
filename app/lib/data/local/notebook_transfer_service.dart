import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';

import 'notebook_transfer_crypto.dart';

import 'file_document_repository.dart';
import '../../features/folders/folder_cover_repository.dart';
import 'folder_repository.dart';
import 'note_repository.dart';

class NotebookTransferService {
  final NoteRepository repository;
  final FolderRepository folders = FolderRepository();

  NotebookTransferService(this.repository);

  Future<Uri?> exportEncryptedPicked({
    required String password,
    String? folderId,
    String? noteId,
  }) async {
    final bytes = await exportEncryptedArchiveBytes(
      password: password,
      folderId: folderId,
      noteId: noteId,
    );
    return FilePicker.saveFile(
      fileName: 'snotee-encrypted-notebook-${DateTime.now().millisecondsSinceEpoch}.snote',
      bytes: bytes,
      mimeType: 'application/octet-stream',
    );
  }

  Future<Uint8List> exportEncryptedArchiveBytes({
    required String password,
    String? folderId,
    String? noteId,
  }) async {
    final archiveBytes = await _buildEncryptedArchive(
      folderId: folderId,
      noteId: noteId,
    );
    final envelope = await NotebookTransferCrypto.encryptArchive(archiveBytes, password);
    return Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
  }

  Future<int> importEncryptedPicked({required String password}) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['snote', 'json'],
    );
    if (result.isEmpty) return 0;
    return importEncryptedArchiveBytes(
      Uint8List.fromList(await result.first.readAsBytes()),
      password: password,
    );
  }

  Future<int> importEncryptedArchiveBytes(
    List<int> encryptedBytes, {
    required String password,
  }) async {
    final raw = jsonDecode(utf8.decode(encryptedBytes));
    if (raw is! Map) throw const FormatException('Invalid encrypted Snote notebook.');
    final envelope = raw.cast<String, dynamic>();
    if (envelope['format'] == 'snote-encrypted-archive-v1') {
      final archiveBytes = await NotebookTransferCrypto.decryptArchive(envelope, password);
      return _importEncryptedArchive(archiveBytes);
    }
    // Backward compatibility for encrypted notebook backups created by older
    // beta versions. Those files contain notes/folders but no attachment bytes.
    final manifest = await NotebookTransferCrypto.decrypt(envelope, password);
    return _importJson(jsonEncode(manifest));
  }

  Future<List<int>> _buildEncryptedArchive({
    String? folderId,
    String? noteId,
  }) async {
    final allNotes = await repository.listAllVisible();
    final allFolders = await folders.listAllVisible();
    late final List<LocalNote> notes;
    late final List<LocalFolder> selectedFolders;
    if (folderId != null) {
      final folderIds = <String>{folderId};
      var changed = true;
      while (changed) {
        changed = false;
        for (final folder in allFolders) {
          if (folder.parentId != null &&
              folderIds.contains(folder.parentId) &&
              folderIds.add(folder.id)) {
            changed = true;
          }
        }
      }
      notes = allNotes.where((note) => note.folderId != null && folderIds.contains(note.folderId)).toList();
      selectedFolders = allFolders.where((folder) => folderIds.contains(folder.id)).toList();
      if (!selectedFolders.any((folder) => folder.id == folderId)) {
        throw StateError('The selected folder is no longer available.');
      }
    } else if (noteId != null) {
      final selected = allNotes.where((note) => note.id == noteId).toList();
      if (selected.isEmpty) throw StateError('The selected note is no longer available.');
      notes = selected;
      final folderIds = <String>{};
      final byId = {for (final folder in allFolders) folder.id: folder};
      var parentId = selected.first.folderId;
      while (parentId != null && folderIds.add(parentId)) {
        parentId = byId[parentId]?.parentId;
      }
      selectedFolders = allFolders.where((folder) => folderIds.contains(folder.id)).toList();
    } else {
      notes = allNotes;
      selectedFolders = allFolders;
    }

    final manifest = await _manifest(notes: notes, selectedFolders: selectedFolders);
    manifest['format'] = 'snote-notebook-v4';
    manifest['version'] = 4;
    final documents = FileDocumentRepository();
    final attachmentManifest = <Map<String, Object?>>[];
    final coverManifest = <Map<String, Object?>>[];
    final archive = Archive();

    for (final note in notes) {
      final assets = await documents.listForNote(note.id);
      for (final asset in assets) {
        final bytes = await documents.readBytes(asset);
        if (bytes.isEmpty) {
          throw StateError('Attachment "${asset.name}" is empty and cannot be backed up safely.');
        }
        if (asset.size > 0 && bytes.length != asset.size) {
          throw StateError('Attachment "${asset.name}" changed while the backup was being created.');
        }
        final archivePath = 'attachments/${asset.id}.bin';
        archive.addFile(ArchiveFile.bytes(archivePath, bytes));
        attachmentManifest.add(<String, Object?>{
          'id': asset.id,
          'noteId': note.id,
          'type': asset.type,
          'name': asset.name,
          'size': bytes.length,
          'metadata': asset.metadata,
          'archivePath': archivePath,
        });
      }
    }

    final coverRepository = FolderCoverRepository.instance;
    final covers = await coverRepository.list();
    final usedCoverKeys = <String>{
      for (final folder in selectedFolders)
        if (folder.iconKey.startsWith('cover:custom-')) folder.iconKey,
    };
    for (final note in notes) {
      try {
        final content = jsonDecode(note.contentJson ?? '{}');
        if (content is Map && content['coverKey'] is String) {
          final key = content['coverKey'] as String;
          if (key.startsWith('cover:custom-')) usedCoverKeys.add(key);
        }
      } catch (_) {
        // A malformed cover reference does not invalidate otherwise valid note content.
      }
    }
    final includeAllCovers = folderId == null && noteId == null;
    for (final cover in covers) {
      if (!includeAllCovers && !usedCoverKeys.contains(cover.key)) continue;
      final bytes = await coverRepository.imageForKey(cover.key);
      if (bytes == null || bytes.isEmpty) {
        throw StateError('Custom folder cover "${cover.name}" is missing and cannot be backed up safely.');
      }
      final archivePath = 'covers/${cover.id}.bin';
      archive.addFile(ArchiveFile.bytes(archivePath, bytes));
      coverManifest.add(<String, Object?>{
        'id': cover.id,
        'name': cover.name,
        'size': bytes.length,
        'archivePath': archivePath,
      });
    }

    manifest['attachments'] = attachmentManifest;
    manifest['folderCovers'] = coverManifest;
    archive.addFile(ArchiveFile.bytes(
      'manifest.json',
      utf8.encode(const JsonEncoder.withIndent('  ').convert(manifest)),
    ));
    return ZipEncoder().encodeBytes(archive);
  }

  Future<int> _importEncryptedArchive(List<int> bytes) async {
    if (bytes.isEmpty) throw const FormatException('The decrypted notebook archive is empty.');
    final archive = ZipDecoder().decodeBytes(bytes);
    if (archive.length > 20000) {
      throw const FormatException('The backup contains too many archive entries.');
    }
    final files = <String, List<int>>{};
    var totalBytes = 0;
    for (final entry in archive) {
      if (!entry.isFile) continue;
      final name = entry.name.replaceAll('\\\\', '/');
      if (name.startsWith('/') || name.split('/').contains('..')) {
        throw const FormatException('The backup contains an unsafe file path.');
      }
      final data = entry.readBytes();
      if (data == null) continue;
      totalBytes += data.length;
      if (totalBytes > 512 * 1024 * 1024) {
        throw const FormatException('The expanded backup exceeds the 512 MB safety limit.');
      }
      files[name] = data;
    }
    final manifestBytes = files.remove('manifest.json');
    if (manifestBytes == null || manifestBytes.isEmpty) {
      throw const FormatException('The backup does not contain a notebook manifest.');
    }
    return _importJson(
      utf8.decode(manifestBytes),
      archiveFiles: files,
    );
  }

  Future<Map<String, dynamic>> _manifest({
    List<LocalNote>? notes,
    List<LocalFolder>? selectedFolders,
  }) async {
    final selectedNotes = notes ?? await repository.listAllVisible();
    final allFolders = selectedFolders ?? await folders.listAllVisible();
    return {
      'format': 'snote-notebook-v3',
      'app': 'Snotee',
      'version': 3,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'folders': allFolders.map((f) => f.toExport()).toList(),
      'notes': selectedNotes.map((n) => {
        'id': n.id,
        'title': n.title,
        'folderId': n.folderId,
        'noteType': n.noteType,
        'isFavorite': n.isFavorite,
        'contentJson': n.contentJson,
        'createdAt': n.createdAt,
        'updatedAt': n.updatedAt,
      }).toList(),
    };
  }

  Future<Uri?> exportPicked() async {
    final manifest = await _manifest();
    final archive = Archive();
    archive.addFile(ArchiveFile.bytes(
      'manifest.json',
      utf8.encode(const JsonEncoder.withIndent('  ').convert(manifest)),
    ));
    final bytes = ZipEncoder().encodeBytes(archive);
    final name = 'snote-notebook-' + DateTime.now().millisecondsSinceEpoch.toString() + '.snote.zip';
    return FilePicker.saveFile(fileName: name, bytes: bytes, mimeType: 'application/zip');
  }

  Future<Uri?> exportJsonPicked() async {
    final manifest = await _manifest();
    return FilePicker.saveFile(
      fileName: 'snote-notebook.json',
      bytes: Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent('  ').convert(manifest))),
      mimeType: 'application/json',
    );
  }

  Future<Uri?> exportMarkdownPicked() async {
    final notes = await repository.listAllVisible();
    final buffer = StringBuffer('# Snote notebook\n\n');
    for (final note in notes) {
      buffer.writeln('## ' + note.title);
      buffer.writeln();
      if (note.contentJson != null && note.contentJson!.isNotEmpty) {
        buffer.writeln('~~~json');
        buffer.writeln(note.contentJson);
        buffer.writeln('~~~');
      }
      buffer.writeln();
    }
    return FilePicker.saveFile(
      fileName: 'snote-notebook.md',
      bytes: Uint8List.fromList(utf8.encode(buffer.toString())),
      mimeType: 'text/markdown',
    );
  }

  Future<Uri?> exportTextPicked() async {
    final notes = await repository.listAllVisible();
    final buffer = StringBuffer();
    for (final note in notes) {
      buffer.writeln(note.title);
      buffer.writeln(List.filled(note.title.length, '=').join());
      buffer.writeln(note.contentJson ?? '');
      buffer.writeln();
    }
    return FilePicker.saveFile(
      fileName: 'snote-notebook.txt',
      bytes: Uint8List.fromList(utf8.encode(buffer.toString())),
      mimeType: 'text/plain',
    );
  }

  Future<int> importPicked({String? targetFolderId}) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json', 'snote', 'zip', 'goodnotes', 'touchnotes', 'md', 'txt', 'csv', 'tsv'],
    );
    if (result.isEmpty) return 0;

    final file = result.first;
    final bytes = await file.readAsBytes();
    final name = file.name.toLowerCase();

    if (name.endsWith('.json') || (name.endsWith('.snote') && !name.endsWith('.snote.zip'))) {
      try {
        return await _importJson(utf8.decode(bytes), fallbackFolderId: targetFolderId);
      } catch (_) {}
    }

    if (name.endsWith('.md') || name.endsWith('.txt') || name.endsWith('.csv') || name.endsWith('.tsv')) {
      return _importText(file.name, utf8.decode(bytes), folderId: targetFolderId);
    }

    if (name.endsWith('.zip') || name.endsWith('.goodnotes') || name.endsWith('.touchnotes')) {
      return _importArchive(bytes, fallbackFolderId: targetFolderId);
    }

    throw const FormatException('Unsupported notebook package.');
  }

  Future<int> _importJson(
    String raw, {
    String? fallbackFolderId,
    Map<String, List<int>>? archiveFiles,
  }) async {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) throw const FormatException('Invalid notebook JSON.');

    final folderData = decoded['folders'];
    final folderItems = folderData is List
        ? folderData.whereType<Map>().toList(growable: false)
        : const <Map>[];
    final parentById = <String, String?>{
      for (final item in folderItems)
        if (item['id']?.toString().isNotEmpty == true)
          item['id'].toString(): item['parentId']?.toString(),
    };
    for (final id in parentById.keys) {
      final visited = <String>{};
      String? current = id;
      while (current != null && parentById.containsKey(current)) {
        if (!visited.add(current)) {
          throw const FormatException('The backup contains a cyclic folder hierarchy.');
        }
        current = parentById[current];
      }
    }

    final noteItems = decoded['notes'] is List
        ? (decoded['notes'] as List).whereType<Map>().toList(growable: false)
        : const <Map>[];
    final preparedNotes = <({Map item, Map<String, Object?>? content})>[];
    for (final item in noteItems) {
      final rawContent = item['contentJson'];
      Map<String, Object?>? content;
      if (rawContent is String && rawContent.isNotEmpty) {
        final parsed = jsonDecode(rawContent);
        if (parsed is! Map) {
          throw const FormatException('A backup note contains invalid content.');
        }
        content = parsed.cast<String, Object?>();
      } else if (rawContent is Map) {
        content = rawContent.cast<String, Object?>();
      }
      preparedNotes.add((item: item, content: content));
    }

    final attachmentItems = decoded['attachments'] is List
        ? (decoded['attachments'] as List).whereType<Map>().toList(growable: false)
        : const <Map>[];
    if (attachmentItems.isNotEmpty) {
      if (archiveFiles == null) {
        throw const FormatException('This backup references attachments but has no attachment archive.');
      }
      final noteIds = noteItems
          .map((item) => item['id']?.toString())
          .whereType<String>()
          .toSet();
      for (final item in attachmentItems) {
        final noteId = item['noteId']?.toString();
        final path = item['archivePath']?.toString();
        final data = path == null ? null : archiveFiles[path];
        final size = (item['size'] as num?)?.toInt();
        if (noteId == null || !noteIds.contains(noteId) ||
            path == null || data == null || data.isEmpty ||
            (size != null && size != data.length)) {
          throw const FormatException('The backup contains a missing or invalid attachment.');
        }
      }
    }

    final coverItems = decoded['folderCovers'] is List
        ? (decoded['folderCovers'] as List).whereType<Map>().toList(growable: false)
        : const <Map>[];
    if (coverItems.isNotEmpty) {
      if (archiveFiles == null) {
        throw const FormatException('This backup references custom covers but has no cover archive.');
      }
      for (final item in coverItems) {
        final path = item['archivePath']?.toString();
        final data = path == null ? null : archiveFiles[path];
        final size = (item['size'] as num?)?.toInt();
        if (item['id'] == null || path == null || data == null || data.isEmpty ||
            (size != null && size != data.length)) {
          throw const FormatException('The backup contains a missing or invalid custom cover.');
        }
      }
    }

    final folderMap = <String, String>{};
    final pendingFolders = folderItems.toList(growable: true);
    final oldFolderIds = folderItems
        .map((item) => item['id']?.toString())
        .whereType<String>()
        .toSet();

    final coverIdMap = <String, String>{};
    if (coverItems.isNotEmpty) {
      final coverRepository = FolderCoverRepository.instance;
      for (final item in coverItems) {
        final oldKey = 'cover:${item['id']}';
        final imageBytes = archiveFiles![item['archivePath']?.toString()]!;
        final newId = await coverRepository.add(
          name: item['name']?.toString() ?? 'Imported cover',
          imageBytes: Uint8List.fromList(imageBytes),
        );
        coverIdMap[oldKey] = 'cover:$newId';
      }
    }

    // Create parents before children. A malformed cyclic hierarchy is rejected
    // rather than creating a partial, incorrectly nested tree.
    while (pendingFolders.isNotEmpty) {
      var progressed = false;
      for (final item in List<Map>.from(pendingFolders)) {
        final oldId = item['id']?.toString();
        final folderName = item['name']?.toString().trim();
        if (oldId == null || oldId.isEmpty || folderName == null || folderName.isEmpty) {
          pendingFolders.remove(item);
          progressed = true;
          continue;
        }
        final oldParentId = item['parentId']?.toString();
        if (oldParentId != null &&
            oldFolderIds.contains(oldParentId) &&
            !folderMap.containsKey(oldParentId)) {
          continue;
        }
        final mappedParentId = oldParentId == null
            ? fallbackFolderId
            : folderMap[oldParentId] ?? fallbackFolderId;
        final oldIconKey = item['iconKey']?.toString() ?? 'folder';
        final newFolder = await folders.create(
          name: folderName,
          parentId: mappedParentId,
          colorValue: (item['colorValue'] as num?)?.toInt() ?? defaultFolderColor,
          iconKey: coverIdMap[oldIconKey] ?? oldIconKey,
        );
        if (item['isFavorite'] == true) {
          await folders.setFavorite(newFolder.id, true);
        }
        folderMap[oldId] = newFolder.id;
        pendingFolders.remove(item);
        progressed = true;
      }
      if (!progressed) {
        throw const FormatException('The backup contains a cyclic or invalid folder hierarchy.');
      }
    }

    final noteIdMap = <String, String>{};
    final pendingContent = <({LocalNote note, Object? content})>[];
    var imported = 0;
    for (final prepared in preparedNotes) {
      final item = prepared.item;
      final title = item['title']?.toString().trim();
      if (title == null || title.isEmpty) continue;
      final oldNoteId = item['id']?.toString();
      final oldFolderId = item['folderId']?.toString();
      final note = await repository.create(
        title: title,
        folderId: folderMap[oldFolderId] ?? fallbackFolderId,
      );
      if (oldNoteId != null && oldNoteId.isNotEmpty) {
        noteIdMap[oldNoteId] = note.id;
      }
      if (item['isFavorite'] == true) {
        await repository.setFavorite(note.id, true);
      }
      pendingContent.add((note: note, content: prepared.content));
      imported++;
    }

    final assetIdMap = <String, String>{...coverIdMap};
    final attachmentData = attachmentItems;
    if (attachmentData.isNotEmpty) {
      if (archiveFiles == null) {
        throw const FormatException('This backup references attachments but has no attachment archive.');
      }
      final documents = FileDocumentRepository();
      for (final item in attachmentData) {
        final oldNoteId = item['noteId']?.toString();
        final newNoteId = oldNoteId == null ? null : noteIdMap[oldNoteId];
        final oldAssetId = item['id']?.toString();
        final archivePath = item['archivePath']?.toString();
        if (newNoteId == null || oldAssetId == null || archivePath == null) {
          throw const FormatException('The backup contains invalid attachment metadata.');
        }
        final attachmentBytes = archiveFiles[archivePath];
        if (attachmentBytes == null || attachmentBytes.isEmpty) {
          throw const FormatException('A backup attachment is missing or empty.');
        }
        final expectedSize = (item['size'] as num?)?.toInt();
        if (expectedSize != null && expectedSize != attachmentBytes.length) {
          throw const FormatException('A backup attachment failed its size check.');
        }
        final metadata = item['metadata'] is Map
            ? (item['metadata'] as Map).map<String, dynamic>(
                (key, value) => MapEntry(key.toString(), value),
              )
            : <String, dynamic>{};
        final savedAsset = await documents.saveBytes(
          noteId: newNoteId,
          name: item['name']?.toString() ?? 'Attachment',
          type: item['type']?.toString() ?? 'file',
          bytes: attachmentBytes,
          metadata: metadata,
        );
        assetIdMap[oldAssetId] = savedAsset.id;
      }
    }

    for (final pending in pendingContent) {
      final content = pending.content;
      if (content != null) {
        await repository.saveContent(
          pending.note.id,
          _remapAssetReferences(content, assetIdMap),
        );
      }
    }
    return imported;
  }

  Map<String, Object?> _remapAssetReferences(
    Map<String, Object?> content,
    Map<String, String> ids,
  ) =>
      content.map(
        (key, value) => MapEntry(key, _remapAssetReferenceValue(value, ids)),
      );

  Object? _remapAssetReferenceValue(Object? value, Map<String, String> ids) {
    if (value is String) return ids[value] ?? value;
    if (value is List) {
      return value.map((item) => _remapAssetReferenceValue(item, ids)).toList();
    }
    if (value is Map) {
      return value.map<Object?, Object?>(
        (key, item) => MapEntry(key, _remapAssetReferenceValue(item, ids)),
      );
    }
    return value;
  }

  Future<int> _importText(String filename, String raw, {String? folderId}) async {
    final title = filename.replaceFirst(RegExp(r'\.[^.]+$'), '').trim();
    if (title.isEmpty || raw.trim().isEmpty) return 0;
    final note = await repository.create(title: title, folderId: folderId);
    await repository.saveContent(note.id, {
      'version': 5,
      'pages': <Map<String, Object?>>[],
      'text_delta': <Map<String, Object?>>[<String, Object?>{'insert': raw + '\n'}],
      'importedText': true,
    });
    return 1;
  }

  Future<int> _importArchive(List<int> bytes, {String? fallbackFolderId}) async {
    final archive = ZipDecoder().decodeBytes(bytes);
    var imported = 0;
    for (final file in archive) {
      if (!file.isFile) continue;
      final lower = file.name.toLowerCase();
      final data = file.readBytes();
      if (data == null) continue;
      if (lower.endsWith('.json')) {
        try { imported += await _importJson(utf8.decode(data), fallbackFolderId: fallbackFolderId); } catch (_) {}
      } else if (lower.endsWith('.md') || lower.endsWith('.txt') || lower.endsWith('.csv') || lower.endsWith('.tsv')) {
        try { imported += await _importText(file.name.split('/').last, utf8.decode(data), folderId: fallbackFolderId); } catch (_) {}
      }
    }
    return imported;
  }
}
