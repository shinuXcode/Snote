import 'dart:convert';

import 'package:file_picker/file_picker.dart';

import 'note_repository.dart';

class NotebookTransferService {
  final NoteRepository repository;

  const NotebookTransferService(this.repository);

  Future<String> exportAll() async {
    final notes = await repository.list();
    return const JsonEncoder.withIndent('  ').convert({
      'format': 'snote-json-v1',
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'notes': notes
          .map(
            (note) => {
              'id': note.id,
              'title': note.title,
              'folderId': note.folderId,
              'noteType': note.noteType,
              'contentJson': note.contentJson,
              'createdAt': note.createdAt,
              'updatedAt': note.updatedAt,
            },
          )
          .toList(),
    });
  }

  Future<int> importFromPickedFile() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json', 'snote'],
    );

    if (file == null) return 0;

    final raw = utf8.decode(await file.readAsBytes());
    final decoded = jsonDecode(raw);

    if (decoded is! Map || decoded['notes'] is! List) {
      throw const FormatException('Not a valid Snote notebook export.');
    }

    var imported = 0;
    for (final item in (decoded['notes'] as List).whereType<Map>()) {
      final title = item['title']?.toString().trim();
      if (title == null || title.isEmpty) continue;

      final created = await repository.create(title: title);
      final content = item['contentJson'];

      if (content is String && content.isNotEmpty) {
        try {
          final parsed = jsonDecode(content);
          if (parsed is Map) {
            await repository.saveContent(
              created.id,
              parsed.cast<String, Object?>(),
            );
          }
        } catch (_) {}
      }

      imported++;
    }

    return imported;
  }
}
