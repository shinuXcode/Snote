import 'package:flutter/material.dart';
import '../../data/local/folder_repository.dart';

class FoldersPage extends StatefulWidget {
  const FoldersPage({super.key});

  @override
  State<FoldersPage> createState() => _FoldersPageState();
}

class _FoldersPageState extends State<FoldersPage> {
  final _repo = FolderRepository();
  List<LocalFolder> _folders = const [];
  String? _parentId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final folders = await _repo.list(parentId: _parentId);
    if (mounted) setState(() => _folders = folders);
  }

  Future<void> _create() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Folder name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (name == null || name.trim().isEmpty) return;
    await _repo.create(name: name, parentId: _parentId);
    await _load();
  }

  Future<void> _delete(LocalFolder folder) async {
    await _repo.delete(folder.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Folders'),
        leading: _parentId == null
            ? null
            : BackButton(
                onPressed: () {
                  setState(() => _parentId = null);
                  _load();
                },
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.create_new_folder_outlined),
        label: const Text('New folder'),
      ),
      body: _folders.isEmpty
          ? const Center(child: Text('No folders yet.'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _folders.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final folder = _folders[index];
                return ListTile(
                  leading: const Icon(Icons.folder_rounded),
                  title: Text(folder.name),
                  trailing: IconButton(
                    tooltip: 'Delete folder',
                    onPressed: () => _delete(folder),
                    icon: const Icon(Icons.delete_outline),
                  ),
                  onTap: () {
                    setState(() => _parentId = folder.id);
                    _load();
                  },
                );
              },
            ),
    );
  }
}
