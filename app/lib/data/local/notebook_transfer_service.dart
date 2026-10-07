import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'folder_repository.dart';
import 'note_repository.dart';

class NotebookTransferService {
  final NoteRepository repository;
  final FolderRepository folders = FolderRepository();
  NotebookTransferService(this.repository);

  Future<Map<String, dynamic>> _manifest() async {
    final notes = await repository.listAllVisible();
    final allFolders = await folders.listAllVisible();
    return {
      'format': 'snote-notebook-v2',
      'app': 'Snote',
      'version': 2,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'folders': allFolders.map((f) => f.toExport()).toList(),
      'notes': notes.map((n) => {
        'id': n.id,
        'title': n.title,
        'folderId': n.folderId,
        'noteType': n.noteType,
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
    return FilePicker.saveFile(fileName: name, bytes: bytes);
  }

  Future<Uri?> exportJsonPicked() async {
    final manifest = await _manifest();
    return FilePicker.saveFile(
      fileName: 'snote-notebook.json',
      bytes: utf8.encode(const JsonEncoder.withIndent('  ').convert(manifest)),
    );
  }

  Future<Uri?> exportMarkdownPicked() async {
    final notes = await repository.listAllVisible();
    final buffer = StringBuffer('# Snote notebook\n\n');
    for (final note in notes) {
      buffer.writeln('## ' + note.title);
      buffer.writeln();
      if (note.contentJson != null && note.contentJson!.isNotEmpty) {
        buffer.writeln('```json');
        buffer.writeln(note.contentJson);
        buffer.writeln('```');
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
      buffer.writeln('=' * note.title.length);
      buffer.writeln(note.contentJson ?? '');
      buffer.writeln();
    }
    return FilePicker.saveFile(
      fileName: 'snote-notebook.txt',
      bytes: Uint8List.fromList(utf8.encode(buffer.toString())),
      mimeType: 'text/plain',
    );
  }

  Future<int> importPicked() async {
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
        return await _importJson(utf8.decode(bytes));
      } catch (_) {}
    }

    if (name.endsWith('.md') || name.endsWith('.txt') || name.endsWith('.csv') || name.endsWith('.tsv')) {
      return _importText(file.name, utf8.decode(bytes));
    }
    if (name.endsWith('.zip') || name.endsWith('.goodnotes') || name.endsWith('.touchnotes')) {
      return _importArchive(bytes);
    }

    throw const FormatException('Unsupported notebook package.');
  }

  Future<int> _importJson(String raw) async {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) throw const FormatException('Invalid notebook JSON.');

    final folderMap = <String, String>{};
    final folderData = decoded['folders'];
    if (folderData is List) {
      for (final item in folderData.whereType<Map>()) {
        final oldId = item['id']?.toString();
        final folderName = item['name']?.toString().trim();
        if (oldId == null || folderName == null || folderName.isEmpty) continue;
        final newFolder = await folders.create(name: folderName);
        folderMap[oldId] = newFolder.id;
      }
    }

    var imported = 0;
    final notes = decoded['notes'];
    if (notes is! List) return imported;

    for (final item in notes.whereType<Map>()) {
      final title = item['title']?.toString().trim();
      if (title == null || title.isEmpty) continue;
      final note = await repository.create(
        title: title,
        folderId: folderMap[item['folderId']?.toString()],
      );

      final content = item['contentJson'];
      if (content is String && content.isNotEmpty) {
        try {
          final parsed = jsonDecode(content);
          if (parsed is Map) {
            await repository.saveContent(note.id, parsed.cast<String, Object?>());
          }
        } catch (_) {}
      } else if (content is Map) {
        await repository.saveContent(note.id, content.cast<String, Object?>());
      }
      imported++;
    }
    return imported;
  }

  Future<int> _importText(String filename, String raw) async {
    final title = filename.replaceFirst(RegExp(r'\.[^.]+
    final archive = ZipDecoder().decodeBytes(bytes);
    var imported = 0;

    for (final file in archive) {
      if (!file.isFile || !file.name.toLowerCase().endsWith('.json')) continue;
      final data = file.readBytes();
      if (data == null) continue;
      try {
        imported += await _importJson(utf8.decode(data));
      } catch (_) {}
    }

    return imported;
  }
}
), '').trim();
    if (title.isEmpty || raw.trim().isEmpty) return 0;
    final note = await repository.create(title: title);
    await repository.saveContent(note.id, {
      'version': 5,
      'pages': <Map<String, Object?>>[],
      'text_delta': <Map<String, Object?>>[
        <String, Object?>{'insert': raw + '\n'},
      ],
      'importedText': true,
    });
    return 1;
  }
  Future<int> _importArchive(List<int> bytes) async {
    final archive = ZipDecoder().decodeBytes(bytes);
    var imported = 0;

    for (final file in archive) {
      if (!file.isFile || !file.name.toLowerCase().endsWith('.json')) continue;
      final data = file.readBytes();
      if (data == null) continue;
      try {
        imported += await _importJson(utf8.decode(data));
      } catch (_) {}
    }

    return imported;
  }
}
