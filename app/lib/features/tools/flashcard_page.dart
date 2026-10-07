import 'package:flutter/material.dart';

import '../../data/local/note_repository.dart';

class FlashcardPage extends StatefulWidget {
  final String? folderId;
  const FlashcardPage({super.key, this.folderId});

  @override
  State<FlashcardPage> createState() => _FlashcardPageState();
}

class _FlashcardPageState extends State<FlashcardPage> {
  final _notes = NoteRepository();
  final _front = TextEditingController();
  final _back = TextEditingController();
  bool _showBack = false;

  Future<void> _save() async {
    if (_front.text.trim().isEmpty && _back.text.trim().isEmpty) return;
    final note = await _notes.create(title: _front.text.trim().isEmpty ? 'Flashcard' : _front.text.trim(), folderId: widget.folderId);
    await _notes.saveContent(note.id, {
      'version': 5,
      'noteType': 'flashcard',
      'flashcard': {'front': _front.text, 'back': _back.text},
      'pages': <Map<String, Object?>>[],
      'text_delta': const <Map<String, Object?>>[],
    });
    if (mounted) Navigator.pop(context, note);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Flashcard'),
          actions: [IconButton(onPressed: _save, tooltip: 'Save', icon: const Icon(Icons.save_outlined))],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(28),
                      onTap: () => setState(() => _showBack = !_showBack),
                      child: Ink(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                        ),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              _showBack ? (_back.text.isEmpty ? 'Back side' : _back.text) : (_front.text.isEmpty ? 'Front side' : _front.text),
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(controller: _front, decoration: const InputDecoration(labelText: 'Front')),
                  const SizedBox(height: 10),
                  TextField(controller: _back, decoration: const InputDecoration(labelText: 'Back')),
                ],
              ),
            ),
          ),
        ),
      );

  @override
  void dispose() {
    _front.dispose();
    _back.dispose();
    super.dispose();
  }
}
