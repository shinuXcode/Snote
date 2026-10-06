import 'package:flutter/material.dart';
import '../../data/local/folder_repository.dart';

class FoldersPage extends StatefulWidget {
  const FoldersPage({super.key});
  @override State<FoldersPage> createState() => _FoldersPageState();
}

class _FoldersPageState extends State<FoldersPage> {
  final _repo = FolderRepository();
  List<LocalFolder> _folders = const [];
  String? _parentId;

  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async { final folders = await _repo.list(parentId: _parentId); if (mounted) setState(() => _folders = folders); }

  Future<void> _create() async {
    final c = TextEditingController();
    final name = await showDialog<String>(context: context, builder: (_) => AlertDialog(
      title: const Text('Create folder'),
      content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: 'Folder name')),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('Create'))],
    ));
    c.dispose();
    if (name == null || name.trim().isEmpty) return;
    await _repo.create(name: name.trim(), parentId: _parentId);
    await _load();
  }

  Future<void> _delete(LocalFolder folder) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Delete folder?'), content: const Text('Notes inside are not deleted automatically.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete'))],
    ));
    if (ok == true) { await _repo.delete(folder.id); await _load(); }
  }

  @override Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: _parentId == null ? null : BackButton(onPressed: () { setState(() => _parentId = null); _load(); }),
        title: const Text('Folders', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [IconButton.filledTonal(onPressed: _create, tooltip: 'New folder', icon: const Icon(Icons.create_new_folder_rounded))],
      ),
      floatingActionButton: FloatingActionButton.extended(onPressed: _create, icon: const Icon(Icons.add_rounded), label: const Text('New folder')),
      body: _folders.isEmpty ? Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
        CircleAvatar(radius: 40, backgroundColor: scheme.primaryContainer, child: Icon(Icons.folder_open_rounded, size: 38, color: scheme.primary)),
        const SizedBox(height: 16), const Text('No folders yet', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)), const SizedBox(height: 6),
        const Text('Create folders to keep subjects, projects and notebooks organized.', textAlign: TextAlign.center),
        const SizedBox(height: 18), FilledButton.icon(onPressed: _create, icon: const Icon(Icons.add_rounded), label: const Text('Create folder')),
      ]))) : ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100), itemCount: _folders.length,
        itemBuilder: (_, i) { final f = _folders[i]; return Card(margin: const EdgeInsets.only(bottom: 10), child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          leading: CircleAvatar(backgroundColor: scheme.primaryContainer, child: Icon(Icons.folder_rounded, color: scheme.primary)),
          title: Text(f.name, style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: const Text('Open folder'),
          trailing: IconButton(tooltip: 'Delete', onPressed: () => _delete(f), icon: const Icon(Icons.delete_outline_rounded)),
          onTap: () { setState(() => _parentId = f.id); _load(); },
        )); },
      ),
    );
  }
}
