import 'dart:async';

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/local/folder_repository.dart';
import '../../data/local/note_repository.dart';
import '../../data/local/notebook_transfer_service.dart';
import '../../sync/sync_engine.dart';
import '../../ui/snote_logo.dart';
import '../auth/login_page.dart';
import '../pdf/pdf_pro_workspace_page.dart';
import '../settings/settings_page.dart';
import '../updates/update_center_page.dart';
import '../share/qr_import_page.dart';
import '../trash/trash_page.dart';
import '../tools/flashcard_page.dart';
import '../tools/mind_map_page.dart';
import '../tools/screenshot_import_page.dart';
import 'note_editor_page.dart';

class NotesHomePage extends StatefulWidget {
  final bool localOnly;
  const NotesHomePage({super.key, this.localOnly = false});

  @override
  State<NotesHomePage> createState() => _NotesHomePageState();
}

class _NotesHomePageState extends State<NotesHomePage> {
  final _notes = NoteRepository();
  final _folders = FolderRepository();
  final _transfer = NotebookTransferService(NoteRepository());
  final _sync = SyncEngine();
  final _search = TextEditingController();

  List<LocalFolder> _folderList = const [];
  List<LocalNote> _noteList = const [];
  String? _folderId;
  final List<LocalFolder> _breadcrumbs = [];
  LocalNote? _selected;
  bool _loading = true;
  bool _syncing = false;
  bool _gridView = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    unawaited(_load());
    if (!widget.localOnly) unawaited(_startSync());
  }

  Future<void> _startSync() async {
    await _sync.start();
    await _load();
  }

  Future<void> _load() async {
    final folders = await _folders.list(parentId: _folderId);
    final notes = await _notes.list(folderId: _folderId);
    if (!mounted) return;
    final selectedId = _selected?.id;
    final visible = notes.where(_matchesSearch).toList();
    LocalNote? selected = selectedId == null
        ? (visible.isEmpty ? null : visible.first)
        : visible.cast<LocalNote?>().firstWhere((n) => n?.id == selectedId, orElse: () => null);
    setState(() {
      _folderList = folders;
      _noteList = notes;
      _selected = selected;
      _loading = false;
    });
  }

  bool _matchesSearch(LocalNote note) {
    final q = _search.text.trim().toLowerCase();
    return q.isEmpty || note.title.toLowerCase().contains(q);
  }

  List<LocalNote> get _filteredNotes => _noteList.where(_matchesSearch).toList();

  Future<void> _createFolder() async {
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('New folder'),
        content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: 'Folder name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, c.text), child: const Text('Create')),
        ],
      ),
    );
    c.dispose();
    if (name == null || name.trim().isEmpty) return;
    await _folders.create(name: name.trim(), parentId: _folderId);
    await _load();
  }

  Future<void> _createNote() async {
    final note = await _notes.create(folderId: _folderId);
    if (!mounted) return;
    setState(() => _selected = note);
    if (MediaQuery.sizeOf(context).width < 900) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => NoteEditorPage(note: note)));
      await _load();
    } else {
      await _load();
    }
  }

  Future<void> _openNote(LocalNote note) async {
    setState(() => _selected = note);
    if (MediaQuery.sizeOf(context).width < 900) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => NoteEditorPage(note: note)));
      await _load();
    }
  }

  void _openFolder(LocalFolder folder) {
    setState(() {
      _folderId = folder.id;
      _breadcrumbs.add(folder);
      _selected = null;
    });
    unawaited(_load());
  }

  void _goBackFolder() {
    if (_breadcrumbs.isEmpty) return;
    setState(() {
      _breadcrumbs.removeLast();
      _folderId = _breadcrumbs.isEmpty ? null : _breadcrumbs.last.id;
      _selected = null;
    });
    unawaited(_load());
  }

  Future<void> _renameFolder(LocalFolder folder) async {
    final c = TextEditingController(text: folder.name);
    final value = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Rename folder'),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, c.text), child: const Text('Save')),
        ],
      ),
    );
    c.dispose();
    if (value == null || value.trim().isEmpty) return;
    await _folders.rename(folder.id, value.trim());
    if (_breadcrumbs.isNotEmpty && _breadcrumbs.last.id == folder.id) {
      _breadcrumbs[_breadcrumbs.length - 1] = LocalFolder(
        id: folder.id,
        parentId: folder.parentId,
        name: value.trim(),
        createdAt: folder.createdAt,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        deletedAt: folder.deletedAt,
      );
    }
    await _load();
  }

  Future<void> _deleteFolder(LocalFolder folder) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Delete folder?'),
        content: const Text('Child folders remain deleted together with this folder. Notes are moved to the root of the notebook.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await _folders.delete(folder.id);
    if (_folderId == folder.id) {
      _goBackFolder();
      return;
    }
    await _load();
  }

  Future<void> _renameNote(LocalNote note) async {
    final c = TextEditingController(text: note.title);
    final value = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Rename note'),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, c.text), child: const Text('Save')),
        ],
      ),
    );
    c.dispose();
    if (value == null || value.trim().isEmpty) return;
    await _notes.rename(note.id, value.trim());
    await _load();
  }

  Future<void> _deleteNote(LocalNote note) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Move to trash?'),
        content: const Text('The note will be hidden from this folder and can be restored from Bin.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Move to trash')),
        ],
      ),
    );
    if (ok != true) return;
    await _notes.delete(note.id);
    await _load();
  }

  Future<void> _openPlus() async {
    final messenger = ScaffoldMessenger.of(context);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _PlusSheet(),
    );
    if (!mounted) return;

    try {
      switch (action) {
        case 'note':
          await _createNote();
          break;
        case 'folder':
          await _createFolder();
          break;
        case 'pdf':
          await Navigator.push(context, MaterialPageRoute(builder: (_) => PdfProWorkspacePage(folderId: _folderId)));
          await _load();
          break;
        case 'import':
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const QrImportPage()));
          await _load();
          break;
        case 'files':
          final count = await _transfer.importPicked();
          if (mounted) messenger.showSnackBar(SnackBar(content: Text('Imported $count item(s).')));
          await _load();
          break;
        case 'screenshot':
          await Navigator.push(context, MaterialPageRoute(builder: (_) => ScreenshotImportPage(folderId: _folderId)));
          await _load();
          break;
        case 'mindmap':
          await Navigator.push(context, MaterialPageRoute(builder: (_) => MindMapPage(folderId: _folderId)));
          await _load();
          break;
        case 'flashcard':
          await Navigator.push(context, MaterialPageRoute(builder: (_) => FlashcardPage(folderId: _folderId)));
          await _load();
          break;
        case 'trash':
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const TrashPage()));
          await _load();
          break;
      }
    } catch (error) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text('Action failed: $error')));
    }
  }

  Future<void> _syncNow() async {
    if (widget.localOnly) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginPage()));
      return;
    }
    setState(() => _syncing = true);
    try {
      await _sync.flush();
      await _load();
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      body: SafeArea(child: wide ? _desktop() : _mobile()),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add',
        onPressed: _openPlus,
        child: const Icon(Icons.add_rounded),
      ),
    );
  }

  Widget _desktop() {
    return Row(
      children: [
        _SideRail(localOnly: widget.localOnly, syncing: _syncing, onAccount: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginPage())), onSettings: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage()))),
        Expanded(
          child: Column(
            children: [
              _TopBar(
                search: _search,
                syncing: _syncing,
                localOnly: widget.localOnly,
                onSync: _syncNow,
              ),
              Row(children: [
                Expanded(child: _Breadcrumbs(items: _breadcrumbs, onBack: _goBackFolder, onRoot: () {
                setState(() {
                  _breadcrumbs.clear();
                  _folderId = null;
                  _selected = null;
                });
                unawaited(_load());
              }),
                )),
                IconButton(tooltip: _gridView ? 'List view' : 'Grid view', onPressed: () => setState(() => _gridView = !_gridView), icon: Icon(_gridView ? Icons.view_list_rounded : Icons.grid_view_rounded)),
              ]),
              Expanded(
                child: Row(
                  children: [
                    SizedBox(width: 380, child: _HierarchyPanel(
                      folderList: _folderList,
                      notes: _filteredNotes,
                      selected: _selected,
                      gridView: _gridView,
                      loading: _loading,
                      onFolder: _openFolder,
                      onNewFolder: _createFolder,
                      onNewNote: _createNote,
                      onRenameFolder: _renameFolder,
                      onDeleteFolder: _deleteFolder,
                      onOpenNote: _openNote,
                      onRenameNote: _renameNote,
                      onDeleteNote: _deleteNote,
                    )),
                    const VerticalDivider(width: 1),
                    Expanded(child: _selected == null ? const _WorkspaceEmpty() : KeyedSubtree(key: ValueKey(_selected!.id), child: NoteEditorPage(note: _selected!))),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _mobile() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              const SnoteLogo(size: 34),
              const Spacer(),
              IconButton(onPressed: _syncNow, tooltip: widget.localOnly ? 'Account' : 'Sync', icon: Icon(widget.localOnly ? Icons.cloud_outlined : Icons.sync_rounded)),
              IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UpdateCenterPage())), tooltip: 'Notifications', icon: const Icon(Icons.notifications_none_rounded)),
              IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage())), tooltip: 'Settings', icon: const Icon(Icons.tune_rounded)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
          child: TextField(
            controller: _search,
            decoration: InputDecoration(hintText: 'Search notes', prefixIcon: const Icon(Icons.search_rounded), suffixIcon: _search.text.isEmpty ? null : IconButton(onPressed: _search.clear, icon: const Icon(Icons.close_rounded))),
          ),
        ),
        _Breadcrumbs(items: _breadcrumbs, onBack: _goBackFolder, onRoot: () {
          setState(() {
            _breadcrumbs.clear();
            _folderId = null;
            _selected = null;
          });
          unawaited(_load());
        }),
        Expanded(
          child: Column(
            children: [
              const _FrontNoticeCard(),
              Expanded(child: _HierarchyPanel(
            compact: true,
            folderList: _folderList,
            notes: _filteredNotes,
            selected: _selected,
            gridView: _gridView,
            loading: _loading,
            onFolder: _openFolder,
            onNewFolder: _createFolder,
            onNewNote: _createNote,
            onRenameFolder: _renameFolder,
            onDeleteFolder: _deleteFolder,
            onOpenNote: _openNote,
            onRenameNote: _renameNote,
            onDeleteNote: _deleteNote,
              )),
          ],
        ),
      ],
    );
  }

  @override
  void dispose() {
    _search.dispose();
    unawaited(_sync.dispose());
    super.dispose();
  }
}

class _SideRail extends StatelessWidget {
  final bool localOnly, syncing;
  final VoidCallback onAccount, onSettings;
  const _SideRail({required this.localOnly, required this.syncing, required this.onAccount, required this.onSettings});

  @override
  Widget build(BuildContext context) => Container(
    width: 220,
    padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      border: Border(right: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .4))),
    ),
    child: Column(
      children: [
        const Padding(padding: EdgeInsets.only(left: 8, bottom: 28), child: Align(alignment: Alignment.centerLeft, child: SnoteLogo(size: 38))),
        ListTile(leading: const Icon(Icons.auto_stories_rounded), title: const Text('Notebook'), selected: true, onTap: () {}),
        ListTile(leading: const Icon(Icons.person_outline_rounded), title: Text(localOnly ? 'Sign in & sync' : 'Account'), onTap: onAccount),
        ListTile(leading: const Icon(Icons.settings_outlined), title: const Text('Settings'), onTap: onSettings),
        ListTile(leading: const Icon(Icons.notifications_none_rounded), title: const Text('Notifications'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UpdateCenterPage()))),
        const Spacer(),
        ListTile(
          leading: Icon(localOnly ? Icons.offline_bolt_rounded : Icons.cloud_done_rounded),
          title: Text(localOnly ? 'Offline first' : syncing ? 'Syncing…' : 'Synced'),
          dense: true,
        ),
      ],
    ),
  );
}

class _TopBar extends StatelessWidget {
  final TextEditingController search;
  final bool syncing, localOnly;
  final VoidCallback onSync;
  const _TopBar({required this.search, required this.syncing, required this.localOnly, required this.onSync});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
    child: Row(
      children: [
        Expanded(child: TextField(controller: search, decoration: const InputDecoration(hintText: 'Search your notebook', prefixIcon: Icon(Icons.search_rounded)))),
        const SizedBox(width: 10),
        FilledButton.tonalIcon(onPressed: onSync, icon: syncing ? const SizedBox.square(dimension: 17, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(localOnly ? Icons.cloud_outlined : Icons.sync_rounded), label: Text(localOnly ? 'Offline' : 'Sync')),
      ],
    ),
  );
}

class _Breadcrumbs extends StatelessWidget {
  final List<LocalFolder> items;
  final VoidCallback onBack, onRoot;
  const _Breadcrumbs({required this.items, required this.onBack, required this.onRoot});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
    child: Row(
      children: [
        IconButton(onPressed: items.isEmpty ? null : onBack, icon: const Icon(Icons.arrow_back_rounded)),
        TextButton.icon(onPressed: onRoot, icon: const Icon(Icons.home_outlined, size: 18), label: const Text('Notebook')),
        for (final item in items) ...[
          const Icon(Icons.chevron_right_rounded, size: 18),
          Flexible(child: Text(item.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
        ],
      ],
    ),
  );
}

class _HierarchyPanel extends StatelessWidget {
  final List<LocalFolder> folderList;
  final List<LocalNote> notes;
  final LocalNote? selected;
  final bool loading, compact;
  final VoidCallback onNewFolder, onNewNote;
  final ValueChanged<LocalFolder> onFolder, onRenameFolder, onDeleteFolder;
  final ValueChanged<LocalNote> onOpenNote, onRenameNote, onDeleteNote;

  const _HierarchyPanel({
    required this.folderList,
    required this.notes,
    required this.selected,
    required this.loading,
    this.gridView = false,
    this.compact = false,
    required this.onFolder,
    required this.onNewFolder,
    required this.onNewNote,
    required this.onRenameFolder,
    required this.onDeleteFolder,
    required this.onOpenNote,
    required this.onRenameNote,
    required this.onDeleteNote,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: EdgeInsets.fromLTRB(compact ? 12 : 14, 4, compact ? 12 : 14, 110),
      children: [
        Row(
          children: [
            const Expanded(child: Text('Folders & notes', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
            IconButton(onPressed: onNewFolder, tooltip: 'New folder', icon: const Icon(Icons.create_new_folder_outlined)),
          ],
        ),
        const SizedBox(height: 8),
        if (folderList.isEmpty && notes.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 80, horizontal: 20),
            child: Column(
              children: [
                Icon(Icons.folder_open_rounded, size: 52),
                SizedBox(height: 14),
                Text('Nothing here yet', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                SizedBox(height: 6),
                Text('Create a subject folder, open it, then create chapter folders and notes inside it.', textAlign: TextAlign.center),
              ],
            ),
          ),
        ...folderList.map((folder) => Card(
          child: ListTile(
            leading: CircleAvatar(backgroundColor: _folderColor(folder.id).withValues(alpha: .18), foregroundColor: _folderColor(folder.id), child: const Icon(Icons.folder_rounded)),
            title: Text(folder.name, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: const Text('Open folder'),
            trailing: PopupMenuButton<String>(
              onSelected: (v) => v == 'rename' ? onRenameFolder(folder) : onDeleteFolder(folder),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Rename')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
            onTap: () => onFolder(folder),
          ),
        )),
        if (notes.isNotEmpty) const Padding(padding: EdgeInsets.fromLTRB(4, 18, 4, 8), child: Text('Notes', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900))),
        if (gridView && notes.isNotEmpty)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: compact ? 2 : 3,
              mainAxisExtent: 112,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: notes.length,
            itemBuilder: (_, index) => _HomeNoteTile(note: notes[index], selected: selected?.id == notes[index].id, onOpen: () => onOpenNote(notes[index]), onRename: () => onRenameNote(notes[index]), onDelete: () => onDeleteNote(notes[index]), compactCard: true),
          )
        else
          ...notes.map((note) => _HomeNoteTile(note: note, selected: selected?.id == note.id, onOpen: () => onOpenNote(note), onRename: () => onRenameNote(note), onDelete: () => onDeleteNote(note))),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(onPressed: onNewNote, icon: const Icon(Icons.note_add_outlined), label: const Text('New note here')),
      ],
    );
  }
}

class _HomeNoteTile extends StatelessWidget {
  final LocalNote note;
  final bool selected;
  final VoidCallback onOpen, onRename, onDelete;
  final bool compactCard;
  const _HomeNoteTile({required this.note, required this.selected, required this.onOpen, required this.onRename, required this.onDelete, this.compactCard = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: selected ? scheme.primaryContainer.withValues(alpha: .6) : null,
      child: compactCard
          ? InkWell(onTap: onOpen, child: Padding(padding: const EdgeInsets.all(10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.description_outlined, color: scheme.primary), const Spacer(), Text(note.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 2), Text(_noteTags(note), maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall)])))
          : ListTile(
        leading: const Icon(Icons.description_outlined),
        title: Text(note.title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(note.noteType),
        onTap: onOpen,
        trailing: PopupMenuButton<String>(
          onSelected: (v) => v == 'rename' ? onRename() : onDelete(),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'rename', child: Text('Rename')),
            PopupMenuItem(value: 'delete', child: Text('Move to trash')),
          ],
        ),
      ),
    );
  }
}

String _noteTags(LocalNote note) {
  final raw = note.contentJson;
  if (raw == null || raw.isEmpty) return note.noteType;
  try {
    final value = jsonDecode(raw);
    if (value is Map && value['tags'] is List) {
      final tags = (value['tags'] as List).map((e) => e.toString()).where((e) => e.isNotEmpty).take(3).join('  #');
      if (tags.isNotEmpty) return '#$tags';
    }
  } catch (_) {}
  return note.noteType;
}

Color _folderColor(String id) {
  const palette = <Color>[Color(0xff2563eb), Color(0xff7c3aed), Color(0xffdb2777), Color(0xffea580c), Color(0xff16a34a), Color(0xff0891b2)];
  var hash = 0;
  for (final code in id.codeUnits) hash = (hash * 31 + code) & 0x7fffffff;
  return palette[hash % palette.length];
}

class _WorkspaceEmpty extends StatelessWidget {
  const _WorkspaceEmpty();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.edit_note_rounded, size: 64, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 14),
          const Text('Your writing workspace', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          const Text('Choose a note from the folder hierarchy, or use + to add a new note, PDF, import or study tool.', textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

class _PlusSheet extends StatelessWidget {
  const _PlusSheet();

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Align(alignment: Alignment.centerLeft, child: Text('Add to notebook', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900))),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: const [
              _ActionChip(icon: Icons.note_add_outlined, label: 'New note', value: 'note'),
              _ActionChip(icon: Icons.create_new_folder_outlined, label: 'New folder', value: 'folder'),
              _ActionChip(icon: Icons.picture_as_pdf_outlined, label: 'PDF annotation', value: 'pdf'),
              _ActionChip(icon: Icons.file_upload_outlined, label: 'Import note/file', value: 'files'),
              _ActionChip(icon: Icons.qr_code_2_rounded, label: 'Private transfer', value: 'import'),
              _ActionChip(icon: Icons.image_outlined, label: 'Screenshot', value: 'screenshot'),
              _ActionChip(icon: Icons.account_tree_outlined, label: 'Mind map', value: 'mindmap'),
              _ActionChip(icon: Icons.style_outlined, label: 'Flashcards', value: 'flashcard'),
              _ActionChip(icon: Icons.delete_outline_rounded, label: 'Bin', value: 'trash'),
            ],
          ),
        ],
      ),
    ),
  );
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _ActionChip({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => ActionChip(
    avatar: Icon(icon, size: 19),
    label: Text(label),
    onPressed: () => Navigator.pop(context, value),
  );
}

class _FrontNoticeCard extends StatelessWidget {
  const _FrontNoticeCard();

  Future<void> _instagram() async {
    final uri = Uri.parse('https://instagram.com/');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: Card(
        child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.notifications_active_outlined)),
          title: const Text('Snote 1.1.0 is here', style: TextStyle(fontWeight: FontWeight.w900)),
          subtitle: const Text('PDF workspace, live ink, Smart Templates and optional E2E encryption.'),
          trailing: Wrap(
            spacing: 2,
            children: [
              IconButton(
                tooltip: 'Open notifications',
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UpdateCenterPage())),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
              IconButton(
                tooltip: 'Instagram',
                onPressed: _instagram,
                icon: const Icon(Icons.camera_alt_outlined),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
