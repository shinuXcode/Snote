import 'package:flutter/material.dart';
import '../../data/local/folder_repository.dart';
import '../../data/local/note_repository.dart';
import '../notes/note_editor_page.dart';
import '../pdf/pdf_annotation_page.dart';

class FoldersPage extends StatefulWidget {
  const FoldersPage({super.key});
  @override State<FoldersPage> createState() => _FoldersPageState();
}

class _FoldersPageState extends State<FoldersPage> {
  final _folders = FolderRepository();
  final _notes = NoteRepository();
  List<LocalFolder> _folderList = [];
  List<LocalNote> _noteList = [];
  String? _parentId;
  final List<LocalFolder> _breadcrumbs = [];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final folders = await _folders.list(parentId: _parentId);
    final notes = await _notes.list(folderId: _parentId);
    if (mounted) setState(() { _folderList = folders; _noteList = notes; });
  }

  Future<void> _createFolder() async {
    final c = TextEditingController();
    final name = await showDialog<String>(context: context, builder: (_) => AlertDialog(
      title: const Text('Create folder'),
      content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: 'Folder name')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('Create')),
      ],
    ));
    c.dispose();
    if (name == null || name.trim().isEmpty) return;
    await _folders.create(name: name.trim(), parentId: _parentId);
    await _load();
  }

  Future<void> _importPdf() async {\n    await Navigator.push(context, MaterialPageRoute(builder: (_) => PdfAnnotationPage(folderId: _parentId)));\n    await _load();\n  }\n\n  Future<void> _createNote() async {
    final note = await _notes.create(folderId: _parentId);
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => NoteEditorPage(note: note)));
    await _load();
  }

  Future<void> _renameFolder(LocalFolder f) async {
    final c = TextEditingController(text: f.name);
    final name = await showDialog<String>(context: context, builder: (_) => AlertDialog(
      title: const Text('Rename folder'),
      content: TextField(controller: c, autofocus: true),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('Save'))],
    ));
    c.dispose();
    if (name == null || name.trim().isEmpty) return;
    await _folders.rename(f.id, name.trim());
    await _load();
  }

  Future<void> _folderDelete(LocalFolder f) async {
    final yes = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Delete folder?'),
      content: const Text('The folder and its child content will be removed from the notebook index.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete'))],
    ));
    if (yes == true) { await _folders.delete(f.id); await _load(); }
  }

  Future<void> _moveNote(LocalNote note) async {
    final roots = await _folders.list();
    final choice = await showModalBottomSheet<String?>(context: context, showDragHandle: true, builder: (_) => SafeArea(
      child: ListView(shrinkWrap: true, children: [
        const ListTile(title: Text('Move note', style: TextStyle(fontWeight: FontWeight.w900))),
        ListTile(title: const Text('Root / All notes'), leading: const Icon(Icons.home_work_outlined), onTap: () => Navigator.pop(context, null)),
        ...roots.map((f) => ListTile(title: Text(f.name), leading: const Icon(Icons.folder_rounded), onTap: () => Navigator.pop(context, f.id))),
      ]),
    ));
    await _notes.moveToFolder(note.id, choice);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final title = _parentId == null ? 'Folders' : (_breadcrumbs.isEmpty ? 'Folder' : _breadcrumbs.last.name);
    return Scaffold(
      appBar: AppBar(
        leading: _parentId == null ? null : BackButton(onPressed: () {
          if (_breadcrumbs.length > 1) {
            _breadcrumbs.removeLast();
            _parentId = _breadcrumbs.last.id;
          } else {
            _breadcrumbs.clear();
            _parentId = null;
          }
          _load();
        }),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(onPressed: _importPdf, tooltip: 'Import PDF', icon: const Icon(Icons.picture_as_pdf_rounded)),\n          IconButton(onPressed: _createFolder, tooltip: 'New folder', icon: const Icon(Icons.create_new_folder_rounded)),
          IconButton(onPressed: _createNote, tooltip: 'New note', icon: const Icon(Icons.note_add_rounded)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 100),
        children: [
          if (_folderList.isNotEmpty) ...[
            const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('Folders', style: TextStyle(fontWeight: FontWeight.w900))),
            ..._folderList.map((f) => Card(
              child: ListTile(
                leading: const Icon(Icons.folder_rounded),
                title: Text(f.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) => v == 'rename' ? _renameFolder(f) : _folderDelete(f),
                  itemBuilder: (_) => const [PopupMenuItem(value: 'rename', child: Text('Rename')), PopupMenuItem(value: 'delete', child: Text('Delete'))],
                ),
                onTap: () {
                  setState(() {
                    _parentId = f.id;
                    _breadcrumbs.add(f);
                  });
                  _load();
                },
              ),
            )),
            const SizedBox(height: 16),
          ],
          if (_noteList.isNotEmpty) const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('Notes', style: TextStyle(fontWeight: FontWeight.w900))),
          ..._noteList.map((n) => Card(
            child: ListTile(
              leading: const Icon(Icons.description_rounded),
              title: Text(n.title, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: const Text('Open note'),
              trailing: IconButton(onPressed: () => _moveNote(n), icon: const Icon(Icons.drive_file_move_outlined)),
              onTap: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => NoteEditorPage(note: n)));
                await _load();
              },
            ),
          )),
          if (_folderList.isEmpty && _noteList.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 100, horizontal: 28),
              child: Column(children: [
                Icon(Icons.folder_open_rounded, size: 56),
                SizedBox(height: 14),
                Text('Nothing here yet', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                SizedBox(height: 6),
                Text('Create a folder or a note to start organizing.', textAlign: TextAlign.center),
              ]),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(onPressed: _createNote, icon: const Icon(Icons.note_add_rounded), label: const Text('New note')),
    );
  }
}
