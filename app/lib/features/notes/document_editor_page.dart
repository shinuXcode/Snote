import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../data/local/note_repository.dart';

/// Offline-first structured text page using the shared note library.
class DocumentEditorPage extends StatefulWidget {
  final LocalNote note;
  const DocumentEditorPage({super.key, required this.note});
  @override
  State<DocumentEditorPage> createState() => _DocumentEditorPageState();
}
class _DocumentEditorPageState extends State<DocumentEditorPage> {
  final _repository = NoteRepository();
  late final TextEditingController _title;
  late final TextEditingController _body;
  Timer? _timer;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    Map<String, dynamic> content = {};
    try {
      final decoded = jsonDecode(widget.note.contentJson ?? '{}');
      if (decoded is Map) content = Map<String, dynamic>.from(decoded);
    } catch (_) {}
    _title = TextEditingController(text: widget.note.title)..addListener(_scheduleSave);
    _body = TextEditingController(text: content['text']?.toString() ?? '')..addListener(_scheduleSave);
  }

  void _insert(String text) {
    final selection = _body.selection;
    final start = selection.isValid ? selection.start : _body.text.length;
    final end = selection.isValid ? selection.end : start;
    _body.value = TextEditingValue(
      text: _body.text.replaceRange(start, end, text),
      selection: TextSelection.collapsed(offset: start + text.length),
    );
    _scheduleSave();
  }

  void _scheduleSave() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 300), () => unawaited(_save()));
  }

  Future<void> _save() async {
    if (_saving) return;
    _saving = true;
    try {
      await _repository.rename(widget.note.id, _title.text.trim().isEmpty ? 'Untitled document' : _title.text.trim());
      await _repository.saveContent(widget.note.id, {
        'noteType': 'document',
        'kind': 'document',
        'text': _body.text,
        'blocks': _body.text.split('\n').map((line) => {
          'type': line.startsWith('# ') ? 'heading1' : line.startsWith('## ') ? 'heading2' : line.startsWith('- ') ? 'bullet' : 'paragraph',
          'text': line,
        }).toList(),
      });
    } finally {
      _saving = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_save());
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Document'),
      actions: [
        PopupMenuButton<String>(
          tooltip: 'Insert block',
          onSelected: _insert,
          itemBuilder: (_) => const [
            PopupMenuItem(value: '# Heading\n', child: Text('Heading')),
            PopupMenuItem(value: '## Subheading\n', child: Text('Subheading')),
            PopupMenuItem(value: '- List item\n', child: Text('Bullet list item')),
            PopupMenuItem(value: '> Callout: \n', child: Text('Callout')),
            PopupMenuItem(value: '\n| Column 1 | Column 2 |\n| --- | --- |\n| Value | Value |\n', child: Text('Table template')),
          ],
          icon: const Icon(Icons.add_box_outlined),
        ),
        IconButton(
          tooltip: 'Save now',
          onPressed: () async {
            await _save();
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved locally')));
          },
          icon: const Icon(Icons.check),
        ),
      ],
    ),
    body: SafeArea(child: ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 48),
      children: [
        TextField(controller: _title, style: Theme.of(context).textTheme.headlineMedium, decoration: const InputDecoration(hintText: 'Document title', border: InputBorder.none)),
        const SizedBox(height: 16),
        TextField(
          controller: _body, minLines: 18, maxLines: null,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Start writing… Use the insert menu for headings, lists, callouts and table templates.',
            border: InputBorder.none, alignLabelWithHint: true,
          ),
        ),
      ],
    )),
  );
}
