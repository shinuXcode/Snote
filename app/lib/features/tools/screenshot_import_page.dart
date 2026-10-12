import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/local/file_document_repository.dart';
import '../../data/local/note_repository.dart';

class ScreenshotImportPage extends StatefulWidget {
  final String? folderId;
  final Uint8List? initialBytes;
  final String? initialName;

  const ScreenshotImportPage({
    super.key,
    this.folderId,
    this.initialBytes,
    this.initialName,
  });

  @override
  State<ScreenshotImportPage> createState() => _ScreenshotImportPageState();
}

class _ScreenshotImportPageState extends State<ScreenshotImportPage> {
  final _picker = ImagePicker();
  final _notes = NoteRepository();
  final _docs = FileDocumentRepository();
  final _nameController = TextEditingController(text: 'Screenshot note');

  Uint8List? _bytes;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _bytes = widget.initialBytes;
    final name = widget.initialName?.trim();
    if (name != null && name.isNotEmpty) _nameController.text = name;
  }

  Future<void> _pick(ImageSource source) async {
    if (_busy) return;
    try {
      final image = await _picker.pickImage(source: source, imageQuality: 96);
      if (image == null || !mounted) return;
      setState(() => _busy = true);
      final bytes = await image.readAsBytes();
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _nameController.text = image.name.replaceFirst(RegExp(r'\.[^.]+$'), '');
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open image source: ' + error.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final bytes = _bytes;
    if (bytes == null || _busy) return;
    final title = _nameController.text.trim().isEmpty
        ? 'Screenshot note'
        : _nameController.text.trim();
    setState(() => _busy = true);
    try {
      final note = await _notes.create(title: title, folderId: widget.folderId);
      await _docs.saveBytes(
        noteId: note.id,
        name: title + '.png',
        type: 'image',
        bytes: bytes,
        metadata: {'source': 'screenshot-import'},
      );
      await _notes.saveContent(note.id, {
        'version': 5,
        'pages': <Map<String, Object?>>[],
        'mediaNote': true,
        'attachmentName': title + '.png',
      });
      if (mounted) Navigator.pop(context, note);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save image: ' + error.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                      ? const Center(
                          child: Text(
                            'Capture with camera or choose a screenshot from Gallery.',
                            textAlign: TextAlign.center,
                          ),
                        )
                      : InteractiveViewer(
                          minScale: .5,
                          maxScale: 5,
                          child: Image.memory(
                            _bytes!,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                            errorBuilder: (_, __, ___) =>
                                const Center(child: Text('Could not preview this image.')),
                          ),
                        ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Note title',
                    prefixIcon: Icon(Icons.edit_note_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _pick(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Gallery'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _pick(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('Camera'),
                    ),
                    FilledButton.icon(
                      onPressed: _busy || _bytes == null ? null : _save,
                      icon: const Icon(Icons.save_rounded),
                      label: Text(_busy ? 'Saving…' : 'Save here'),
                    ),
                  ],
                ),
                if (_busy) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
