import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'folder_cover_art.dart';
import 'folder_cover_repository.dart';

class FolderCoverLibraryPage extends StatefulWidget {
  final bool selectionMode;
  final String? initialCoverKey;

  const FolderCoverLibraryPage({
    super.key,
    this.selectionMode = false,
    this.initialCoverKey,
  });

  @override
  State<FolderCoverLibraryPage> createState() => _FolderCoverLibraryPageState();
}

class _FolderCoverLibraryPageState extends State<FolderCoverLibraryPage> {
  final _repository = FolderCoverRepository.instance;
  final _picker = ImagePicker();
  final _nameController = TextEditingController();
  List<LocalFolderCover> _customCovers = <LocalFolderCover>[];
  String? _selectedKey;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _selectedKey = widget.initialCoverKey;
    _loadCustomCovers();
  }

  Future<void> _loadCustomCovers() async {
    try {
      final items = await _repository.list();
      if (mounted) setState(() { _customCovers = items; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addCustomCover() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final picked = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 1400, imageQuality: 82);
      if (picked == null) return;
      final Uint8List bytes = await picked.readAsBytes();
      if (bytes.isEmpty) throw StateError('The selected image is empty.');
      if (bytes.length > 4 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Choose an image under 4 MB for a folder cover.')),
          );
        }
        return;
      }
      final basename = picked.name.replaceFirst(RegExp(r'\.[^.]+$'), '').trim();
      _nameController.text = basename.isEmpty ? 'My cover' : basename;
      if (!mounted) return;
      final name = await showDialog<String>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Name custom cover'),
          content: TextField(controller: _nameController, autofocus: true, decoration: const InputDecoration(labelText: 'Cover name')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialog, _nameController.text), child: const Text('Save cover')),
          ],
        ),
      );
      if (name == null) return;
      final id = await _repository.add(name: name, imageBytes: bytes);
      await _loadCustomCovers();
      if (mounted) setState(() => _selectedKey = 'cover:' + id);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not add cover: ' + error.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteCover(LocalFolderCover cover) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Delete custom cover?'),
        content: const Text('Folders using it will fall back to a generated cover.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await _repository.delete(cover.id);
    if (mounted) setState(() {
      _customCovers.removeWhere((item) => item.id == cover.id);
      if (_selectedKey == cover.key) _selectedKey = null;
    });
  }

  String _builtInName(int index) => 'Cover ' + (index + 1).toString().padLeft(2, '0');

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = 100 + _customCovers.length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cover library'),
        actions: [
          IconButton(tooltip: 'Add custom cover from Gallery', onPressed: _busy ? null : _addCustomCover, icon: const Icon(Icons.add_photo_alternate_outlined)),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '100 built-in covers + ' + _customCovers.length.toString() + ' custom covers',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                if (_busy) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
          ),
          Expanded(
            child: _loading ? const Center(child: CircularProgressIndicator()) : GridView.builder(
              padding: const EdgeInsets.fromLTRB(14, 2, 14, 18),
              itemCount: total,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 178, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: .72,
              ),
              itemBuilder: (context, index) {
                final custom = index >= 100 ? _customCovers[index - 100] : null;
                final key = custom == null ? 'cover:' + index.toString() : custom.key;
                final title = custom == null ? _builtInName(index) : custom.name;
                final selected = _selectedKey == key;
                return Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant,
                      width: selected ? 3 : 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(13),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        FolderCoverArt(coverKey: key, title: title),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => setState(() => _selectedKey = key),
                            onDoubleTap: widget.selectionMode ? () => Navigator.pop(context, key) : null,
                          ),
                        ),
                        if (selected)
                          const Positioned(
                            left: 6, top: 6,
                            child: CircleAvatar(
                              radius: 13, backgroundColor: Colors.white,
                              child: Icon(Icons.check_circle_rounded, color: Colors.green, size: 24),
                            ),
                          ),
                        if (custom != null)
                          Positioned(
                            right: 2, top: 2,
                            child: IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Delete custom cover',
                              style: IconButton.styleFrom(backgroundColor: Colors.black45, foregroundColor: Colors.white),
                              onPressed: () => _deleteCover(custom),
                              icon: const Icon(Icons.delete_outline_rounded, size: 18),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (widget.selectionMode)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _selectedKey == null ? null : () => Navigator.pop(context, _selectedKey),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Use selected cover'),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
