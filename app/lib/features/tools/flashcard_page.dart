import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../data/local/note_repository.dart';

class FlashcardPage extends StatefulWidget {
  final String? folderId;
  final LocalNote? note;
  const FlashcardPage({super.key, this.folderId, this.note});
  @override
  State<FlashcardPage> createState() => _FlashcardPageState();
}

class _FlashcardPageState extends State<FlashcardPage> {
  final _notes = NoteRepository();
  final _front = TextEditingController();
  final _back = TextEditingController();
  final List<Map<String, String>> _cards = [];
  int _index = 0;
  bool _showBack = false;
  bool _showEditor = true;
  int _editingIndex = -1;

  int get _knownCount => _cards.where((card) => card['known'] == 'true').length;

  String _newCardId() => DateTime.now().microsecondsSinceEpoch.toString();

  @override
  void initState() {
    super.initState();
    try {
      final decoded = jsonDecode(widget.note?.contentJson ?? '{}');
      if (decoded is Map && decoded['flashcards'] is List) {
        var index = 0;
        final stamp = DateTime.now().microsecondsSinceEpoch.toString();
        for (final item in decoded['flashcards'] as List) {
          if (item is Map) {
            _cards.add({
              'id': item['id']?.toString() ?? 'legacy-' + stamp + '-' + index.toString(),
              'front': item['front']?.toString() ?? '',
              'back': item['back']?.toString() ?? '',
              'known': item['known']?.toString() ?? 'false',
            });
            index++;
          }
        }
      }
    } catch (_) {}
    if (widget.note != null && _cards.isNotEmpty) _showEditor = false;
  }

  void _editCurrentCard() {
    if (_cards.isEmpty) return;
    setState(() {
      _editingIndex = _index;
      _front.text = _cards[_index]['front'] ?? '';
      _back.text = _cards[_index]['back'] ?? '';
      _showBack = false;
      _showEditor = true;
    });
  }

  void _shuffleCards() {
    if (_cards.length < 2) return;
    final currentId = _cards[_index]['id'];
    setState(() {
      _cards.shuffle(math.Random());
      final nextIndex = _cards.indexWhere((card) => card['id'] == currentId);
      _index = nextIndex < 0 ? 0 : nextIndex;
      _showBack = false;
    });
  }

  void _markCurrentKnown(bool value) {
    if (_cards.isEmpty) return;
    setState(() {
      _cards[_index] = <String, String>{
        ..._cards[_index],
        'known': value ? 'true' : 'false',
      };
    });
  }

  Future<void> _deleteCurrentCard() async {
    if (_cards.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Delete flashcard?'),
        content: const Text('This card will be removed from the deck when you save it.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Delete card')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _cards.removeAt(_index);
      if (_cards.isEmpty) {
        _index = 0;
      } else if (_index >= _cards.length) {
        _index = _cards.length - 1;
      }
      _editingIndex = -1;
      _showBack = false;
      _front.clear();
      _back.clear();
      _showEditor = _cards.isEmpty;
    });
  }

  void _addCard() {
    if (_front.text.trim().isEmpty || _back.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter both the front and back.')));
      return;
    }
    setState(() {
      if (_editingIndex >= 0 && _editingIndex < _cards.length) {
        final existing = _cards[_editingIndex];
        _cards[_editingIndex] = <String, String>{
          ...existing,
          'front': _front.text.trim(),
          'back': _back.text.trim(),
          'known': existing['known'] ?? 'false',
        };
        _index = _editingIndex;
      } else {
        _cards.add(<String, String>{
          'id': _newCardId(),
          'front': _front.text.trim(),
          'back': _back.text.trim(),
          'known': 'false',
        });
        _index = _cards.length - 1;
      }
      _editingIndex = -1;
      _showBack = false;
      _front.clear();
      _back.clear();
    });
  }

  Future<void> _save() async {
    if (_front.text.trim().isNotEmpty && _back.text.trim().isNotEmpty) {
      if (_editingIndex >= 0 && _editingIndex < _cards.length) {
        final existing = _cards[_editingIndex];
        _cards[_editingIndex] = <String, String>{
          ...existing,
          'front': _front.text.trim(),
          'back': _back.text.trim(),
          'known': existing['known'] ?? 'false',
        };
      } else {
        _cards.add(<String, String>{
          'id': _newCardId(),
          'front': _front.text.trim(),
          'back': _back.text.trim(),
          'known': 'false',
        });
      }
      _editingIndex = -1;
    }
    if (_cards.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add at least one complete card first.')));
      return;
    }
    final first = _cards.first['front']!;
    final title = first.length > 36 ? first.substring(0, 33) + '...' : first;
    final target = widget.note ?? await _notes.create(
      title: 'Flashcards - ' + title,
      folderId: widget.folderId,
    );
    if (widget.note != null) await _notes.rename(target.id, 'Flashcards - ' + title);
    final content = <String, Object?>{};
    try {
      final decoded = jsonDecode(target.contentJson ?? '{}');
      if (decoded is Map) content.addAll(decoded.cast<String, Object?>());
    } catch (_) {}
    content.addAll({
      'version': 5,
      'noteType': 'flashcard',
      'flashcards': _cards,
      'flashcard': _cards.first,
      'pages': <Map<String, Object?>>[],
      'text_delta': const <Map<String, Object?>>[],
    });
    await _notes.saveContent(target.id, content);
    if (mounted) Navigator.pop(context, target);
  }


  @override
  Widget build(BuildContext context) {
    final active = _cards.isEmpty ? null : _cards[_index];
    final front = active?['front'] ?? _front.text;
    final back = active?['back'] ?? _back.text;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.note == null ? 'Flashcard deck' : 'Edit flashcards'),
        actions: [
          if (_cards.length > 1)
            IconButton(onPressed: _shuffleCards, tooltip: 'Shuffle deck', icon: const Icon(Icons.shuffle_rounded)),
          if (_cards.isNotEmpty)
            IconButton(onPressed: _deleteCurrentCard, tooltip: 'Delete current card', icon: const Icon(Icons.delete_outline_rounded)),
          if (_cards.isNotEmpty)
            IconButton(
              onPressed: () => setState(() => _showEditor = !_showEditor),
              tooltip: _showEditor ? 'Hide card editor' : 'Edit cards',
              icon: Icon(_showEditor ? Icons.visibility_off_outlined : Icons.edit_note_rounded),
            ),
          if (_showEditor)
            IconButton(onPressed: _addCard, tooltip: 'Add card to deck', icon: const Icon(Icons.add_card_rounded)),
          IconButton(onPressed: _save, tooltip: 'Save deck', icon: const Icon(Icons.save_outlined)),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                if (_cards.isNotEmpty) ...[
                  Row(
                    children: [
                      Text('Card ' + (_index + 1).toString() + ' of ' + _cards.length.toString()),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            value: _knownCount / _cards.length,
                            minHeight: 7,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('$_knownCount known'),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(28),
                    onTap: () => setState(() => _showBack = !_showBack),
                    child: Ink(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft, end: Alignment.bottomRight,
                          colors: _showBack ? [colors.tertiaryContainer, colors.surfaceContainerHighest] : [colors.primaryContainer, colors.surfaceContainerHighest],
                        ),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: colors.outlineVariant),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .12), blurRadius: 18, offset: const Offset(0, 8))],
                      ),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(_showBack ? 'ANSWER' : 'QUESTION', style: Theme.of(context).textTheme.labelLarge),
                              const SizedBox(height: 14),
                              Text(_showBack ? (back.isEmpty ? 'Back side' : back) : (front.isEmpty ? 'Front side' : front), textAlign: TextAlign.center, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                              const SizedBox(height: 14),
                              const Text('Tap card to flip', style: TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_cards.isNotEmpty) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _index == 0 ? null : () => setState(() { _index--; _showBack = false; }),
                        icon: const Icon(Icons.chevron_left),
                        label: const Text('Previous'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _index >= _cards.length - 1 ? null : () => setState(() { _index++; _showBack = false; }),
                        icon: const Icon(Icons.chevron_right),
                        label: const Text('Next'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _markCurrentKnown(false),
                        icon: Icon(active?['known'] == 'true' ? Icons.refresh_rounded : Icons.replay_rounded),
                        label: const Text('Review again'),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        onPressed: () => _markCurrentKnown(true),
                        icon: Icon(active?['known'] == 'true' ? Icons.check_circle : Icons.check_circle_outline),
                        label: Text(active?['known'] == 'true' ? 'Known' : 'Mark known'),
                      ),
                    ],
                  ),
                ],
                if (_showEditor) ...[
                  const SizedBox(height: 10),
                  TextField(controller: _front, decoration: const InputDecoration(labelText: 'Question / front')),
                  const SizedBox(height: 8),
                  TextField(controller: _back, decoration: const InputDecoration(labelText: 'Answer / back')),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() { _front.dispose(); _back.dispose(); super.dispose(); }
}
