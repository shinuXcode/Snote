import 'dart:convert';

import 'package:flutter/material.dart';

import '../../data/local/folder_repository.dart';
import '../../data/local/note_repository.dart';
import 'flashcard_page.dart';
import 'mind_map_page.dart';

/// Folder-aware library for saved flashcard decks or mind maps.
class NoteCollectionPage extends StatefulWidget {
  final String kind;

  const NoteCollectionPage({super.key, required this.kind})
      : assert(kind == 'flashcard' || kind == 'mindmap');

  @override
  State<NoteCollectionPage> createState() => _NoteCollectionPageState();
}

class _NoteCollectionPageState extends State<NoteCollectionPage> {
  final _notes = NoteRepository();
  final _folders = FolderRepository();
  final _search = TextEditingController();
  List<LocalNote> _items = const [];
  List<LocalFolder> _allFolders = const [];
  bool _loading = true;

  String get _label => widget.kind == 'flashcard' ? 'Flashcard decks' : 'Mind maps';
  IconData get _icon => widget.kind == 'flashcard'
      ? Icons.style_rounded
      : Icons.account_tree_rounded;

  String _contentKind(LocalNote note) {
    try {
      final decoded = jsonDecode(note.contentJson ?? '{}');
      if (decoded is Map && decoded['noteType'] is String) {
        return decoded['noteType'] as String;
      }
    } catch (_) {}
    return note.noteType;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _notes.listAllVisible(limit: 1000),
        _folders.listAllVisible(),
      ]);
      if (!mounted) return;
      final allNotes = results[0] as List<LocalNote>;
      setState(() {
        _items = allNotes.where((note) => _contentKind(note) == widget.kind).toList();
        _allFolders = results[1] as List<LocalFolder>;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load ${_label.toLowerCase()}: $error')),
      );
    }
  }

  Future<void> _create() async {
    final page = widget.kind == 'flashcard'
        ? const FlashcardPage()
        : const MindMapPage();
    await Navigator.push<LocalNote>(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
    if (mounted) await _load();
  }

  Future<void> _open(LocalNote note) async {
    final page = widget.kind == 'flashcard'
        ? FlashcardPage(note: note, folderId: note.folderId)
        : MindMapPage(note: note, folderId: note.folderId);
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
    if (mounted) await _load();
  }

  @override
  void initState() {
    super.initState();
    _search.addListener(_refresh);
    _load();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _search.removeListener(_refresh);
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final foldersById = {for (final folder in _allFolders) folder.id: folder};
    final query = _search.text.trim().toLowerCase();
    final filtered = _items.where((note) =>
        query.isEmpty || note.title.toLowerCase().contains(query)).toList();
    final grouped = <String?, List<LocalNote>>{};
    for (final note in filtered) {
      grouped.putIfAbsent(note.folderId, () => <LocalNote>[]).add(note);
    }
    final folderIds = grouped.keys.toList()
      ..sort((a, b) {
        if (a == null) return -1;
        if (b == null) return 1;
        return (foldersById[a]?.name ?? '').compareTo(foldersById[b]?.name ?? '');
      });

    return Scaffold(
      appBar: AppBar(
        title: Text(_label),
        actions: [
          IconButton(
            tooltip: 'Refresh library',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add_rounded),
        label: Text(widget.kind == 'flashcard' ? 'New deck' : 'New mind map'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: 'Search ${_label.toLowerCase()}',
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: _search.clear,
                        icon: const Icon(Icons.close_rounded),
                      ),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_icon, size: 44, color: Theme.of(context).colorScheme.outline),
                            const SizedBox(height: 10),
                            Text(query.isEmpty ? 'No saved ${_label.toLowerCase()} yet.' : 'No matches found.'),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: _create,
                              icon: const Icon(Icons.add_rounded),
                              label: Text(widget.kind == 'flashcard' ? 'Create a deck' : 'Create a mind map'),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 92),
                          itemCount: folderIds.length,
                          itemBuilder: (context, index) {
                            final folderId = folderIds[index];
                            final folderName = folderId == null
                                ? 'Unfiled'
                                : foldersById[folderId]?.name ?? 'Other folder';
                            final notes = grouped[folderId]!;
                            return Card(
                              clipBehavior: Clip.antiAlias,
                              margin: const EdgeInsets.only(bottom: 10),
                              child: ExpansionTile(
                                initiallyExpanded: true,
                                leading: Icon(folderId == null ? Icons.folder_open_rounded : Icons.folder_rounded),
                                title: Text(folderName, maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: Text('${notes.length} ${widget.kind == 'flashcard' ? 'deck(s)' : 'map(s)'}'),
                                children: [
                                  for (final note in notes)
                                    ListTile(
                                      leading: Icon(_icon),
                                      title: Text(note.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                                      subtitle: Text('Updated ${DateTime.fromMillisecondsSinceEpoch(note.updatedAt).toLocal()}'),
                                      trailing: const Icon(Icons.chevron_right_rounded),
                                      onTap: () => _open(note),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
