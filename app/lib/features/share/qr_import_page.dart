import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../data/local/note_repository.dart';

class QrImportPage extends StatelessWidget {
  const QrImportPage({super.key});

  Future<void> _showPayload(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json', 'snote'],
      withData: true,
    );

    if (result == null || result.files.single.bytes == null) return;

    try {
      final raw = utf8.decode(result.files.single.bytes!);
      final decoded = jsonDecode(raw);

      if (decoded is! Map || decoded['format'] != 'snote-note-v1') {
        throw const FormatException('Invalid Snote transfer payload.');
      }

      final content = decoded['content'];
      final title = decoded['title']?.toString() ?? 'Imported note';
      final repo = NoteRepository();
      final note = await repo.create(title: title);

      if (content is Map) {
        await repo.saveContent(note.id, content.cast<String, Object?>());
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Note imported.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import transfer')),
      body: Center(
        child: FilledButton.icon(
          onPressed: () => _showPayload(context),
          icon: const Icon(Icons.qr_code_scanner_rounded),
          label: const Text('Import a Snote transfer file'),
        ),
      ),
    );
  }
}
