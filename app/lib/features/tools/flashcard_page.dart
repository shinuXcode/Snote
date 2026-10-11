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
  final List<Map<String, String>> _cards = [];
  int _index = 0;
  bool _showBack = false;

  void _addCard() {
    if (_front.text.trim().isEmpty || _back.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter both the front and back.')));
      return;
    }
    setState(() {
      _cards.add({'front': _front.text.trim(), 'back': _back.text.trim()});
      _index = _cards.length - 1;
      _showBack = false;
      _front.clear();
      _back.clear();
    });
  }

  Future<void> _save() async {
    if (_front.text.trim().isNotEmpty && _back.text.trim().isNotEmpty) {
      _cards.add({'front': _front.text.trim(), 'back': _back.text.trim()});
    }
    if (_cards.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add at least one complete card first.')));
      return;
    }
    final first = _cards.first['front']!;
    final title = first.length > 36 ? first.substring(0, 33) + '...' : first;
    final note = await _notes.create(title: 'Flashcards - ' + title, folderId: widget.folderId);
    await _notes.saveContent(note.id, {
      'version': 5, 'noteType': 'flashcard',
      'flashcards': _cards, 'flashcard': _cards.first,
      'pages': <Map<String, Object?>>[], 'text_delta': const <Map<String, Object?>>[],
    });
    if (mounted) Navigator.pop(context, note);
  }

  @override
  Widget build(BuildContext context) {
    final active = _cards.isEmpty ? null : _cards[_index];
    final front = active?['front'] ?? _front.text;
    final back = active?['back'] ?? _back.text;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flashcard deck'),
        actions: [
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
                if (_cards.isNotEmpty) Text('Card ' + (_index + 1).toString() + ' of ' + _cards.length.toString()),
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
                if (_cards.isNotEmpty) Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    OutlinedButton.icon(onPressed: _index == 0 ? null : () => setState(() { _index--; _showBack = false; }), icon: const Icon(Icons.chevron_left), label: const Text('Previous')),
                    OutlinedButton.icon(onPressed: _index >= _cards.length - 1 ? null : () => setState(() { _index++; _showBack = false; }), icon: const Icon(Icons.chevron_right), label: const Text('Next')),
                  ],
                ),
                TextField(controller: _front, decoration: const InputDecoration(labelText: 'Question / front')),
                const SizedBox(height: 8),
                TextField(controller: _back, decoration: const InputDecoration(labelText: 'Answer / back')),
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
