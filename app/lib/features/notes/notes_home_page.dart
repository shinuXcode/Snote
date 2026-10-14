import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'package:flutter/material.dart';

import '../../core/settings/app_settings.dart';
import '../../data/local/folder_repository.dart';
import '../../data/local/file_document_repository.dart';
import '../../data/local/note_repository.dart';
import '../../data/local/notebook_transfer_service.dart';
import '../../data/local/shared_media_path_reader.dart';
import '../../sync/sync_engine.dart';
import '../../ui/snote_logo.dart';
import '../auth/login_page.dart';
import '../folders/folder_tree_view.dart';
import '../folders/folder_cover_art.dart';
import '../folders/folder_cover_library_page.dart';
import '../pdf/pdf_annotation_page.dart';
import '../settings/settings_page.dart';
import '../share/qr_import_page.dart';
import '../trash/trash_page.dart';
import '../tools/flashcard_page.dart';
import '../tools/mind_map_page.dart';
import '../tools/screenshot_import_page.dart';
import '../updates/update_center_page.dart';
import '../onboarding/welcome_guide_page.dart';
import 'nextgen_editor_route.dart';
import 'new_note_route.dart';

class NotesHomePage extends StatefulWidget {
  final bool localOnly;
  const NotesHomePage({super.key, this.localOnly = false});

  @override
  State<NotesHomePage> createState() => _NotesHomePageState();
}

class _NotesHomePageState extends State<NotesHomePage> {
  static const int _databasePageSize = 100;

  final _notes = NoteRepository();
  final _folders = FolderRepository();
  final _transfer = NotebookTransferService(NoteRepository());
  final _sync = SyncEngine();
  final _search = TextEditingController();

  List<LocalFolder> _allFolders = const [];
  List<LocalNote> _noteList = const [];
  bool _sidebarCollapsed = false;
  bool _gridView = true;
  String? _folderId;
  final List<LocalFolder> _breadcrumbs = [];
  LocalNote? _selected;
  bool _loading = true;
  bool _syncing = false;
  bool _searchVisible = false;
  Timer? _searchDebounce;
  int _loadGeneration = 0;
  int _homeNoteRenderLimit = 60;
  int _homeFolderRenderLimit = 60;
  int _databaseOffset = 0;
  bool _hasMoreDatabaseNotes = false;
  bool _loadingMoreDatabaseNotes = false;
  bool _welcomeCheckScheduled = false;
  String _folderSort = 'nameAsc';
  bool _folderSelectionMode = false;
  final Set<String> _selectedFolderIds = <String>{};
  List<String> _folderClipboardIds = <String>[];
  String? _folderClipboardMode;
  LocalNote? _noteClipboard;
  String? _noteClipboardMode;
  StreamSubscription<List<SharedMediaFile>>? _sharingSubscription;
  bool _handlingIncomingShare = false;
  String? _lastIncomingSharePath;

  @override
  void initState() {
    super.initState();
    _folderSort = SnoteSettings.instance.getString('folderSort');
    _search.addListener(_onSearchChanged);
    unawaited(_initializeIncomingShareListener());
    unawaited(_load());
    if (!widget.localOnly) unawaited(_startSync());
  }

  Future<void> _initializeIncomingShareListener() async {
    final isMobile = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    if (!isMobile) return;
    try {
      _sharingSubscription =
          ReceiveSharingIntent.instance.getMediaStream().listen(
        (items) => unawaited(_handleIncomingSharedMedia(items)),
        onError: (error) => debugPrint('Snote incoming-share stream error: $error'),
      );
      final initialItems = await ReceiveSharingIntent.instance.getInitialMedia();
      if (initialItems.isNotEmpty) {
        unawaited(_handleIncomingSharedMedia(initialItems));
      }
    } catch (error) {
      debugPrint('Snote could not initialize incoming-share listener: $error');
    }
  }

  bool _isIncomingImage(SharedMediaFile item) {
    if ((item.mimeType ?? '').toLowerCase().startsWith('image/')) return true;
    final path = item.path.toLowerCase().split('?').first;
    return const ['.png', '.jpg', '.jpeg', '.webp', '.heic', '.heif', '.bmp', '.gif'].any(path.endsWith);
  }

  Future<void> _handleIncomingSharedMedia(List<SharedMediaFile> items) async {
    if (!mounted || _handlingIncomingShare || items.isEmpty) return;
    SharedMediaFile? image;
    for (final item in items) {
      if (_isIncomingImage(item)) { image = item; break; }
    }
    if (image == null) {
      try { await ReceiveSharingIntent.instance.reset(); } catch (_) {}
      return;
    }
    final path = image.path.trim();
    if (path.isEmpty || path == _lastIncomingSharePath) {
      try { await ReceiveSharingIntent.instance.reset(); } catch (_) {}
      return;
    }
    _handlingIncomingShare = true;
    _lastIncomingSharePath = path;
    try {
      final bytes = await readSharedMediaBytes(path);
      if (bytes.isEmpty) throw StateError('The shared image is empty.');
      try { await ReceiveSharingIntent.instance.reset(); } catch (_) {}
      if (!mounted) return;
      final filename = path.replaceAll(String.fromCharCode(92), '/').split('/').last;
      final title = filename.replaceFirst(RegExp(r'\.[^.]+$'), '').trim();
      await Navigator.of(context).push<LocalNote>(
        MaterialPageRoute(
          builder: (_) => ScreenshotImportPage(
            folderId: _folderId,
            initialBytes: bytes,
            initialName: title.isEmpty ? 'Shared screenshot' : title,
          ),
        ),
      );
      if (mounted) await _load();
    } catch (error) {
      try { await ReceiveSharingIntent.instance.reset(); } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not import the shared image: ' + error.toString())),
        );
      }
    } finally {
      _handlingIncomingShare = false;
    }
  }
  Future<void> _startSync() async {
    try {
      await _sync.start();
      await _load();
    } catch (error, stackTrace) {
      debugPrint('Snote background sync initialization failed: $error\\n$stackTrace');
      if (!mounted) return;
      setState(() => _syncing = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Sync could not start. Your local notebook remains available.'),
        ),
      );
    }
  }

  void _onSearchChanged() {
    if (!mounted) return;
    _homeNoteRenderLimit = 60;
    _homeFolderRenderLimit = 60;
    setState(() {});
    _searchDebounce?.cancel();

    _searchDebounce = Timer(
      const Duration(milliseconds: 180),
      () => unawaited(_load()),
    );
  }

  void _loadMoreHomeItems() {
    setState(() {
      _homeNoteRenderLimit += 60;
      _homeFolderRenderLimit += 60;
    });
    if (!_loadingMoreDatabaseNotes && _hasMoreDatabaseNotes) {
      unawaited(_loadNextDatabasePage());
    }
  }

  Future<void> _loadNextDatabasePage() async {
    if (_loadingMoreDatabaseNotes || !_hasMoreDatabaseNotes) return;
    final generation = _loadGeneration;
    final query = _search.text.trim();
    final folderId = _folderId;
    setState(() => _loadingMoreDatabaseNotes = true);
    try {
      final batch = query.isNotEmpty
          ? await _notes.searchVisible(
              query,
              limit: _databasePageSize,
              offset: _databaseOffset,
            )
          : await _notes.list(
              folderId: folderId,
              limit: _databasePageSize,
              offset: _databaseOffset,
            );
      if (!mounted || generation != _loadGeneration) return;
      final ids = _noteList.map((note) => note.id).toSet();
      final additions = batch.where((note) => ids.add(note.id)).toList();
      setState(() {
        _noteList = [..._noteList, ...additions];
        _databaseOffset += batch.length;
        _hasMoreDatabaseNotes = batch.length == _databasePageSize;
        _loadingMoreDatabaseNotes = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingMoreDatabaseNotes = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load more notes: $error')),
      );
    }
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final query = _search.text.trim();
    final searching = query.isNotEmpty;

    try {
      final allFolders = await _folders.listAllVisible();
      final notes = searching
          ? await _notes.searchVisible(query, limit: _databasePageSize)
          : await _notes.list(folderId: _folderId, limit: _databasePageSize);
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
        _databaseOffset = notes.length;
        _hasMoreDatabaseNotes = notes.length == _databasePageSize;
        _loadingMoreDatabaseNotes = false;
        _selected = selected;
        _loading = false;
      });
      if (!_welcomeCheckScheduled) {
        _welcomeCheckScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_showWelcomeGuideIfNeeded());
        });
      }
    } catch (error, stackTrace) {
      debugPrint('Snote notebook load failed: $error\\n$stackTrace');
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _loadingMoreDatabaseNotes = false;
      });
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: const Text(
            'Could not load the notebook. Your saved data was not changed.',
          ),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: () => unawaited(_load()),
          ),
        ),
      );
    }
  }

  Future<void> _showWelcomeGuideIfNeeded() async {
    final settings = SnoteSettings.instance;
    if (settings.getBool('welcomeGuideSeen') || !mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const WelcomeGuidePage()),
    );
    await settings.setBool('welcomeGuideSeen', true);
  }

  bool _matchesSearch(LocalNote note) {
    final q = _search.text.trim().toLowerCase();
    return q.isEmpty || note.title.toLowerCase().contains(q);
  }

  List<LocalNote> get _filteredNotes => _noteList.where(_matchesSearch).toList();

  // Large Android tablets must use the same full-screen editor navigation as
  // phones. Embedding a second Scaffold in the split workspace caused the
  // note editor to mount without its normal header/toolbox on some tablets.
  // Keep split view for desktop-class platforms only and use this single
  // decision everywhere so the layout and note-opening behavior cannot drift.
  // The rebuilt editor always owns a dedicated full-screen route.
  bool _usesSplitWorkspace(BuildContext context) => false;

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
    final folderId = _folderId;
    debugPrint(
      '[Snote][Navigation] New Note requested '
      'platform=${defaultTargetPlatform.name} folder=${folderId ?? 'root'}',
    );
    try {
      final created = await _notes.create(folderId: folderId);
      if (created.id.trim().isEmpty) {
        throw StateError('The local note repository returned an empty note ID.');
      }

      // Verify that the exact record being passed to the route exists in the
      // local database. This catches route/state mismatches before mounting
      // an editor that cannot reload its document.
      final note = await _notes.get(created.id);
      if (note == null) {
        throw StateError('The new note was created but could not be read back from local storage.');
      }
      if (!mounted) return;

      debugPrint('[Snote][Navigation] persisted new note id=${note.id}');
      setState(() => _selected = note);
      // Always open New Note in its own full-screen route. In particular,
      // do not mount a just-created note inside the split-workspace editor:
      // this isolates its lifecycle and constraints from the home layout.
      debugPrint('[Snote][Navigation] push dedicated new-note route noteId=${note.id}');
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          settings: RouteSettings(name: '/new-note/${note.id}'),
          builder: (_) => NewNoteRoute(note: note),
        ),
      );
      debugPrint('[Snote][Navigation] dedicated new-note route returned noteId=${note.id}');
      await _load();
    } catch (error, stackTrace) {
      debugPrint('[Snote][Navigation] New Note failed: $error\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open a new note: $error')),
        );
      }
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
    if (!_usesSplitWorkspace(context)) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => _noteContentPage(note)),
      );
      await _load();
    }
  }

  String _noteContentKind(LocalNote note) {
    try {
      final decoded = jsonDecode(note.contentJson ?? '{}');
      if (decoded is Map) {
        final kind = decoded['noteType']?.toString();
        if (kind == 'flashcard' || kind == 'mindmap') return kind!;
      }
    } catch (_) {}
    return note.noteType;
  }

  Widget _noteContentPage(LocalNote note) {
    switch (_noteContentKind(note)) {
      case 'flashcard':
        return FlashcardPage(folderId: note.folderId, note: note);
      case 'mindmap':
        return MindMapPage(folderId: note.folderId, note: note);
      default:
        return SnoteNextEditorRoute(note: note);
    }
  }

  String _noteCoverKey(LocalNote note) {
    try {
      final decoded = jsonDecode(note.contentJson ?? '{}');
      if (decoded is Map) {
        final key = decoded['coverKey']?.toString();
        if (key != null && key.startsWith('cover:')) return key;
      }
    } catch (_) {}
    return 'cover:' + (note.id.hashCode.abs() % 200).toString();
  }

  Future<void> _changeNoteCover(LocalNote note) async {
    final chosen = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => FolderCoverLibraryPage(
          selectionMode: true,
          initialCoverKey: _noteCoverKey(note),
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    final content = <String, Object?>{};
    try {
      final decoded = jsonDecode(note.contentJson ?? '{}');
      if (decoded is Map) content.addAll(decoded.cast<String, Object?>());
    } catch (_) {}
    content['coverKey'] = chosen;
    await _notes.saveContent(note.id, content);
    await _load();
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
    var coverKey = folder.iconKey.startsWith('cover:') ? folder.iconKey : null;
    var iconKey = coverKey == null ? folder.iconKey : 'folder';
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
                const SizedBox(height: 14),
                const Text('Cover artwork', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 112,
                  width: double.infinity,
                  child: FolderCoverArt(coverKey: coverKey ?? 'cover:0', title: folder.name, showTitle: false),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        final chosen = await Navigator.push<String>(
                          dialogContext,
                          MaterialPageRoute(builder: (_) => FolderCoverLibraryPage(
                            selectionMode: true,
                            initialCoverKey: coverKey,
                          )),
                        );
                        if (chosen != null) setDialog(() => coverKey = chosen);
                      },
                      icon: const Icon(Icons.collections_bookmark_outlined, size: 18),
                      label: const Text('Choose cover'),
                    ),
                    if (coverKey != null)
                      TextButton.icon(
                        onPressed: () => setDialog(() => coverKey = null),
                        icon: const Icon(Icons.close_rounded, size: 16),
                        label: const Text('Remove cover'),
                      ),
                  ],
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
                'coverKey': coverKey,
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
      iconKey: result['coverKey'] is String ? result['coverKey']! as String : result['iconKey']! as String,
    );
    await _load();
  }

  Future<void> _openUpdates() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const UpdateCenterPage()));
    await _load();
  }

  Future<void> _openCoverLibrary() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const FolderCoverLibraryPage()));
    await _load();
  }

  void _setFolderSort(String value) {
    setState(() => _folderSort = value);
    unawaited(SnoteSettings.instance.setString('folderSort', value));
  }

  List<String> _topLevelFolderIds(Iterable<String> sourceIds) {
    final chosen = sourceIds.toSet();
    final byId = {for (final item in _allFolders) item.id: item};
    bool hasChosenAncestor(LocalFolder folder) {
      String? parentId = folder.parentId;
      final seen = <String>{};
      while (parentId != null && seen.add(parentId)) {
        if (chosen.contains(parentId)) return true;
        parentId = byId[parentId]?.parentId;
      }
      return false;
    }
    return chosen.where((id) {
      final folder = byId[id];
      return folder != null && !hasChosenAncestor(folder);
    }).toList();
  }

  bool _isInsideFolder(String? folderId, String rootId) {
    if (folderId == null) return false;
    final byId = {for (final item in _allFolders) item.id: item};
    LocalFolder? current = byId[folderId];
    final seen = <String>{};
    while (current != null && seen.add(current.id)) {
      if (current.id == rootId) return true;
      current = current.parentId == null ? null : byId[current.parentId];
    }
    return false;
  }

  void _toggleFolderSelection(LocalFolder folder) {
    setState(() {
      _folderSelectionMode = true;
      if (!_selectedFolderIds.add(folder.id)) _selectedFolderIds.remove(folder.id);
    });
  }

  void _selectAllVisibleFolders() {
    setState(() {
      _folderSelectionMode = true;
      _selectedFolderIds
        ..clear()
        ..addAll(_allFolders.where((f) => f.parentId == _folderId).map((f) => f.id));
    });
  }

  void _invertFolderSelection() {
    final visible = _allFolders.where((f) => f.parentId == _folderId).map((f) => f.id).toSet();
    setState(() {
      _folderSelectionMode = true;
      for (final id in visible) {
        if (!_selectedFolderIds.add(id)) _selectedFolderIds.remove(id);
      }
    });
  }

  void _clearFolderSelection() {
    setState(() {
      _selectedFolderIds.clear();
      _folderSelectionMode = false;
    });
  }

  void _setFolderClipboard(LocalFolder folder, String mode) {
    setState(() {
      _folderClipboardIds = <String>[folder.id];
      _folderClipboardMode = mode;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(mode == 'cut' ? 'Folder ready to move. Open destination and choose Paste.' : 'Folder copied. Open destination and choose Paste.'),
    ));
  }

  void _clipboardSelection(String mode) {
    final ids = _topLevelFolderIds(_selectedFolderIds);
    if (ids.isEmpty) return;
    setState(() {
      _folderClipboardIds = ids;
      _folderClipboardMode = mode;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(mode == 'cut' ? 'Selected folders ready to move. Choose Paste in destination.' : 'Selected folders copied. Choose Paste in destination.'),
    ));
  }

  Future<String?> _chooseFolderDestination(Set<String> excludedRoots) async {
    final byId = {for (final item in _allFolders) item.id: item};
    bool isExcludedDescendant(LocalFolder folder) {
      LocalFolder? current = folder;
      final seen = <String>{};
      while (current != null && seen.add(current.id)) {
        if (excludedRoots.contains(current.id)) return true;
        current = current.parentId == null ? null : byId[current.parentId];
      }
      return false;
    }
    final destinations = _allFolders.where((folder) => !isExcludedDescendant(folder)).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Choose destination'),
        content: SizedBox(
          width: 340,
          height: 360,
          child: ListView(children: [
            ListTile(leading: const Icon(Icons.home_work_outlined), title: const Text('Notebook root'), onTap: () => Navigator.pop(dialog, '')),
            for (final folder in destinations)
              ListTile(
                leading: Icon(folderIconForKey(folder.iconKey), color: Color(folder.colorValue)),
                title: Text(folder.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.pop(dialog, folder.id),
              ),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel'))],
      ),
    );
  }

  Future<void> _moveFolderPrompt(LocalFolder folder) async {
    final destination = await _chooseFolderDestination(<String>{folder.id});
    if (destination == null) return;
    await _moveFolder(folder.id, destination.isEmpty ? null : destination);
  }

  Future<void> _moveSelectedFolders() async {
    final ids = _topLevelFolderIds(_selectedFolderIds);
    if (ids.isEmpty) return;
    final destination = await _chooseFolderDestination(ids.toSet());
    if (destination == null) return;
    try {
      for (final id in ids) {
        await _folders.move(id, parentId: destination.isEmpty ? null : destination);
      }
      _clearFolderSelection();
      await _load();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not move folders: ' + error.toString())));
    }
  }

  Future<void> _pasteFolders() async {
    if (_folderClipboardIds.isEmpty || _folderClipboardMode == null) return;
    final ids = List<String>.from(_folderClipboardIds);
    final mode = _folderClipboardMode!;
    try {
      for (final id in ids) {
        if (mode == 'cut') {
          await _folders.move(id, parentId: _folderId);
        } else {
          await _folders.duplicate(id, parentId: _folderId);
        }
      }
      if (mode == 'cut') {
        setState(() {
          _folderClipboardIds = <String>[];
          _folderClipboardMode = null;
        });
      }
      _clearFolderSelection();
      await _load();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not paste folders: ' + error.toString())));
    }
  }

  Future<void> _deleteSelectedFolders() async {
    final ids = _topLevelFolderIds(_selectedFolderIds);
    if (ids.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Delete selected folders?'),
        content: const Text('Child folders will be deleted too. Notes are returned to notebook root.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    final resetRoot = _folderId != null && ids.any((id) => _isInsideFolder(_folderId, id));
    for (final id in ids) {
      await _folders.delete(id);
    }
    if (resetRoot) {
      setState(() {
        _breadcrumbs.clear();
        _folderId = null;
      });
    }
    _clearFolderSelection();
    await _load();
  }

  Future<void> _showFolderDetails(LocalFolder folder) async {
    final visibleNotes = await _notes.listAllVisible();
    if (!mounted) return;
    final childCount = _allFolders.where((item) => item.parentId == folder.id).length;
    final noteCount = visibleNotes.where((item) => item.folderId == folder.id).length;
    final created = DateTime.fromMillisecondsSinceEpoch(folder.createdAt).toLocal().toString().split('.').first;
    final updated = DateTime.fromMillisecondsSinceEpoch(folder.updatedAt).toLocal().toString().split('.').first;
    await showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(folder.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Direct child folders: ' + childCount.toString()),
            Text('Notes: ' + noteCount.toString()),
            Text('Created: ' + created),
            Text('Updated: ' + updated),
            Text('Cover: ' + (folder.iconKey.startsWith('cover:') ? folder.iconKey : 'Generated cover')),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Close'))],
      ),
    );
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


  void _setNoteClipboard(LocalNote note, String mode) {
    setState(() {
      _noteClipboard = note;
      _noteClipboardMode = mode;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          mode == 'cut'
              ? 'Note cut. Open the destination folder and choose Paste note.'
              : 'Note copied. Open the destination folder and choose Paste note.',
        ),
      ),
    );
  }

  Future<void> _moveNotePrompt(LocalNote note) async {
    final destination = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Move note to folder'),
        content: SizedBox(
          width: 380,
          height: 380,
          child: ListView(
            children: [
              ListTile(
                leading: const Icon(Icons.home_outlined),
                title: const Text('Notebook root'),
                trailing: note.folderId == null ? const Icon(Icons.check_rounded) : null,
                onTap: () => Navigator.pop(dialog, ''),
              ),
              for (final folder in _allFolders)
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(folder.name),
                  subtitle: Text(folder.parentId == null
                      ? 'Root folder'
                      : 'Nested folder'),
                  trailing: note.folderId == folder.id ? const Icon(Icons.check_rounded) : null,
                  onTap: () => Navigator.pop(dialog, folder.id),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
        ],
      ),
    );
    if (destination == null) return;
    try {
      await _notes.moveToFolder(note.id, destination.isEmpty ? null : destination);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Note moved.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not move note: ' + error.toString())),
        );
      }
    }
  }

  Future<void> _pasteNoteClipboard() async {
    final clipboardNote = _noteClipboard;
    final mode = _noteClipboardMode;
    if (clipboardNote == null || mode == null) return;
    try {
      final source = await _notes.get(clipboardNote.id);
      if (source == null) throw StateError('The copied note is no longer available.');
      if (mode == 'cut') {
        await _notes.moveToFolder(source.id, _folderId);
        if (mounted) {
          setState(() {
            _noteClipboard = null;
            _noteClipboardMode = null;
          });
        }
      } else {
        final copy = await _notes.create(
          title: source.title + ' (copy)',
          folderId: _folderId,
        );
        final raw = source.contentJson;
        if (raw != null && raw.isNotEmpty) {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            await _notes.saveContent(copy.id, decoded.cast<String, Object?>());
          }
        }
        final documents = FileDocumentRepository();
        final assets = await documents.listForNote(source.id);
        for (final asset in assets) {
          await documents.duplicate(asset, copy.id);
        }
      }
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mode == 'cut' ? 'Note moved here.' : 'Note copied here.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not paste note: ' + error.toString())),
        );
      }
    }
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
    final wide = _usesSplitWorkspace(context);
    return Scaffold(
      body: SafeArea(child: wide ? _desktop() : _mobile()),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add',
        onPressed: _openPlus,
        child: const Icon(Icons.add_rounded),
      ),
    );
  }


  /// Beta 79's new notebook launch panel. Feature-specific destinations remain
  /// available from the existing action sheet; these are only quick shortcuts.
  Widget _beta79WelcomePanel({bool compact = false}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 520;
        final headline = Text(
          'Give your ideas a page.',
          style: TextStyle(
            color: Colors.white,
            fontSize: compact ? 20 : 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.45,
          ),
        );
        final intro = Text(
          'Write naturally. Mark up PDFs. Keep everything in one notebook.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: .82),
            fontSize: 12.5,
            height: 1.3,
          ),
        );
        final actions = Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF795C),
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 42),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              onPressed: () => unawaited(_createNote()),
              icon: const Icon(Icons.draw_rounded, size: 18),
              label: const Text('New note'),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withValues(alpha: .5)),
                minimumSize: const Size(0, 42),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              onPressed: () => unawaited(_openPdfAnnotation()),
              icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
              label: const Text('Annotate PDF'),
            ),
          ],
        );

        return Container(
          margin: EdgeInsets.fromLTRB(compact ? 16 : 16, 4, 16, compact ? 6 : 12),
          padding: EdgeInsets.all(compact ? 16 : 18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF183D3B), Color(0xFF176B66), Color(0xFF227E70)],
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: const [
              BoxShadow(
                color: Color(0x20176B66),
                blurRadius: 18,
                offset: Offset(0, 7),
              ),
            ],
          ),
          child: narrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'TIDAL INK  •  BETA 79',
                      style: TextStyle(
                        color: Color(0xFF9FE0D1),
                        fontSize: 10,
                        letterSpacing: 1.45,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 7),
                    headline,
                    const SizedBox(height: 5),
                    intro,
                    const SizedBox(height: 13),
                    actions,
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'TIDAL INK  •  BETA 79',
                            style: TextStyle(
                              color: Color(0xFF9FE0D1),
                              fontSize: 10,
                              letterSpacing: 1.45,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 7),
                          headline,
                          const SizedBox(height: 5),
                          intro,
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    actions,
                  ],
                ),
        );
      },
    );
  }

  Future<void> _openPdfAnnotation() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PdfAnnotationPage(folderId: _folderId)),
    );
    if (mounted) await _load();
  }

  Widget _desktop() {
    // The split workspace must never remain visually blank while the note
    // list contains visible notes. Restore a deterministic active note even
    // if selection was cleared by a folder/search refresh or route restoration.
    final visibleNotes = _filteredNotes;
    final activeNote = _selected != null &&
            visibleNotes.any((note) => note.id == _selected!.id)
        ? _selected
        : (visibleNotes.isNotEmpty ? visibleNotes.first : null);

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
          onCovers: _openCoverLibrary,
        ),
        Expanded(
          child: Column(
            children: [
              _TopBar(
                search: _search,
                syncing: _syncing,
                localOnly: widget.localOnly,
                gridView: _gridView,
                searchVisible: _searchVisible,
                onToggleSearch: () => setState(() { _searchVisible = !_searchVisible; if (!_searchVisible) _search.clear(); }),
                onSync: _syncNow,
                onToggleView: () => setState(() => _gridView = !_gridView),
              ),
              _beta79WelcomePanel(compact: true),
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
                        recentNotes: const <LocalNote>[],
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
                        onMoveNote: _moveNotePrompt,
                        onCopyNote: (note) => _setNoteClipboard(note, 'copy'),
                        onCutNote: (note) => _setNoteClipboard(note, 'cut'),
                        onPasteNotes: _pasteNoteClipboard,
                        canPasteNotes: _noteClipboard != null,
                        onChangeNoteCover: _changeNoteCover,
                        folderSort: _folderSort,
                        onFolderSort: _setFolderSort,
                        selectedFolderIds: _selectedFolderIds,
                        folderSelectionMode: _folderSelectionMode,
                        onToggleFolderSelection: _toggleFolderSelection,
                        onSelectAllFolders: _selectAllVisibleFolders,
                        onInvertFolderSelection: _invertFolderSelection,
                        onClearFolderSelection: _clearFolderSelection,
                        onMoveFolderPrompt: _moveFolderPrompt,
                        onFolderDetails: _showFolderDetails,
                        onSetFolderClipboard: _setFolderClipboard,
                        onClipboardSelection: _clipboardSelection,
                        onPasteFolders: _pasteFolders,
                        onMoveSelectedFolders: _moveSelectedFolders,
                        onDeleteSelectedFolders: _deleteSelectedFolders,
                        canPasteFolders: _folderClipboardIds.isNotEmpty,
                        onOpenCoverLibrary: _openCoverLibrary,
                        noteRenderLimit: _homeNoteRenderLimit,
                        folderRenderLimit: _homeFolderRenderLimit,
                        hasMoreDatabaseNotes: _hasMoreDatabaseNotes,
                        loadingMoreDatabaseNotes: _loadingMoreDatabaseNotes,
                        onLoadMore: _loadMoreHomeItems,
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: activeNote == null
                          ? _WorkspaceEmpty(onCreateNote: () => unawaited(_createNote()))
                          : KeyedSubtree(
                              key: ValueKey(activeNote.id),
                              child: _noteContentPage(activeNote),
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
              IconButton(onPressed: () => setState(() { _searchVisible = !_searchVisible; if (!_searchVisible) _search.clear(); }), tooltip: 'Search notes', icon: const Icon(Icons.search_rounded)),
              IconButton(
                onPressed: _openUpdates,
                tooltip: 'Updates and notifications',
                icon: const Icon(Icons.notifications_none_rounded),
              ),
              IconButton(
                onPressed: _openCoverLibrary,
                tooltip: 'Cover library',
                icon: const Icon(Icons.collections_bookmark_outlined),
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
        _beta79WelcomePanel(),
        if (_searchVisible) ...[
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
        ],
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
            recentNotes: const <LocalNote>[],
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
                        onMoveNote: _moveNotePrompt,
                        onCopyNote: (note) => _setNoteClipboard(note, 'copy'),
                        onCutNote: (note) => _setNoteClipboard(note, 'cut'),
                        onPasteNotes: _pasteNoteClipboard,
                        canPasteNotes: _noteClipboard != null,
                        onChangeNoteCover: _changeNoteCover,
                        folderSort: _folderSort,
                        onFolderSort: _setFolderSort,
                        selectedFolderIds: _selectedFolderIds,
                        folderSelectionMode: _folderSelectionMode,
                        onToggleFolderSelection: _toggleFolderSelection,
                        onSelectAllFolders: _selectAllVisibleFolders,
                        onInvertFolderSelection: _invertFolderSelection,
                        onClearFolderSelection: _clearFolderSelection,
                        onMoveFolderPrompt: _moveFolderPrompt,
                        onFolderDetails: _showFolderDetails,
                        onSetFolderClipboard: _setFolderClipboard,
                        onClipboardSelection: _clipboardSelection,
                        onPasteFolders: _pasteFolders,
                        onMoveSelectedFolders: _moveSelectedFolders,
                        onDeleteSelectedFolders: _deleteSelectedFolders,
                        canPasteFolders: _folderClipboardIds.isNotEmpty,
                        onOpenCoverLibrary: _openCoverLibrary,
                        noteRenderLimit: _homeNoteRenderLimit,
                        folderRenderLimit: _homeFolderRenderLimit,
                        hasMoreDatabaseNotes: _hasMoreDatabaseNotes,
                        loadingMoreDatabaseNotes: _loadingMoreDatabaseNotes,
                        onLoadMore: _loadMoreHomeItems,
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
    _sharingSubscription?.cancel();
    unawaited(_sync.dispose());
    super.dispose();
  }
}

class _SideRail extends StatelessWidget {
  final bool localOnly;
  final bool syncing;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onAccount;
  final VoidCallback onSettings;
  final VoidCallback onUpdates;
  final VoidCallback onCovers;

  const _SideRail({
    required this.localOnly,
    required this.syncing,
    required this.expanded,
    required this.onToggle,
    required this.onAccount,
    required this.onSettings,
    required this.onUpdates,
    required this.onCovers,
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
          entry(icon: Icons.collections_bookmark_outlined, label: 'Cover library', onTap: onCovers),
          entry(icon: Icons.person_outline_rounded, label: localOnly ? 'Sign in & sync' : 'Account', onTap: onAccount),
          entry(icon: Icons.settings_outlined, label: 'Settings', onTap: onSettings),
          const Spacer(),
          if (!localOnly)
            if (expanded)
              ListTile(
                leading: Icon(Icons.cloud_done_rounded),
                title: Text(syncing ? 'Syncing…' : 'Sync ready'),
                dense: true,
              )
            else
              Tooltip(
                message: syncing ? 'Syncing' : 'Sync ready',
                child: const Icon(Icons.cloud_done_rounded),
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
  final bool searchVisible;
  final VoidCallback onToggleSearch;
  final VoidCallback onSync;
  final VoidCallback onToggleView;

  const _TopBar({
    required this.search,
    required this.syncing,
    required this.localOnly,
    required this.gridView,
    required this.searchVisible,
    required this.onToggleSearch,
    required this.onSync,
    required this.onToggleView,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Row(
          children: [
            if (searchVisible)
              Expanded(child: TextField(
                controller: search,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search your notebook',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: IconButton(onPressed: onToggleSearch, icon: const Icon(Icons.close_rounded), tooltip: 'Close search'),
                ),
              ))
            else
              IconButton(onPressed: onToggleSearch, tooltip: 'Search notes', icon: const Icon(Icons.search_rounded)),
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
  final ValueChanged<LocalNote> onMoveNote;
  final ValueChanged<LocalNote> onCopyNote;
  final ValueChanged<LocalNote> onCutNote;
  final VoidCallback onPasteNotes;
  final bool canPasteNotes;
  final ValueChanged<LocalNote> onChangeNoteCover;
  final String folderSort;
  final ValueChanged<String> onFolderSort;
  final Set<String> selectedFolderIds;
  final bool folderSelectionMode;
  final ValueChanged<LocalFolder> onToggleFolderSelection;
  final VoidCallback onSelectAllFolders;
  final VoidCallback onInvertFolderSelection;
  final VoidCallback onClearFolderSelection;
  final ValueChanged<LocalFolder> onMoveFolderPrompt;
  final ValueChanged<LocalFolder> onFolderDetails;
  final void Function(LocalFolder folder, String mode) onSetFolderClipboard;
  final ValueChanged<String> onClipboardSelection;
  final VoidCallback onPasteFolders;
  final VoidCallback onMoveSelectedFolders;
  final VoidCallback onDeleteSelectedFolders;
  final bool canPasteFolders;
  final VoidCallback onOpenCoverLibrary;
  final int noteRenderLimit;
  final int folderRenderLimit;
  final bool hasMoreDatabaseNotes;
  final bool loadingMoreDatabaseNotes;
  final VoidCallback onLoadMore;

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
    required this.onMoveNote,
    required this.onCopyNote,
    required this.onCutNote,
    required this.onPasteNotes,
    required this.canPasteNotes,
    required this.onChangeNoteCover,
    required this.folderSort,
    required this.onFolderSort,
    required this.selectedFolderIds,
    required this.folderSelectionMode,
    required this.onToggleFolderSelection,
    required this.onSelectAllFolders,
    required this.onInvertFolderSelection,
    required this.onClearFolderSelection,
    required this.onMoveFolderPrompt,
    required this.onFolderDetails,
    required this.onSetFolderClipboard,
    required this.onClipboardSelection,
    required this.onPasteFolders,
    required this.onMoveSelectedFolders,
    required this.onDeleteSelectedFolders,
    required this.canPasteFolders,
    required this.onOpenCoverLibrary,
    required this.noteRenderLimit,
    required this.folderRenderLimit,
    required this.hasMoreDatabaseNotes,
    required this.loadingMoreDatabaseNotes,
    required this.onLoadMore,
  });

  String _noteContentKind(LocalNote note) {
    try {
      final decoded = jsonDecode(note.contentJson ?? '{}');
      if (decoded is Map) {
        final kind = decoded['noteType']?.toString();
        if (kind == 'flashcard' || kind == 'mindmap') return kind!;
      }
    } catch (_) {}
    return note.noteType;
  }

  String _noteCoverKey(LocalNote note) {
    try {
      final decoded = jsonDecode(note.contentJson ?? '{}');
      if (decoded is Map) {
        final key = decoded['coverKey']?.toString();
        if (key != null && key.startsWith('cover:')) return key;
      }
    } catch (_) {}
    return 'cover:' + (note.id.hashCode.abs() % 200).toString();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    final theme = Theme.of(context);
    final visibleFolders = allFolders.where((folder) => folder.parentId == currentFolderId).toList();
    final renderedFolders = visibleFolders.take(folderRenderLimit).toList();
    final renderedNotes = notes.take(noteRenderLimit).toList();
    switch (folderSort) {
      case 'nameDesc':
        visibleFolders.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
        break;
      case 'newest':
        visibleFolders.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        break;
      case 'oldest':
        visibleFolders.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
      default:
        visibleFolders.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }

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
            PopupMenuButton<String>(
              tooltip: 'Sort folders',
              icon: const Icon(Icons.sort_by_alpha_rounded),
              onSelected: onFolderSort,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'nameAsc', child: Text('Name (A–Z)')),
                PopupMenuItem(value: 'nameDesc', child: Text('Name (Z–A)')),
                PopupMenuItem(value: 'newest', child: Text('Recently changed')),
                PopupMenuItem(value: 'oldest', child: Text('Oldest first')),
              ],
            ),
            PopupMenuButton<String>(
              tooltip: 'Folder selection and clipboard',
              icon: Icon(folderSelectionMode ? Icons.checklist_rounded : Icons.more_vert_rounded),
              onSelected: (action) {
                switch (action) {
                  case 'selectAll': onSelectAllFolders(); break;
                  case 'invert': onInvertFolderSelection(); break;
                  case 'clear': onClearFolderSelection(); break;
                  case 'move': onMoveSelectedFolders(); break;
                  case 'copy': onClipboardSelection('copy'); break;
                  case 'cut': onClipboardSelection('cut'); break;
                  case 'delete': onDeleteSelectedFolders(); break;
                  case 'paste': onPasteFolders(); break;
                  case 'pasteNote': onPasteNotes(); break;
                  case 'covers': onOpenCoverLibrary(); break;
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'selectAll', child: Text('Select all folders')),
                const PopupMenuItem(value: 'invert', child: Text('Invert selection')),
                if (folderSelectionMode) const PopupMenuItem(value: 'clear', child: Text('Clear selection')),
                if (selectedFolderIds.isNotEmpty) ...[
                  const PopupMenuItem(value: 'move', child: Text('Move selected')),
                  const PopupMenuItem(value: 'copy', child: Text('Copy selected')),
                  const PopupMenuItem(value: 'cut', child: Text('Cut selected')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete selected')),
                ],
                if (canPasteFolders) const PopupMenuItem(value: 'paste', child: Text('Paste folders here')),
                if (canPasteNotes) const PopupMenuItem(value: 'pasteNote', child: Text('Paste note here')),
                const PopupMenuItem(value: 'covers', child: Text('Cover library')),
              ],
            ),
          ],
        ),
        const SizedBox(height: 4),
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
        else if (compact) ...[
          if (visibleFolders.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 14, 4, 10),
              child: Text(currentFolderId == null ? 'No folders yet. Use + to make one.' : 'No subfolders here.'),
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: renderedFolders.map((folder) {
                final isSelected = selectedFolderIds.contains(folder.id);
                return SizedBox(
                  width: compact ? 152 : 174,
                  child: _FolderCoverCard(
                    folder: folder,
                    selected: isSelected,
                    selectionMode: folderSelectionMode,
                    onOpen: () => folderSelectionMode ? onToggleFolderSelection(folder) : onOpenTreeFolder(folder),
                    onSelect: () => onToggleFolderSelection(folder),
                    onCustomize: () => onCustomizeFolder(folder),
                    onRename: () => onRenameFolder(folder),
                    onDelete: () => onDeleteFolder(folder),
                    onMove: () => onMoveFolderPrompt(folder),
                    onCopy: () => onSetFolderClipboard(folder, 'copy'),
                    onCut: () => onSetFolderClipboard(folder, 'cut'),
                    onDetails: () => onFolderDetails(folder),
                  ),
                );
              }).toList(),
            )
        ] else
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
        if (gridView)
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: renderedNotes.map((note) {
              final isSelected = selected?.id == note.id;
              final cover = _noteCoverKey(note);
              return SizedBox(
                width: compact ? 155 : 166,
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  color: isSelected
                      ? theme.colorScheme.primaryContainer.withValues(alpha: .65)
                      : theme.colorScheme.surfaceContainerLow,
                  elevation: isSelected ? 4 : 1,
                  child: InkWell(
                    onTap: () => onOpenNote(note),
                    child: SizedBox(
                      height: 190,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: FolderCoverArt(
                                  coverKey: cover,
                                  title: note.title,
                                  showTitle: false,
                                  borderRadius: BorderRadius.zero,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(9, 8, 9, 27),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      note.title.isEmpty ? 'Untitled note' : note.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w800),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      _noteContentKind(note),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.labelSmall,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          Positioned(
                            right: 3,
                            bottom: 2,
                            child: PopupMenuButton<String>(
                              tooltip: 'Note options',
                              padding: EdgeInsets.zero,
                              iconSize: 19,
                              onSelected: (value) {
                                if (value == 'cover') {
                                  onChangeNoteCover(note);
                                } else if (value == 'rename') {
                                  onRenameNote(note);
                                } else if (value == 'delete') {
                                  onDeleteNote(note);
                                } else if (value == 'move') {
                                  onMoveNote(note);
                                } else if (value == 'copy') {
                                  onCopyNote(note);
                                } else if (value == 'cut') {
                                  onCutNote(note);
                                } else if (value == 'paste') {
                                  onPasteNotes();
                                }
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(value: 'cover', child: Text('Change cover')),
                                const PopupMenuItem(value: 'rename', child: Text('Rename')),
                                const PopupMenuItem(value: 'move', child: Text('Move to folder')),
                                const PopupMenuItem(value: 'copy', child: Text('Copy')),
                                const PopupMenuItem(value: 'cut', child: Text('Cut')),
                                if (canPasteNotes)
                                  const PopupMenuItem(value: 'paste', child: Text('Paste note here')),
                                const PopupMenuItem(value: 'delete', child: Text('Move to bin')),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          )
        else
          ...renderedNotes.map(
            (note) => _HomeNoteTile(
              note: note,
              selected: selected?.id == note.id,
              coverKey: _noteCoverKey(note),
              displayKind: _noteContentKind(note),
              onOpen: () => onOpenNote(note),
              onRename: () => onRenameNote(note),
              onDelete: () => onDeleteNote(note),
              onMove: () => onMoveNote(note),
              onCopy: () => onCopyNote(note),
              onCut: () => onCutNote(note),
              onPaste: onPasteNotes,
              canPasteNotes: canPasteNotes,
              onChangeCover: () => onChangeNoteCover(note),
            ),
          ),
        if (notes.length > renderedNotes.length ||
            (compact && visibleFolders.length > renderedFolders.length) ||
            hasMoreDatabaseNotes ||
            loadingMoreDatabaseNotes)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 14, 4, 24),
            child: Center(
              child: OutlinedButton.icon(
                onPressed: loadingMoreDatabaseNotes ? null : onLoadMore,
                icon: loadingMoreDatabaseNotes
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.expand_more_rounded),
                label: Text(
                  loadingMoreDatabaseNotes ? 'Loading more notes…' : 'Load more folders and notes',
                ),
              ),
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _FolderCoverCard extends StatelessWidget {
  final LocalFolder folder;
  final bool selected;
  final bool selectionMode;
  final VoidCallback onOpen;
  final VoidCallback onSelect;
  final VoidCallback onCustomize;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onMove;
  final VoidCallback onCopy;
  final VoidCallback onCut;
  final VoidCallback onDetails;

  const _FolderCoverCard({
    required this.folder, required this.selected, required this.selectionMode,
    required this.onOpen, required this.onSelect, required this.onCustomize,
    required this.onRename, required this.onDelete, required this.onMove,
    required this.onCopy, required this.onCut, required this.onDetails,
  });

  @override
  Widget build(BuildContext context) {
    final coverKey = folder.iconKey.startsWith('cover:')
        ? folder.iconKey
        : 'cover:' + (folder.sortOrder.abs() % 200).toString();
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: selected ? 5 : 2,
      shadowColor: Theme.of(context).colorScheme.shadow.withValues(alpha: .24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .55),
          width: selected ? 2.4 : .7,
        ),
      ),
      child: InkWell(
        onTap: onOpen,
        onLongPress: onSelect,
        child: SizedBox(
          height: 202,
          child: Column(children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FolderCoverArt(coverKey: coverKey, title: folder.name, showTitle: false, showBrandLabel: false),
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: PopupMenuButton<String>(
                      tooltip: 'Folder options',
                      onSelected: (action) {
                        switch (action) {
                          case 'open': onOpen(); break;
                          case 'cover': onCustomize(); break;
                          case 'select': onSelect(); break;
                          case 'move': onMove(); break;
                          case 'copy': onCopy(); break;
                          case 'cut': onCut(); break;
                          case 'details': onDetails(); break;
                          case 'rename': onRename(); break;
                          case 'delete': onDelete(); break;
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'open', child: Text('Open folder')),
                        PopupMenuItem(value: 'cover', child: Text('Change cover / color')),
                        PopupMenuItem(value: 'select', child: Text('Select')),
                        PopupMenuItem(value: 'move', child: Text('Move')),
                        PopupMenuItem(value: 'copy', child: Text('Copy')),
                        PopupMenuItem(value: 'cut', child: Text('Cut')),
                        PopupMenuItem(value: 'details', child: Text('Details')),
                        PopupMenuItem(value: 'rename', child: Text('Rename')),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                      icon: const Icon(Icons.more_vert_rounded, color: Colors.white, shadows: [Shadow(color: Colors.black45, blurRadius: 4)]),
                      style: IconButton.styleFrom(backgroundColor: Colors.black26, foregroundColor: Colors.white),
                    ),
                  ),
                  if (selected || selectionMode)
                    Positioned(
                      left: 4,
                      bottom: 4,
                      child: IconButton.filledTonal(
                        tooltip: selected ? 'Deselect folder' : 'Select folder',
                        onPressed: onSelect,
                        visualDensity: VisualDensity.compact,
                        icon: Icon(selected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded, size: 18),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
              child: Row(children: [
                Icon(Icons.folder_rounded, size: 17, color: Color(folder.colorValue)),
                const SizedBox(width: 6),
                Expanded(child: Text(folder.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _HomeNoteTile extends StatelessWidget {
  final LocalNote note;
  final bool selected;
  final String coverKey;
  final String displayKind;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onMove;
  final VoidCallback onCopy;
  final VoidCallback onCut;
  final VoidCallback onPaste;
  final bool canPasteNotes;
  final VoidCallback onChangeCover;

  const _HomeNoteTile({
    required this.note,
    required this.selected,
    required this.coverKey,
    required this.displayKind,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
    required this.onMove,
    required this.onCopy,
    required this.onCut,
    required this.onPaste,
    required this.canPasteNotes,
    required this.onChangeCover,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      color: selected ? scheme.primaryContainer.withValues(alpha: .65) : scheme.surfaceContainerLow,
      elevation: selected ? 3 : 1,
      child: InkWell(
        onTap: onOpen,
        child: SizedBox(
          height: 104,
          child: Stack(
            children: [
              Positioned.fill(
                child: Row(
                  children: [
                    SizedBox(
                      width: 92,
                      child: FolderCoverArt(
                        coverKey: coverKey,
                        title: note.title,
                        showTitle: false,
                        borderRadius: BorderRadius.zero,
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 42, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              note.title.isEmpty ? 'Untitled note' : note.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 4),
                            Text(displayKind, maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 1,
                bottom: 1,
                child: PopupMenuButton<String>(
                  tooltip: 'Note options',
                  onSelected: (value) {
                    if (value == 'cover') {
                      onChangeCover();
                    } else if (value == 'rename') {
                      onRename();
                    } else if (value == 'delete') {
                      onDelete();
                    } else if (value == 'move') {
                      onMove();
                    } else if (value == 'copy') {
                      onCopy();
                    } else if (value == 'cut') {
                      onCut();
                    } else if (value == 'paste') {
                      onPaste();
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'cover', child: Text('Change cover')),
                    const PopupMenuItem(value: 'rename', child: Text('Rename')),
                    const PopupMenuItem(value: 'move', child: Text('Move to folder')),
                    const PopupMenuItem(value: 'copy', child: Text('Copy')),
                    const PopupMenuItem(value: 'cut', child: Text('Cut')),
                    if (canPasteNotes)
                      const PopupMenuItem(value: 'paste', child: Text('Paste note here')),
                    const PopupMenuItem(value: 'delete', child: Text('Move to bin')),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkspaceEmpty extends StatelessWidget {
  final VoidCallback onCreateNote;

  const _WorkspaceEmpty({required this.onCreateNote});

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.draw_outlined, size: 54, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 16),
                const Text('Open a note to start writing', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                const Text('Choose a note from the list, or create a new one. The workspace will not stay blank.', textAlign: TextAlign.center),
                const SizedBox(height: 18),
                FilledButton.icon(onPressed: onCreateNote, icon: const Icon(Icons.note_add_outlined), label: const Text('Create a note')),
              ],
            ),
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
              _ActionChip(icon: Icons.account_tree_outlined, label: 'Mind map', value: 'mindmap'),
              _ActionChip(icon: Icons.style_outlined, label: 'Flashcards', value: 'flashcard'),
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
