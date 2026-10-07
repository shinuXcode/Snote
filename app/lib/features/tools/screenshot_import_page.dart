import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/local/file_document_repository.dart';
import '../../data/local/note_repository.dart';

class ScreenshotImportPage extends StatefulWidget {
  final String? folderId;
  const ScreenshotImportPage({super.key, this.folderId});

  @override
  State<ScreenshotImportPage> createState() => _ScreenshotImportPageState();
}

class _ScreenshotImportPageState extends State<ScreenshotImportPage> {
  final _picker = ImagePicker();
  final _notes = NoteRepository();
  final _docs = FileDocumentRepository();
  Uint8List? _bytes;
  bool _busy = false;
  String _name = 'Screenshot note';

  Future<void> _pick() async {
    final image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 96);
    if (image == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await image.readAsBytes();
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _name = image.name.replaceFirst(RegExp(r'\.[^.]+$'), '');
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final bytes = _bytes;
    if (bytes == null) return;
    setState(() => _busy = true);
    try {
      final note = await _notes.create(title: _name, folderId: widget.folderId);
      await _docs.saveBytes(
        noteId: note.id,
        name: _name + '.png',
        type: 'image',
        bytes: bytes,
        metadata: {'source': 'screenshot-import'},
      );
      await _notes.saveContent(note.id, {
        'version': 5,
        'pages': <Map<String, Object?>>[],
        'mediaNote': true,
        'attachmentName': _name + '.png',
      });
      if (mounted) Navigator.pop(context, note);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save image: $error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Screenshot / image note')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Expanded(
                    child: _bytes == null
                        ? const Center(child: Text('Choose a screenshot or image to keep it inside the current folder.'))
                        : InteractiveViewer(child: Image.memory(_bytes!, fit: BoxFit.contain)),
                  ),
                  TextField(
                    controller: TextEditingController(text: _name),
                    onChanged: (v) => _name = v,
                    decoration: const InputDecoration(labelText: 'Note title'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: OutlinedButton.icon(onPressed: _busy ? null : _pick, icon: const Icon(Icons.photo_library_outlined), label: const Text('Choose image'))),
                      const SizedBox(width: 12),
                      Expanded(child: FilledButton.icon(onPressed: _busy || _bytes == null ? null : _save, icon: const Icon(Icons.save_rounded), label: Text(_busy ? 'Saving…' : 'Save here'))),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
