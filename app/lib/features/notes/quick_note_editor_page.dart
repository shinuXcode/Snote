import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../data/local/note_repository.dart';

/// Lightweight offline editor for Quick Notes and checklists. It uses the
/// shared notes table and JSON content, leaving the handwriting editor intact.
class QuickNoteEditorPage extends StatefulWidget {
  final LocalNote note;
  const QuickNoteEditorPage({super.key, required this.note});

  @override
  State<QuickNoteEditorPage> createState() => _QuickNoteEditorPageState();
}

class _QuickNoteEditorPageState extends State<QuickNoteEditorPage> {
  final _repository = NoteRepository();
  late final TextEditingController _title;
  late final TextEditingController _body;
  final List<_ChecklistItem> _items = [];
  Timer? _saveTimer;
  bool _saving = false;
  bool _checklist = false;

  @override
  void initState() {
    super.initState();
    Map<String, dynamic> content = {};
    try {
      final decoded = jsonDecode(widget.note.contentJson ?? '{}');
      if (decoded is Map) content = Map<String, dynamic>.from(decoded);
    } catch (_) {}
    _checklist = widget.note.noteType == 'checklist' || content['kind'] == 'checklist';
    _title = TextEditingController(text: widget.note.title);
    _body = TextEditingController(text: content['text']?.toString() ?? '');
    final rawItems = content['items'];
    if (rawItems is List) {
      for (final item in rawItems) {
        if (item is Map) {
          _items.add(_ChecklistItem(
            item['text']?.toString() ?? '',
            item['done'] == true,
          ));
        }
      }
    }
    _title.addListener(_scheduleSave);
    _body.addListener(_scheduleSave);
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 250), () => unawaited(_save()));
  }

  Future<void> _save() async {
    if (_saving) return;
    _saving = true;
    try {
      final title = _title.text.trim().isEmpty ? (_checklist ? 'Checklist' : 'Quick note') : _title.text.trim();
      await _repository.rename(widget.note.id, title);
      await _repository.saveContent(widget.note.id, {
        'noteType': _checklist ? 'checklist' : 'quick_note',
        'kind': _checklist ? 'checklist' : 'text',
        'text': _body.text,
        'items': _items.map((item) => {'text': item.text, 'done': item.done}).toList(),
      });
    } finally {
      _saving = false;
    }
  }

  void _addChecklistItem() {
    setState(() => _items.add(_ChecklistItem('', false)));
    _scheduleSave();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    unawaited(_save());
    _title.dispose();
    _body.dispose();
    for (final item in _items) {
      item.controller?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_checklist ? 'Quick checklist' : 'Quick note'),
        actions: [
          IconButton(
            tooltip: 'Save now',
            onPressed: () async {
              await _save();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Saved locally')),
                );
              }
            },
            icon: const Icon(Icons.check),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          children: [
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              style: theme.textTheme.headlineSmall,
              decoration: const InputDecoration(
                hintText: 'Title',
                border: InputBorder.none,
              ),
            ),
            const SizedBox(height: 12),
            if (_checklist) ...[
              for (var i = 0; i < _items.length; i++)
                Row(
                  children: [
                    Checkbox(
                      value: _items[i].done,
                      onChanged: (value) {
                        setState(() => _items[i].done = value ?? false);
                        _scheduleSave();
                      },
                    ),
                    Expanded(
                      child: TextFormField(
                        initialValue: _items[i].text,
                        decoration: const InputDecoration(
                          hintText: 'List item',
                          border: InputBorder.none,
                        ),
                        onChanged: (value) {
                          _items[i].text = value;
                          _scheduleSave();
                        },
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove item',
                      onPressed: () {
                        setState(() => _items.removeAt(i));
                        _scheduleSave();
                      },
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _addChecklistItem,
                  icon: const Icon(Icons.add),
                  label: const Text('Add item'),
                ),
              ),
            ] else
              TextField(
                controller: _body,
                minLines: 10,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Write something…',
                  border: InputBorder.none,
                ),
              ),
            const SizedBox(height: 24),
            Text('Stored on this device', style: theme.textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}

class _ChecklistItem {
  String text;
  bool done;
  TextEditingController? controller;
  _ChecklistItem(this.text, this.done);
}
