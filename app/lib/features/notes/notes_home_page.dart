import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/local/note_repository.dart';
import '../../sync/sync_engine.dart';
import '../../ui/snote_logo.dart';
import '../auth/login_page.dart';
import '../folders/folders_page.dart';
import '../pdf/pdf_annotation_page.dart';
import '../settings/settings_page.dart';
import '../share/qr_import_page.dart';
import '../trash/trash_page.dart';
import 'note_editor_page.dart';

class NotesHomePage extends StatefulWidget {
  final bool localOnly;
  const NotesHomePage({super.key, this.localOnly = false});
  @override State<NotesHomePage> createState() => _NotesHomePageState();
}

class _NotesHomePageState extends State<NotesHomePage> {
  final _repo = NoteRepository();
  final _sync = SyncEngine();
  final _search = TextEditingController();
  List<LocalNote> _notes = const [];
  LocalNote? _selected;
  bool _loading = true, _syncing = false;
  int _section = 0;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    unawaited(_load());
    if (!widget.localOnly) unawaited(_startSync());
  }

  Future<void> _startSync() async { await _sync.start(); await _load(); }

  Future<void> _load() async {
    final notes = await _repo.list();
    if (!mounted) return;
    final id = _selected?.id;
    LocalNote? selected;
    for (final n in notes) { if (n.id == id) selected = n; }
    setState(() {
      _notes = notes;
      _selected = selected ?? (notes.isEmpty ? null : notes.first);
      _loading = false;
    });
  }

  List<LocalNote> get _filtered {
    final q = _search.text.trim().toLowerCase();
    return q.isEmpty ? _notes : _notes.where((n) => n.title.toLowerCase().contains(q)).toList();
  }

  Future<void> _create() async {
    final note = await _repo.create();
    if (!mounted) return;
    setState(() { _notes = [note, ..._notes]; _selected = note; });
    if (MediaQuery.sizeOf(context).width < 850) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => NoteEditorPage(note: note)));
      await _load();
    }
  }

  Future<void> _open(LocalNote note) async {
    setState(() => _selected = note);
    if (MediaQuery.sizeOf(context).width < 850) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => NoteEditorPage(note: note)));
      await _load();
    }
  }

  Future<void> _rename(LocalNote note) async {
    final c = TextEditingController(text: note.title);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename note'),
        content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: 'Title')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('Save')),
        ],
      ),
    );
    c.dispose();
    if (name == null || name.trim().isEmpty) return;
    await _repo.rename(note.id, name.trim());
    await _load();
  }

  Future<void> _delete(LocalNote note) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Move to trash?'),
        content: const Text('This note will be hidden from the notebook.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Move to trash')),
        ],
      ),
    );
    if (yes != true) return;
    await _repo.delete(note.id);
    await _load();
  }

  Future<void> _syncNow() async {
    if (widget.localOnly) { await _openAccount(); return; }
    setState(() => _syncing = true);
    try { await _sync.flush(); await _load(); } finally { if (mounted) setState(() => _syncing = false); }
  }

  Future<void> _openAccount() async => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginPage()));
  Future<void> _openFolders() async { await Navigator.push(context, MaterialPageRoute(builder: (_) => const FoldersPage())); await _load(); }
  Future<void> _openSettings() async => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage()));

  Future<void> _openTools() async {
    final navigator = Navigator.of(context);
    final action = await showModalBottomSheet<String>(
      context: context, showDragHandle: true, builder: (_) => const _ToolsSheet(),
    );
    if (!mounted) return;
    if (action == 'folders') {
      await navigator.push(MaterialPageRoute(builder: (_) => const FoldersPage()));
    }
    if (action == 'pdf') {
      await navigator.push(MaterialPageRoute(builder: (_) => const PdfAnnotationPage()));
    }
    if (action == 'import') {
      await navigator.push(MaterialPageRoute(builder: (_) => const QrImportPage()));
      await _load();
    }
    if (action == 'trash') {
      await navigator.push(MaterialPageRoute(builder: (_) => const TrashPage()));
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: SafeArea(child: MediaQuery.sizeOf(context).width >= 900 ? _desktop() : _mobile()));
  }

  Widget _desktop() {
    return Row(children: [
      _SideRail(localOnly: widget.localOnly, onAccount: _openAccount, onSettings: _openSettings, onTools: _openTools, onFolders: _openFolders),
      Expanded(child: Column(children: [
        _TopBar(search: _search, localOnly: widget.localOnly, syncing: _syncing, onSync: _syncNow, onTools: _openTools),
        Expanded(child: Row(children: [
          SizedBox(width: 360, child: _NotebookPanel(notes: _filtered, selected: _selected, loading: _loading, onCreate: _create, onOpen: _open, onRename: _rename, onDelete: _delete)),
          Expanded(child: _selected == null ? const _WorkspaceEmpty() : KeyedSubtree(key: ValueKey(_selected!.id), child: NoteEditorPage(note: _selected!))),
        ])),
      ])),
    ]);
  }

  Widget _mobile() {
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(18, 12, 18, 8), child: Row(children: [
        const SnoteLogo(size: 34), const Spacer(),
        IconButton(onPressed: _syncNow, tooltip: widget.localOnly ? 'Account' : 'Sync', icon: Icon(widget.localOnly ? Icons.cloud_outlined : Icons.sync_rounded)),
        IconButton(onPressed: _openFolders, tooltip: 'Folders', icon: const Icon(Icons.folder_copy_rounded)),
        IconButton(onPressed: _openSettings, tooltip: 'Settings', icon: const Icon(Icons.tune_rounded)),
      ])),
      Padding(padding: const EdgeInsets.fromLTRB(18, 4, 18, 12), child: TextField(
        controller: _search,
        decoration: InputDecoration(hintText: 'Search notes', prefixIcon: const Icon(Icons.search_rounded), suffixIcon: _search.text.isEmpty ? null : IconButton(onPressed: _search.clear, icon: const Icon(Icons.close_rounded))),
      )),
      Expanded(child: _section == 0
          ? _NotebookPanel(notes: _filtered, selected: _selected, loading: _loading, onCreate: _create, onOpen: _open, onRename: _rename, onDelete: _delete)
          : const _MobileInfoPanel()),
      NavigationBar(selectedIndex: _section, onDestinationSelected: (v) async {
        if (v == 2) { await _openTools(); return; }
        if (v == 1) { await _openAccount(); return; }
        setState(() => _section = v);
      }, destinations: const [
        NavigationDestination(icon: Icon(Icons.notes_outlined), selectedIcon: Icon(Icons.notes_rounded), label: 'Notes'),
        NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Account'),
        NavigationDestination(icon: Icon(Icons.grid_view_rounded), label: 'Tools'),
      ]),
    ]);
  }

  @override
  void dispose() { _search.dispose(); unawaited(_sync.dispose()); super.dispose(); }
}

class _TopBar extends StatelessWidget {
  final TextEditingController search; final bool localOnly, syncing; final VoidCallback onSync, onTools;
  const _TopBar({required this.search, required this.localOnly, required this.syncing, required this.onSync, required this.onTools});
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(22, 18, 22, 14),
    child: Row(children: [
      Expanded(child: TextField(controller: search, decoration: InputDecoration(hintText: 'Search your notebook', prefixIcon: const Icon(Icons.search_rounded), suffixIcon: search.text.isEmpty ? null : IconButton(onPressed: search.clear, icon: const Icon(Icons.close_rounded))))),
      const SizedBox(width: 12),
      IconButton.filledTonal(onPressed: onTools, tooltip: 'Tools', icon: const Icon(Icons.grid_view_rounded)),
      const SizedBox(width: 8),
      FilledButton.tonalIcon(onPressed: onSync, icon: syncing ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(localOnly ? Icons.cloud_outlined : Icons.sync_rounded), label: Text(localOnly ? 'Offline' : 'Sync')),
    ]),
  );
}

class _SideRail extends StatelessWidget {
  final bool localOnly; final VoidCallback onAccount, onSettings, onTools, onFolders;
  const _SideRail({required this.localOnly, required this.onAccount, required this.onSettings, required this.onTools, required this.onFolders});
  @override Widget build(BuildContext context) {
    final active = Theme.of(context).colorScheme.primaryContainer;
    return Container(width: 236, padding: const EdgeInsets.fromLTRB(16, 22, 16, 18),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, border: Border(right: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .45)))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(padding: EdgeInsets.only(left: 8, bottom: 30), child: SnoteLogo(size: 38)),
        _RailButton(icon: Icons.notes_rounded, label: 'All notes', color: active, onTap: () {}),
        _RailButton(icon: Icons.folder_copy_rounded, label: 'Folders', color: active, onTap: onFolders),
        _RailButton(icon: Icons.person_outline_rounded, label: localOnly ? 'Sign in & sync' : 'Account', color: active, onTap: onAccount),
        _RailButton(icon: Icons.grid_view_rounded, label: 'Tools', color: active, onTap: onTools),
        const Spacer(),
        _RailButton(icon: Icons.settings_outlined, label: 'Settings', color: active, onTap: onSettings),
        const SizedBox(height: 12),
        Container(width: double.infinity, padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .55), borderRadius: BorderRadius.circular(18)),
          child: Row(children: [Icon(localOnly ? Icons.offline_bolt_rounded : Icons.cloud_done_rounded, size: 18), const SizedBox(width: 9), Expanded(child: Text(localOnly ? 'Local-first mode' : 'Cloud synced', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)))])),
      ]),
    );
  }
}

class _RailButton extends StatelessWidget {
  final IconData icon; final String label; final Color color; final VoidCallback onTap;
  const _RailButton({required this.icon, required this.label, required this.color, required this.onTap});
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: ListTile(dense: true, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), leading: Icon(icon), title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)), onTap: onTap),
  );
}

class _NotebookPanel extends StatelessWidget {
  final List<LocalNote> notes; final LocalNote? selected; final bool loading; final VoidCallback onCreate; final ValueChanged<LocalNote> onOpen, onRename, onDelete;
  const _NotebookPanel({required this.notes, required this.selected, required this.loading, required this.onCreate, required this.onOpen, required this.onRename, required this.onDelete});
  @override Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(border: Border(right: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .4)))),
    child: Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(18, 4, 18, 14), child: Row(children: [
        const Expanded(child: Text('Your notebook', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
        IconButton.filled(onPressed: onCreate, tooltip: 'New note', icon: const Icon(Icons.add_rounded)),
      ])),
      Expanded(child: loading ? const Center(child: CircularProgressIndicator()) : notes.isEmpty ? _EmptyNotes(onCreate: onCreate) : ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24), itemCount: notes.length,
        itemBuilder: (_, i) { final note = notes[i]; return _NoteCard(note: note, selected: selected?.id == note.id, onTap: () => onOpen(note), onRename: () => onRename(note), onDelete: () => onDelete(note)); },
      )),
    ]),
  );
}

class _NoteCard extends StatelessWidget {
  final LocalNote note; final bool selected; final VoidCallback onTap, onRename, onDelete;
  const _NoteCard({required this.note, required this.selected, required this.onTap, required this.onRename, required this.onDelete});
  @override Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final date = DateTime.fromMillisecondsSinceEpoch(note.updatedAt).toLocal();
    final title = note.title.trim().isEmpty ? 'Untitled note' : note.title;
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: Material(
      color: selected ? scheme.primaryContainer.withValues(alpha: .62) : scheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(borderRadius: BorderRadius.circular(18), onTap: onTap, child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 15, 8, 15),
        child: Row(children: [
          Container(width: 42, height: 42, decoration: BoxDecoration(color: selected ? scheme.primary.withValues(alpha: .12) : scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(13)), child: Icon(Icons.description_rounded, color: selected ? scheme.primary : scheme.onSurfaceVariant)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 5), Text(_dateLabel(date), style: Theme.of(context).textTheme.bodySmall)])),
          PopupMenuButton<String>(onSelected: (v) => v == 'rename' ? onRename() : onDelete(), itemBuilder: (_) => const [PopupMenuItem(value: 'rename', child: Text('Rename')), PopupMenuItem(value: 'delete', child: Text('Move to trash'))]),
        ]),
      )),
    ));
  }
  String _dateLabel(DateTime d) => 'Updated ${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

class _EmptyNotes extends StatelessWidget {
  final VoidCallback onCreate; const _EmptyNotes({required this.onCreate});
  @override Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 86, height: 86, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, shape: BoxShape.circle), child: Icon(Icons.auto_stories_rounded, size: 40, color: Theme.of(context).colorScheme.primary)),
    const SizedBox(height: 18), const Text('Your notebook is empty', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)), const SizedBox(height: 7),
    Text('Create your first page and start writing.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium), const SizedBox(height: 18),
    FilledButton.icon(onPressed: onCreate, icon: const Icon(Icons.add_rounded), label: const Text('Create note')),
  ])));
}

class _WorkspaceEmpty extends StatelessWidget {
  const _WorkspaceEmpty();
  @override Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(30), child: Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(Icons.draw_rounded, size: 58, color: Theme.of(context).colorScheme.primary), const SizedBox(height: 16),
    const Text('Pick a page to start writing', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)), const SizedBox(height: 6),
    Text('Your notebook stays local-first and ready for handwriting.', style: Theme.of(context).textTheme.bodyMedium),
  ])));
}

class _MobileInfoPanel extends StatelessWidget {
  const _MobileInfoPanel();
  @override Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(Icons.person_rounded, size: 58, color: Theme.of(context).colorScheme.primary), const SizedBox(height: 14),
    const Text('Account & sync', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)), const SizedBox(height: 7),
    const Text('Sign in to connect your notebook when cloud services are configured.', textAlign: TextAlign.center),
  ])));
}

class _ToolsSheet extends StatelessWidget {
  const _ToolsSheet();
  @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.fromLTRB(18, 6, 18, 24), child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Align(alignment: Alignment.centerLeft, child: Text('Snote tools', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900))), const SizedBox(height: 12),
    _ToolTile(icon: Icons.folder_copy_rounded, title: 'Folders', subtitle: 'Organize notebooks', value: 'folders'),
    _ToolTile(icon: Icons.picture_as_pdf_rounded, title: 'PDF annotation', subtitle: 'Write directly on PDFs', value: 'pdf'),
    _ToolTile(icon: Icons.qr_code_2_rounded, title: 'Private transfer', subtitle: 'Move notes without cloud', value: 'import'),
    _ToolTile(icon: Icons.delete_outline_rounded, title: 'Bin', subtitle: 'Recently deleted • 30 days', value: 'trash'),
  ]));
}

class _ToolTile extends StatelessWidget {
  final IconData icon; final String title, subtitle, value;
  const _ToolTile({required this.icon, required this.title, required this.subtitle, required this.value});
  @override Widget build(BuildContext context) => ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4), leading: CircleAvatar(child: Icon(icon)), title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text(subtitle), trailing: const Icon(Icons.chevron_right_rounded), onTap: () => Navigator.pop(context, value));
}
