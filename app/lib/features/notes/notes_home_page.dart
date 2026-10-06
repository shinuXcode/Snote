import 'dart:async';

import 'package:flutter/material.dart';
import '../../data/local/note_repository.dart';
import '../../data/remote/supabase_service.dart';
import '../../sync/sync_engine.dart';
import '../../ui/snote_logo.dart';
import '../auth/login_page.dart';
import 'note_editor_page.dart';

class NotesHomePage extends StatefulWidget {
  final bool localOnly;
  const NotesHomePage({super.key, this.localOnly = false});

  @override
  State<NotesHomePage> createState() => _NotesHomePageState();
}

class _NotesHomePageState extends State<NotesHomePage> {
  final _repo = NoteRepository();
  final _sync = SyncEngine();

  List<LocalNote> _notes = const [];
  LocalNote? _selected;
  bool _loading = true;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    if (!widget.localOnly) unawaited(_startSync());
  }

  Future<void> _startSync() async {
    await _sync.start();
    await _load();
  }

  Future<void> _load() async {
    final notes = await _repo.list();
    if (!mounted) return;

    final selectedId = _selected?.id;
    LocalNote? nextSelected;

    if (notes.isNotEmpty) {
      nextSelected = notes.firstWhere(
        (n) => n.id == selectedId,
        orElse: () => notes.first,
      );
    }

    setState(() {
      _notes = notes;
      _selected = nextSelected;
      _loading = false;
    });
  }

  Future<void> _create() async {
    final note = await _repo.create();
    if (!mounted) return;

    setState(() {
      _notes = [note, ..._notes];
      _selected = note;
    });

    if (MediaQuery.sizeOf(context).width < 850) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => NoteEditorPage(note: note)),
      );
      await _load();
    }
  }

  Future<void> _open(LocalNote note) async {
    setState(() => _selected = note);

    if (MediaQuery.sizeOf(context).width < 850) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => NoteEditorPage(note: note)),
      );
      await _load();
    }
  }

  Future<void> _rename(LocalNote note) async {
    final controller = TextEditingController(text: note.title);

    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename note'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Note title'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (name == null || name.trim().isEmpty) return;

    await _repo.rename(note.id, name.trim());
    await _load();
  }

  Future<void> _delete(LocalNote note) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Move to trash?'),
        content: Text(note.title + ' will be hidden from the notebook.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Move to trash'),
          ),
        ],
      ),
    );

    if (yes != true) return;

    await _repo.delete(note.id);
    await _load();
  }

  Future<void> _manualSync() async {
    if (widget.localOnly) return;

    setState(() => _syncing = true);
    try {
      await _sync.flush();
      await _load();
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _openAccount() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 850;

    return Scaffold(
      appBar: AppBar(
        title: const SnoteLogo(size: 34),
        actions: [
          if (widget.localOnly)
            TextButton.icon(
              onPressed: _openAccount,
              icon: const Icon(Icons.cloud_outlined),
              label: const Text('Sign in to sync'),
            ),
          if (!widget.localOnly)
            IconButton(
              tooltip: 'Sync now',
              onPressed: _syncing ? null : _manualSync,
              icon: _syncing
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync_rounded),
            ),
          if (!widget.localOnly)
            IconButton(
              tooltip: 'Sign out',
              onPressed: () => SnoteSupabase.client?.auth.signOut(),
              icon: const Icon(Icons.logout_rounded),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New note'),
      ),
      body: wide
          ? Row(
              children: [
                SizedBox(
                  width: 320,
                  child: _NoteList(
                    notes: _notes,
                    selected: _selected,
                    loading: _loading,
                    onOpen: _open,
                    onRename: _rename,
                    onDelete: _delete,
                  ),
                ),
                Expanded(
                  child: _selected == null
                      ? const _EmptyEditor()
                      : KeyedSubtree(
                          key: ValueKey(_selected!.id),
                          child: NoteEditorPage(note: _selected!),
                        ),
                ),
              ],
            )
          : _NoteList(
              notes: _notes,
              selected: _selected,
              loading: _loading,
              onOpen: _open,
              onRename: _rename,
              onDelete: _delete,
            ),
    );
  }

  @override
  void dispose() {
    unawaited(_sync.dispose());
    super.dispose();
  }
}

class _NoteList extends StatelessWidget {
  final List<LocalNote> notes;
  final LocalNote? selected;
  final bool loading;
  final ValueChanged<LocalNote> onOpen;
  final ValueChanged<LocalNote> onRename;
  final ValueChanged<LocalNote> onDelete;

  const _NoteList({
    required this.notes,
    required this.selected,
    required this.loading,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());

    if (notes.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'No notes yet. Create one and start writing.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
      itemCount: notes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        final note = notes[index];

        return ListTile(
          selected: selected?.id == note.id,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          leading: const CircleAvatar(
            child: Icon(Icons.note_alt_outlined),
          ),
          title: Text(
            note.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            DateTime.fromMillisecondsSinceEpoch(note.updatedAt)
                .toLocal()
                .toString(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => onOpen(note),
          trailing: PopupMenuButton<String>(
            onSelected: (action) {
              if (action == 'rename') onRename(note);
              if (action == 'delete') onDelete(note);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'rename',
                child: Text('Rename'),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Text('Move to trash'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EmptyEditor extends StatelessWidget {
  const _EmptyEditor();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.draw_rounded, size: 70),
          SizedBox(height: 12),
          Text('Select a note or create a new one'),
        ],
      ),
    );
  }
}
