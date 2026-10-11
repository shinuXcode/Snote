import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/settings/app_settings.dart';
import '../../data/local/folder_repository.dart';
import '../../data/local/note_repository.dart';
import '../../data/local/notebook_transfer_service.dart';
import '../../sync/sync_engine.dart';
import '../../ui/snote_logo.dart';
import '../auth/login_page.dart';
import '../folders/folder_tree_view.dart';
import '../pdf/pdf_annotation_page.dart';
import '../settings/settings_page.dart';
import '../share/qr_import_page.dart';
import '../trash/trash_page.dart';
import '../tools/flashcard_page.dart';
import '../tools/mind_map_page.dart';
import '../tools/screenshot_import_page.dart';
import '../updates/update_center_page.dart';
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

  List<LocalFolder> _allFolders = const [];
  List<LocalNote> _noteList = const [];
  List<LocalNote> _recentNotes = const [];
  bool _sidebarCollapsed = false;
  bool _gridView = true;
  String? _folderId;
  final List<LocalFolder> _breadcrumbs = [];
  LocalNote? _selected;
  bool _loading = true;
  bool _syncing = false;
  Timer? _searchDebounce;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchChanged);
    unawaited(_load());
    if (!widget.localOnly) unawaited(_startSync());
  }

  Future<void> _startSync() async {
    await _sync.start();
    await _load();
  }

  void _onSearchChanged() {
    if (!mounted) return;
    setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 180),
      () => unawaited(_load()),
    );
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final searching = _search.text.trim().isNotEmpty;
    final allFolders = await _folders.listAllVisible();
    final notes = searching
        ? await _notes.listAllVisible()
        : await _notes.list(folderId: _folderId);
    final recentNotes = await _notes.listAllVisible(limit: 6);
    if (!mounted || generation != _loadGeneration) return;

    final selectedId = _selected?.id;
    final visible = notes.where(_matchesSearch).toList();
    LocalNote? selected = visible.isEmpty ? null : visible.first;
    if (selectedId != null) {
      for (final note in visible) {
        if (note.id == selectedId) {
          selected = note;
          break;
        }
      }
    }

    setState(() {
      _allFolders = allFolders;
      _noteList = notes;
      _recentNotes = recentNotes;
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
    if (note.folderId != _folderId) {
      final byId = {for (final item in _allFolders) item.id: item};
      final path = <LocalFolder>[];
      final seen = <String>{};
      LocalFolder? current =
          note.folderId == null ? null : byId[note.folderId];
      while (current != null && seen.add(current.id)) {
        path.add(current);
        current = current.parentId == null ? null : byId[current.parentId];
      }
      setState(() {
        _breadcrumbs
          ..clear()
          ..addAll(path.reversed);
        _folderId = note.folderId;
        _selected = note;
      });
      await _load();
    } else {
      setState(() => _selected = note);
    }

    if (!mounted) return;
    if (MediaQuery.sizeOf(context).width < 900) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => NoteEditorPage(note: note)),
      );
      await _load();
    }
  }

  void _openTreeFolder(LocalFolder folder) {
    final byId = {for (final item in _allFolders) item.id: item};
    final path = <LocalFolder>[];
    final seen = <String>{};
    LocalFolder? current = folder;
    while (current != null && seen.add(current.id)) {
      path.add(current);
      current = current.parentId == null ? null : byId[current.parentId];
    }
    setState(() {
      _breadcrumbs
        ..clear()
        ..addAll(path.reversed);
      _folderId = folder.id;
      _selected = null;
    });
    unawaited(_load());
  }

  Future<void> _moveFolder(String folderId, String? parentId) async {
    try {
      await _folders.move(folderId, parentId: parentId);
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not move folder: $error')),
        );
      }
    }
  }

  Future<void> _customizeFolder(LocalFolder folder) async {
    const colors = <int>[
      0xff5b6cf9,
      0xff16a085,
      0xfff39c12,
      0xffe74c3c,
      0xff9b59b6,
      0xff34495e,
      0xffd35400,
      0xff2d9cdb,
    ];
    const icons = <String, String>{
      'folder': 'Folder',
      'book': 'Book',
      'science': 'Science',
      'math': 'Math',
      'star': 'Star',
      'lightbulb': 'Ideas',
      'work': 'Work',
      'archive': 'Archive',
    };
    var colorValue = folder.colorValue;
    var iconKey = folder.iconKey;
    final result = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Folder appearance'),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Color'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: colors.map((value) => InkWell(
                    onTap: () => setDialog(() => colorValue = value),
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(value),
                        border: Border.all(
                          color: colorValue == value
                              ? Theme.of(context).colorScheme.onSurface
                              : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: colorValue == value
                          ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
                          : null,
                    ),
                  )).toList(),
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  initialValue: iconKey,
                  decoration: const InputDecoration(labelText: 'Folder icon'),
                  items: icons.entries.map((entry) => DropdownMenuItem(
                    value: entry.key,
                    child: Row(
                      children: [
                        Icon(folderIconForKey(entry.key), size: 19),
                        const SizedBox(width: 10),
                        Text(entry.value),
                      ],
                    ),
                  )).toList(),
                  onChanged: (value) {
                    if (value != null) setDialog(() => iconKey = value);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, {
                'colorValue': colorValue,
                'iconKey': iconKey,
              }),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    await _folders.updateAppearance(
      folder.id,
      colorValue: result['colorValue']! as int,
      iconKey: result['iconKey']! as String,
    );
    await _load();
  }

  Future<void> _openUpdates() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const UpdateCenterPage()),
    );
    await _load();
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
        colorValue: folder.colorValue,
        iconKey: folder.iconKey,
        sortOrder: folder.sortOrder,
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
    final breadcrumbIndex =
        _breadcrumbs.indexWhere((item) => item.id == folder.id);
    if (breadcrumbIndex >= 0) {
      setState(() {
        _breadcrumbs.removeRange(breadcrumbIndex, _breadcrumbs.length);
        _folderId = _breadcrumbs.isEmpty ? null : _breadcrumbs.last.id;
        _selected = null;
      });
    }
    await _load();
  }

  void _closeEmbeddedOpenNoteTab(LocalNote? next) {
    if (!mounted) return;
    if (next == null) {
      setState(() => _selected = null);
      return;
    }
    unawaited(_openNote(next));
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

  Future<void> _customizeNoteCover(LocalNote note) async {
    final savedCovers = await _loadSavedCoverLibrary();
    final stored = await _notes.get(note.id);
    if (stored == null || !mounted) return;

    var content = <String, dynamic>{};
    if (stored.contentJson != null && stored.contentJson!.isNotEmpty) {
      try {
        final decoded = jsonDecode(stored.contentJson!);
        if (decoded is Map) content = Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }

    final pages = <Map<String, Object?>>[];
    final rawPages = content['pages'];
    if (rawPages is List) {
      for (final raw in rawPages) {
        if (raw is Map) pages.add(Map<String, Object?>.from(raw));
      }
    }
    if (pages.isEmpty) {
      pages.add(<String, Object?>{
        'id': DateTime.now().microsecondsSinceEpoch.toString(),
        'template': 'dotted',
        'paperColor': 0xffffffff,
        'lineColor': 0xffd8dee8,
        'lineOpacity': .85,
        'spacing': 28.0,
        'lineWidth': .7,
        'pageSize': 'A4',
        'cornellAssist': false,
        'orientation': 'vertical',
        'strokes': <Object?>[],
        'images': <Object?>[],
      });
    }

    var coverStyle = ((content['coverStyle'] ?? pages.first['coverStyle']) as num?)?.toInt() ?? 0;
    var coverImage = content['coverImage']?.toString() ?? pages.first['coverImage']?.toString();
    var coverColor = (content['coverColor'] as num?)?.toInt() ?? 0xff5267df;
    var coverIcon = content['coverIcon']?.toString() ?? 'notes';
    final customCoverTitle = TextEditingController(text: content['coverTitle']?.toString() ?? note.title);
    var storeToLibrary = false;
    const icons = <String, String>{
      'notes': 'Notebook',
      'book': 'Book',
      'math': 'Mathematics',
      'science': 'Science',
      'physics': 'Physics',
      'chemistry': 'Chemistry',
      'biology': 'Biology',
      'code': 'Code',
      'lightbulb': 'Ideas',
      'star': 'Favourite',
      'flask': 'Lab',
      'calendar': 'Planner',
    };

    final result = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialog) {
          final styleColors = _coverStyleColors(coverStyle);
          Widget preview() => Container(
            width: 124,
            height: 164,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: styleColors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (coverImage != null && coverImage!.isNotEmpty)
                  Image.memory(
                    base64Decode(coverImage!),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: .05),
                        Colors.black.withValues(alpha: .62),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(_noteCoverIcon(coverIcon), color: Colors.white, size: 28),
                      const SizedBox(height: 7),
                      Text(
                        customCoverTitle.text.trim().isEmpty ? note.title : customCoverTitle.text.trim(),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );

          return AlertDialog(
            title: const Text('Notebook cover library'),
            content: SizedBox(
              width: 620,
              height: 560,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      preview(),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          children: [
                            TextField(
                              controller: customCoverTitle,
                              onChanged: (_) => setDialog(() {}),
                              decoration: const InputDecoration(
                                labelText: 'Cover title',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                            const SizedBox(height: 10),
                            DropdownButtonFormField<String>(
                              initialValue: icons.containsKey(coverIcon) ? coverIcon : 'notes',
                              decoration: const InputDecoration(
                                labelText: 'Cover icon',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: icons.entries.map((entry) => DropdownMenuItem(
                                value: entry.key,
                                child: Row(children: [
                                  Icon(_noteCoverIcon(entry.key), size: 18),
                                  const SizedBox(width: 8),
                                  Text(entry.value),
                                ]),
                              )).toList(),
                              onChanged: (value) {
                                if (value != null) setDialog(() => coverIcon = value);
                              },
                            ),
                            const SizedBox(height: 8),
                            Row(children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    final picked = await ImagePicker().pickImage(
                                      source: ImageSource.gallery,
                                      maxWidth: 1000,
                                      maxHeight: 1500,
                                      imageQuality: 78,
                                    );
                                    if (picked == null) return;
                                    try {
                                      final bytes = await picked.readAsBytes();
                                      if (bytes.isNotEmpty) {
                                        setDialog(() => coverImage = base64Encode(bytes));
                                      }
                                    } catch (_) {}
                                  },
                                  icon: const Icon(Icons.photo_library_outlined),
                                  label: const Text('Custom image'),
                                ),
                              ),
                              if (coverImage != null && coverImage!.isNotEmpty)
                                IconButton(
                                  tooltip: 'Remove custom image',
                                  onPressed: () => setDialog(() => coverImage = null),
                                  icon: const Icon(Icons.close_rounded),
                                ),
                            ]),
                            CheckboxListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              value: storeToLibrary,
                              onChanged: (value) => setDialog(() => storeToLibrary = value ?? false),
                              title: const Text('Keep this custom cover for reuse'),
                            ),
                            const Text(
                              'Choose from 100 generated cover designs below. Covers are saved with the note; the optional reuse library keeps custom covers on this device.',
                              style: TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    const Expanded(child: Text('100 ready-made cover designs', style: TextStyle(fontWeight: FontWeight.w900))),
                    Text('Selected: ${coverStyle + 1}/100'),
                  ]),
                  const SizedBox(height: 8),
                  Expanded(
                    child: GridView.builder(
                      itemCount: 100,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 5,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: .68,
                      ),
                      itemBuilder: (_, index) {
                        final colors = _coverStyleColors(index);
                        final chosen = index == coverStyle;
                        return InkWell(
                          borderRadius: BorderRadius.circular(9),
                          onTap: () => setDialog(() {
                            coverStyle = index;
                            coverImage = null;
                          }),
                          child: Container(
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: colors,
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(
                                color: chosen ? Theme.of(dialogContext).colorScheme.primary : Colors.black12,
                                width: chosen ? 3 : 1,
                              ),
                            ),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (index % 3 == 0)
                                  Positioned(
                                    right: -12,
                                    top: -12,
                                    child: Icon(
                                      _noteCoverIcon(coverIcon),
                                      size: 78,
                                      color: Colors.white.withValues(alpha: .16),
                                    ),
                                  ),
                                Align(
                                  alignment: Alignment.bottomLeft,
                                  child: Padding(
                                    padding: const EdgeInsets.all(6),
                                    child: Text(
                                      'Cover ${index + 1}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w900,
                                        shadows: [Shadow(color: Colors.black54, blurRadius: 3)],
                                      ),
                                    ),
                                  ),
                                ),
                                if (chosen)
                                  const Positioned(
                                    right: 4,
                                    top: 4,
                                    child: Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
              FilledButton.icon(
                onPressed: () => Navigator.pop(dialogContext, <String, Object?>{
                  'coverStyle': coverStyle,
                  'coverImage': coverImage,
                  'coverColor': coverColor,
                  'coverIcon': coverIcon,
                  'coverTitle': customCoverTitle.text.trim().isEmpty ? note.title : customCoverTitle.text.trim(),
                  'storeToLibrary': storeToLibrary,
                }),
                icon: const Icon(Icons.check_rounded),
                label: const Text('Save cover'),
              ),
            ],
          );
        },
      ),
    );
    customCoverTitle.dispose();
    if (result == null) return;

    final style = result['coverStyle'] as int;
    content['coverStyle'] = style;
    content['coverImage'] = result['coverImage'];
    content['coverColor'] = result['coverColor'];
    content['coverIcon'] = result['coverIcon'];
    content['coverTitle'] = result['coverTitle'];
    content['version'] = content['version'] ?? 5;
    pages.first['coverStyle'] = style;
    pages.first['coverImage'] = result['coverImage'];
    pages.first['coverColor'] = result['coverColor'];
    pages.first['coverIcon'] = result['coverIcon'];
    content['pages'] = pages;

    if (result['storeToLibrary'] == true) {
      final library = await _loadSavedCoverLibrary();
      final image = result['coverImage']?.toString();
      final signature = image == null || image.isEmpty ? 'style:$style' : 'image:${image.hashCode}';
      library.removeWhere((item) => item['signature'] == signature);
      library.insert(0, <String, Object?>{
        'signature': signature,
        'style': style,
        'image': image,
        'icon': result['coverIcon'],
        'title': result['coverTitle'],
      });
      await _settingsPlaceholderSaveCoverLibrary(library);
    }

    content['text_delta'] ??= <Object?>[
      <String, Object?>{'insert': '\n'},
    ];
    await _notes.saveContent(stored.id, Map<String, Object?>.from(content));
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
          await Navigator.push(context, MaterialPageRoute(builder: (_) => PdfAnnotationPage(folderId: _folderId)));
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
        _SideRail(
          localOnly: widget.localOnly,
          syncing: _syncing,
          expanded: !_sidebarCollapsed,
          onToggle: () => setState(() => _sidebarCollapsed = !_sidebarCollapsed),
          onAccount: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const LoginPage()),
          ),
          onSettings: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SettingsPage()),
          ),
          onUpdates: _openUpdates,
        ),
        Expanded(
          child: Column(
            children: [
              _TopBar(
                search: _search,
                syncing: _syncing,
                localOnly: widget.localOnly,
                gridView: _gridView,
                onSync: _syncNow,
                onToggleView: () => setState(() => _gridView = !_gridView),
              ),
              _Breadcrumbs(
                items: _breadcrumbs,
                onBack: _goBackFolder,
                onRoot: () {
                  setState(() {
                    _breadcrumbs.clear();
                    _folderId = null;
                    _selected = null;
                  });
                  unawaited(_load());
                },
              ),
              Expanded(
                child: Row(
                  children: [
                    SizedBox(
                      width: 380,
                      child: _HierarchyPanel(
                        allFolders: _allFolders,
                        recentNotes: _search.text.trim().isEmpty
                            ? _recentNotes
                            : const <LocalNote>[],
                        isSearching: _search.text.trim().isNotEmpty,
                        currentFolderId: _folderId,
                        notes: _filteredNotes,
                        selected: _selected,
                        loading: _loading,
                        gridView: _gridView,
                        onToggleView: () => setState(() => _gridView = !_gridView),
                        onOpenTreeFolder: _openTreeFolder,
                        onMoveFolder: _moveFolder,
                        onCustomizeFolder: _customizeFolder,
                        onNewFolder: _createFolder,
                        onNewNote: _createNote,
                        onRenameFolder: _renameFolder,
                        onDeleteFolder: _deleteFolder,
                        onOpenNote: _openNote,
                        onRenameNote: _renameNote,
                        onDeleteNote: _deleteNote,
                        onCustomizeNote: _customizeNoteCover,
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: _selected == null
                          ? const _WorkspaceEmpty()
                          : KeyedSubtree(
                              key: ValueKey(_selected!.id),
                              child: NoteEditorPage(
                                note: _selected!,
                                embedded: true,
                                onSwitchTab: (note) => unawaited(_openNote(note)),
                                onCloseTab: _closeEmbeddedOpenNoteTab,
                              ),
                            ),
                    ),
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
              IconButton(
                onPressed: _openUpdates,
                tooltip: 'Updates and notifications',
                icon: const Icon(Icons.notifications_none_rounded),
              ),
              IconButton(
                onPressed: _syncNow,
                tooltip: widget.localOnly ? 'Account' : 'Sync',
                icon: Icon(widget.localOnly ? Icons.cloud_outlined : Icons.sync_rounded),
              ),
              IconButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsPage()),
                ),
                tooltip: 'Settings',
                icon: const Icon(Icons.tune_rounded),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
          child: TextField(
            controller: _search,
            decoration: InputDecoration(
              hintText: 'Search notes',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: _search.clear,
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
        ),
        _Breadcrumbs(
          items: _breadcrumbs,
          onBack: _goBackFolder,
          onRoot: () {
            setState(() {
              _breadcrumbs.clear();
              _folderId = null;
              _selected = null;
            });
            unawaited(_load());
          },
        ),
        Expanded(
          child: _HierarchyPanel(
            compact: true,
            allFolders: _allFolders,
            recentNotes: _search.text.trim().isEmpty
                ? _recentNotes
                : const <LocalNote>[],
            isSearching: _search.text.trim().isNotEmpty,
            currentFolderId: _folderId,
            notes: _filteredNotes,
            selected: _selected,
            loading: _loading,
            gridView: _gridView,
            onToggleView: () => setState(() => _gridView = !_gridView),
            onOpenTreeFolder: _openTreeFolder,
            onMoveFolder: _moveFolder,
            onCustomizeFolder: _customizeFolder,
            onNewFolder: _createFolder,
            onNewNote: _createNote,
            onRenameFolder: _renameFolder,
            onDeleteFolder: _deleteFolder,
            onOpenNote: _openNote,
            onRenameNote: _renameNote,
            onDeleteNote: _deleteNote,
            onCustomizeNote: _customizeNoteCover,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.removeListener(_onSearchChanged);
    _search.dispose();
    unawaited(_sync.dispose());
    super.dispose();
  }
}

List<Color> _coverStyleColors(int index) {
  final normalized = index.clamp(0, 99);
  final hue = (normalized * 47.0) % 360;
  final depth = (normalized % 5) * .06;
  return [
    HSVColor.fromAHSV(1, hue, .54 + (normalized % 4) * .10, .96 - depth).toColor(),
    HSVColor.fromAHSV(1, (hue + 38 + (normalized % 3) * 17) % 360, .72, .48 + (normalized % 4) * .08).toColor(),
  ];
}

Future<List<Map<String, Object?>>> _loadSavedCoverLibrary() async {
  try {
    final decoded = jsonDecode(SnoteSettings.instance.getString('coverLibrary'));
    if (decoded is List) {
      return decoded.whereType<Map>().map((item) => Map<String, Object?>.from(item)).toList();
    }
  } catch (_) {}
  return <Map<String, Object?>>[];
}

Future<void> _settingsPlaceholderSaveCoverLibrary(List<Map<String, Object?>> library) async {
  await SnoteSettings.instance.setString('coverLibrary', jsonEncode(library.take(50).toList()));
}

IconData _noteCoverIcon(String key) {
  switch (key) {
    case 'book': return Icons.menu_book_rounded;
    case 'math': return Icons.functions_rounded;
    case 'science': return Icons.science_rounded;
    case 'physics': return Icons.bolt_rounded;
    case 'chemistry': return Icons.biotech_rounded;
    case 'biology': return Icons.spa_rounded;
    case 'code': return Icons.code_rounded;
    case 'lightbulb': return Icons.lightbulb_rounded;
    case 'star': return Icons.star_rounded;
    case 'flask': return Icons.science_outlined;
    case 'calendar': return Icons.calendar_month_rounded;
    default: return Icons.auto_stories_rounded;
  }
}

Widget _noteCoverPreview(LocalNote note, {double size = 44}) {
  var colorValue = 0xff5267df;
  var iconKey = 'notes';
  final raw = note.contentJson;
  if (raw != null && raw.isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      final pages = decoded is Map ? decoded['pages'] : null;
      if (decoded is Map) {
        colorValue = (decoded['coverColor'] as num?)?.toInt() ?? colorValue;
        iconKey = decoded['coverIcon']?.toString() ?? iconKey;
      }
      if (pages is List && pages.isNotEmpty && pages.first is Map) {
        final cover = pages.first as Map;
        colorValue = (cover['coverColor'] as num?)?.toInt() ?? colorValue;
        iconKey = cover['coverIcon']?.toString() ?? iconKey;
      }
    } catch (_) {}
  }
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: Color(colorValue),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Icon(_noteCoverIcon(iconKey), color: Colors.white, size: size * .56),
  );
}

class _SideRail extends StatelessWidget {
  final bool localOnly;
  final bool syncing;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onAccount;
  final VoidCallback onSettings;
  final VoidCallback onUpdates;

  const _SideRail({
    required this.localOnly,
    required this.syncing,
    required this.expanded,
    required this.onToggle,
    required this.onAccount,
    required this.onSettings,
    required this.onUpdates,
  });

  @override
  Widget build(BuildContext context) {
    final width = expanded ? 220.0 : 76.0;
    Widget entry({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
      bool selected = false,
    }) {
      return Tooltip(
        message: expanded ? '' : label,
        child: ListTile(
          leading: Icon(icon),
          title: expanded ? Text(label) : null,
          selected: selected,
          onTap: onTap,
          dense: !expanded,
          contentPadding: EdgeInsets.symmetric(horizontal: expanded ? 12 : 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: width,
      padding: EdgeInsets.fromLTRB(expanded ? 14 : 8, 18, expanded ? 14 : 8, 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          right: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .4),
          ),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: expanded ? MainAxisAlignment.spaceBetween : MainAxisAlignment.center,
            children: [
              if (expanded) const SnoteLogo(size: 38),
              IconButton(
                onPressed: onToggle,
                tooltip: expanded ? 'Collapse sidebar' : 'Expand sidebar',
                icon: Icon(expanded ? Icons.chevron_left_rounded : Icons.chevron_right_rounded),
              ),
            ],
          ),
          const SizedBox(height: 20),
          entry(icon: Icons.auto_stories_rounded, label: 'Notebook', selected: true, onTap: () {}),
          entry(icon: Icons.notifications_none_rounded, label: 'Updates & notices', onTap: onUpdates),
          entry(icon: Icons.person_outline_rounded, label: localOnly ? 'Sign in & sync' : 'Account', onTap: onAccount),
          entry(icon: Icons.settings_outlined, label: 'Settings', onTap: onSettings),
          const Spacer(),
          if (expanded)
            ListTile(
              leading: Icon(localOnly ? Icons.offline_bolt_rounded : Icons.cloud_done_rounded),
              title: Text(localOnly ? 'Offline first' : syncing ? 'Syncing…' : 'Sync ready'),
              dense: true,
            )
          else
            Tooltip(
              message: localOnly ? 'Offline first' : syncing ? 'Syncing' : 'Sync ready',
              child: Icon(localOnly ? Icons.offline_bolt_rounded : Icons.cloud_done_rounded),
            ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final TextEditingController search;
  final bool syncing;
  final bool localOnly;
  final bool gridView;
  final VoidCallback onSync;
  final VoidCallback onToggleView;

  const _TopBar({
    required this.search,
    required this.syncing,
    required this.localOnly,
    required this.gridView,
    required this.onSync,
    required this.onToggleView,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: search,
                decoration: const InputDecoration(
                  hintText: 'Search your notebook',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: onToggleView,
              tooltip: gridView ? 'Switch to list view' : 'Switch to grid view',
              icon: Icon(gridView ? Icons.view_list_rounded : Icons.grid_view_rounded),
            ),
            const SizedBox(width: 4),
            FilledButton.tonalIcon(
              onPressed: onSync,
              icon: syncing
                  ? const SizedBox.square(
                      dimension: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(localOnly ? Icons.cloud_outlined : Icons.sync_rounded),
              label: Text(localOnly ? 'Offline' : 'Sync'),
            ),
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
  final List<LocalFolder> allFolders;
  final List<LocalNote> recentNotes;
  final bool isSearching;
  final String? currentFolderId;
  final List<LocalNote> notes;
  final LocalNote? selected;
  final bool loading;
  final bool compact;
  final bool gridView;
  final VoidCallback onToggleView;
  final VoidCallback onNewFolder;
  final VoidCallback onNewNote;
  final ValueChanged<LocalFolder> onOpenTreeFolder;
  final Future<void> Function(String folderId, String? parentId) onMoveFolder;
  final ValueChanged<LocalFolder> onCustomizeFolder;
  final ValueChanged<LocalFolder> onRenameFolder;
  final ValueChanged<LocalFolder> onDeleteFolder;
  final ValueChanged<LocalNote> onOpenNote;
  final ValueChanged<LocalNote> onRenameNote;
  final ValueChanged<LocalNote> onDeleteNote;
  final ValueChanged<LocalNote> onCustomizeNote;

  const _HierarchyPanel({
    required this.allFolders,
    required this.recentNotes,
    required this.isSearching,
    required this.currentFolderId,
    required this.notes,
    required this.selected,
    required this.loading,
    this.compact = false,
    required this.gridView,
    required this.onToggleView,
    required this.onOpenTreeFolder,
    required this.onMoveFolder,
    required this.onCustomizeFolder,
    required this.onNewFolder,
    required this.onNewNote,
    required this.onRenameFolder,
    required this.onDeleteFolder,
    required this.onOpenNote,
    required this.onRenameNote,
    required this.onDeleteNote,
    required this.onCustomizeNote,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    final theme = Theme.of(context);

    return ListView(
      padding: EdgeInsets.fromLTRB(compact ? 12 : 14, 4, compact ? 12 : 14, 110),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Folders & notes',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
            ),
            IconButton(
              onPressed: onToggleView,
              tooltip: gridView ? 'List view' : 'Grid view',
              icon: Icon(gridView ? Icons.view_list_rounded : Icons.grid_view_rounded),
            ),
            IconButton(
              onPressed: onNewFolder,
              tooltip: 'New folder',
              icon: const Icon(Icons.create_new_folder_outlined),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (currentFolderId == null && recentNotes.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
            child: Text(
              'Quick recents',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          SizedBox(
            height: 78,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: recentNotes.take(6).length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final note = recentNotes[index];
                return SizedBox(
                  width: compact ? 156 : 174,
                  child: Card(
                    margin: EdgeInsets.zero,
                    color: theme.colorScheme.surfaceContainerLow,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => onOpenNote(note),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          children: [
                            Icon(
                              Icons.history_rounded,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    note.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    note.noteType,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelSmall,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
        if (allFolders.isEmpty && notes.isEmpty && recentNotes.isEmpty && !isSearching)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24, horizontal: 18),
            child: Column(
              children: [
                Icon(Icons.folder_open_rounded, size: 42),
                SizedBox(height: 10),
                Text('Nothing here yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                SizedBox(height: 6),
                Text(
                  'Create a folder or note to start organizing your notebook.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
        else
          FolderTreeView(
            folders: allFolders,
            selectedFolderId: currentFolderId,
            onSelect: onOpenTreeFolder,
            onMove: onMoveFolder,
            onRename: onRenameFolder,
            onDelete: onDeleteFolder,
            onAppearance: onCustomizeFolder,
          ),
        if (isSearching && notes.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 18, 4, 8),
            child: Text('No notes match your search.'),
          ),
        if (notes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
            child: Text(
              isSearching
                  ? 'Search results'
                  : currentFolderId == null
                      ? 'Notes in this folder'
                      : 'Notes in this folder',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
          ),
        if (gridView)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: notes.map((note) {
              final isSelected = selected?.id == note.id;
              return SizedBox(
                width: compact ? 155 : 166,
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  color: isSelected
                      ? theme.colorScheme.primaryContainer.withValues(alpha: .65)
                      : theme.colorScheme.surfaceContainerLow,
                  child: InkWell(
                    onTap: () => onOpenNote(note),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: SizedBox(
                        height: 96,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _noteCoverPreview(note, size: 46),
                            const Spacer(),
                            Text(
                              note.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    note.noteType,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelSmall,
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  padding: EdgeInsets.zero,
                                  iconSize: 18,
                                  onSelected: (value) {
                                    if (value == 'rename') {
                                      onRenameNote(note);
                                    } else if (value == 'cover') {
                                      onCustomizeNote(note);
                                    } else if (value == 'delete') {
                                      onDeleteNote(note);
                                    }
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(value: 'cover', child: Text('Customize cover')),
                                    PopupMenuItem(value: 'rename', child: Text('Rename')),
                                    PopupMenuItem(value: 'delete', child: Text('Move to trash')),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          )
        else
          ...notes.map(
            (note) => _HomeNoteTile(
              note: note,
              selected: selected?.id == note.id,
              onOpen: () => onOpenNote(note),
              onRename: () => onRenameNote(note),
              onDelete: () => onDeleteNote(note),
              onCover: () => onCustomizeNote(note),
            ),
          ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: onNewNote,
          icon: const Icon(Icons.note_add_outlined),
          label: const Text('New note here'),
        ),
      ],
    );
  }
}

class _HomeNoteTile extends StatelessWidget {
  final LocalNote note;
  final bool selected;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onCover;

  const _HomeNoteTile({
    required this.note,
    required this.selected,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
    required this.onCover,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: selected
          ? scheme.primaryContainer.withValues(alpha: .65)
          : scheme.surfaceContainerLow,
      child: ListTile(
        leading: _noteCoverPreview(note, size: 44),
        title: Text(
          note.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(note.noteType),
        onTap: onOpen,
        trailing: PopupMenuButton<String>(
          tooltip: 'Note actions',
          onSelected: (value) {
            if (value == 'cover') {
              onCover();
            } else if (value == 'rename') {
              onRename();
            } else if (value == 'delete') {
              onDelete();
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'cover', child: Text('Customize cover')),
            PopupMenuItem(value: 'rename', child: Text('Rename')),
            PopupMenuItem(value: 'delete', child: Text('Move to trash')),
          ],
        ),
      ),
    );
  }
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
