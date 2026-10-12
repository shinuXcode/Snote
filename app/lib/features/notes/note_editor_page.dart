import 'dart:math' as math;
import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart' as pdfcore;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfx/pdfx.dart';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/theme_controller.dart';
import '../../canvas_engine/models/pen_config.dart';
import '../../canvas_engine/widgets/page_background.dart';
import '../../canvas_engine/widgets/notebook_viewport.dart';
import '../../canvas_engine/widgets/snote_canvas.dart';
import '../../canvas_engine/widgets/snote_canvas_controller.dart';
import '../../core/security/note_lock_service.dart';
import '../../core/settings/app_settings.dart';
import '../../data/local/note_repository.dart';
import '../settings/settings_page.dart';
import '../folders/folder_cover_library_page.dart';

// Open-note tabs are shared by editor routes during the current app session.
final ValueNotifier<List<LocalNote>> _snoteOpenNoteTabs = ValueNotifier<List<LocalNote>>(<LocalNote>[]);

class NoteEditorPage extends StatefulWidget {
  final LocalNote note;
  final bool embedded;
  final ValueChanged<LocalNote>? onSwitchTab;
  final ValueChanged<LocalNote?>? onCloseTab;

  const NoteEditorPage({
    super.key,
    required this.note,
    this.embedded = false,
    this.onSwitchTab,
    this.onCloseTab,
  });

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage> with WidgetsBindingObserver {
  final _repo = NoteRepository();
  final _canvas = SnoteCanvasController();
  final _quill = QuillController.basic();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final _title = TextEditingController();
  final _lock = const NoteLockService();
  final _settings = SnoteSettings.instance;
  final GlobalKey _pageCaptureKey = GlobalKey();
  final GlobalKey _toolbarKey = GlobalKey();
  final GlobalKey _editorStackKey = GlobalKey();
  final GlobalKey _canvasRenderKey = GlobalKey();
  final GlobalKey _showcaseKey = GlobalKey();
  final Map<String, double> _toolSizeOverrides = <String, double>{};
  final Map<String, Color> _toolColorOverrides = <String, Color>{};
  final Map<String, bool> _toolDashedOverrides = <String, bool>{};
  double _pageChangerX = -1;
  double _pageChangerY = 130;
  double _selectionToolbarX = -1;
  double _selectionToolbarY = -1;
  Offset? _toolOptionsAnchorPosition;
  bool _pdfExporting = false;
  final TextEditingController _calculatorInput = TextEditingController(text: '0');
  String _calculatorResult = '0';

  List<Map<String, Object?>> _pages = [];
  int _page = 0;
  bool _loading = true;
  bool _locked = false;
  bool _unlocked = true;
  bool _draw = true;
  bool _pan = false;
  bool _full = false;
  bool _preview = false;
  bool _tabsVisible = true;
  bool _readingMode = false;
  bool _eyedropperActive = false;
  bool _toolbar = true;
  bool _docked = true;
  String _dockSide = 'left';
  Axis _floatingAxis = Axis.vertical;
  // Keep the free toolbox outside the fixed left rail by default.
  double _toolbarX = 16;
  double _toolbarY = 0;
  final ValueNotifier<Offset> _toolbarOffset = ValueNotifier(const Offset(16, 0));
  CanvasTool _tool = CanvasTool.ballpoint;
  Color _penColor = const Color(0xff263238);
  double _penSize = 3;
  double _opacity = 1;
  double _pressureSensitivity = .55;
  double _velocitySensitivity = .65;
  bool _fill = false;
  bool _dashed = false;
  Color? _fillColor;
  int _sides = 6;
  bool _shapePanel = false;
  bool _showcaseOpen = false;
  String _showcaseDock = 'right';
  double _showcaseX = 12;
  double _showcaseY = 140;
  String? _sticker;
  int _selected = 0;
  Timer? _saveTimer;
  bool _savePending = false;
  bool _saveInFlight = false;
  int? _noteCoverColor;
  String? _noteCoverIcon;
  String? _noteCoverKey;
  StateSetter? _templateSheetRefresh;

  Map<String, Object?> get pageData => _pages[_page];
  PenConfig get pen {
    final curve = PressureCurve.values.firstWhere(
      (value) => value.name == _settings.getString('pressureCurve'),
      orElse: () => PressureCurve.linear,
    );
    return PenConfig(
      type: _tool.penType,
      color: _toolColorOverrides[_tool.name] ?? _penColor,
      size: _toolSizeOverrides[_tool.name] ?? _penSize,
      opacity: _tool == CanvasTool.highlighter
          ? _opacity.clamp(.08, .55)
          : _opacity,
      pressureSensitivity: _pressureSensitivity,
      velocitySensitivity: _velocitySensitivity,
      pressureCurve: curve,
      customPressureExponent: _settings.getDouble('pressureExponent'),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _title.text = widget.note.title;
    _registerCurrentOpenTab();
    _snoteOpenNoteTabs.addListener(_onOpenTabsChanged);
    try {
      final sizes = jsonDecode(_settings.getString('toolSizes'));
      if (sizes is Map) {
        for (final entry in sizes.entries) {
          if (entry.value is num) _toolSizeOverrides[entry.key.toString()] = (entry.value as num).toDouble();
        }
      }
      final colors = jsonDecode(_settings.getString('toolColors'));
      if (colors is Map) {
        for (final entry in colors.entries) {
          if (entry.value is num) _toolColorOverrides[entry.key.toString()] = Color((entry.value as num).toInt());
        }
      }
      final dashed = jsonDecode(_settings.getString('toolDashed'));
      if (dashed is Map) {
        for (final entry in dashed.entries) {
          if (entry.value is bool) _toolDashedOverrides[entry.key.toString()] = entry.value as bool;
        }
      }
    } catch (_) {}
    _quill.addListener(_scheduleSave);
    _prepare();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      unawaited(_flushSave());
    }
  }

  LocalNote _currentTabRecord() {
    final title = _title.text.trim();
    return LocalNote(
      id: widget.note.id,
      title: title.isEmpty ? 'Untitled note' : title,
      folderId: widget.note.folderId,
      noteType: widget.note.noteType,
      contentJson: widget.note.contentJson,
      createdAt: widget.note.createdAt,
      updatedAt: widget.note.updatedAt,
      deletedAt: widget.note.deletedAt,
      version: widget.note.version,
    );
  }

  void _registerCurrentOpenTab() {
    final tabs = List<LocalNote>.from(_snoteOpenNoteTabs.value);
    final note = _currentTabRecord();
    final index = tabs.indexWhere((tab) => tab.id == note.id);
    if (index < 0) {
      tabs.add(note);
    } else {
      tabs[index] = note;
    }
    _snoteOpenNoteTabs.value = tabs;
  }

  void _refreshCurrentOpenTab() {
    final tabs = List<LocalNote>.from(_snoteOpenNoteTabs.value);
    final note = _currentTabRecord();
    final index = tabs.indexWhere((tab) => tab.id == note.id);
    if (index < 0) {
      tabs.add(note);
    } else {
      tabs[index] = note;
    }
    _snoteOpenNoteTabs.value = tabs;
    _scheduleSave();
  }

  void _onOpenTabsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _switchOpenNoteTab(LocalNote note) async {
    if (note.id == widget.note.id) return;
    await _flushSave();
    if (!mounted) return;
    final fresh = await _repo.get(note.id);
    if (!mounted) return;
    if (fresh == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That note is no longer available.')),
      );
      _snoteOpenNoteTabs.value = _snoteOpenNoteTabs.value
          .where((tab) => tab.id != note.id)
          .toList();
      return;
    }
    if (widget.embedded && widget.onSwitchTab != null) {
      widget.onSwitchTab!(fresh);
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => NoteEditorPage(note: fresh)),
    );
  }

  Future<void> _closeOpenNoteTab(LocalNote note) async {
    final remaining = _snoteOpenNoteTabs.value
        .where((tab) => tab.id != note.id)
        .toList(growable: false);
    if (note.id != widget.note.id) {
      _snoteOpenNoteTabs.value = remaining;
      return;
    }

    await _flushSave();
    if (!mounted) return;
    _snoteOpenNoteTabs.value = remaining;
    if (remaining.isEmpty) {
      if (widget.embedded && widget.onCloseTab != null) {
        widget.onCloseTab!(null);
      } else {
        Navigator.maybePop(context);
      }
      return;
    }
    final next = await _repo.get(remaining.last.id);
    if (!mounted) return;
    if (widget.embedded && widget.onCloseTab != null) {
      widget.onCloseTab!(next);
    } else if (next != null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => NoteEditorPage(note: next)),
      );
    } else {
      Navigator.maybePop(context);
    }
  }

  Widget _openNotesTabsBar() => Positioned(
        left: 8,
        right: 8,
        top: 46,
        height: 34,
        child: Material(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: .92),
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final tab in _snoteOpenNoteTabs.value)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: tab.id == widget.note.id
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: tab.id == widget.note.id
                              ? Theme.of(context).colorScheme.primary
                              : Colors.transparent,
                        ),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        InkWell(
                          onTap: () => unawaited(_switchOpenNoteTab(tab)),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(10, 5, 6, 5),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 160),
                              child: Text(
                                tab.id == widget.note.id
                                    ? (_title.text.trim().isEmpty
                                        ? 'Untitled note'
                                        : _title.text.trim())
                                    : tab.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: tab.id == widget.note.id
                                      ? FontWeight.w900
                                      : FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                          constraints: const BoxConstraints.tightFor(width: 25, height: 26),
                          padding: EdgeInsets.zero,
                          tooltip: 'Close tab',
                          onPressed: () => unawaited(_closeOpenNoteTab(tab)),
                          icon: const Icon(Icons.close_rounded, size: 14),
                        ),
                      ]),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );

  Future<void> _prepare() async {
    final locked = await _lock.isLocked(widget.note.id);
    if (!mounted) return;
    setState(() {
      _locked = locked;
      _unlocked = !locked;
      _loading = locked;
    });
    if (!locked) await _load();
  }

  Future<void> _load() async {
    final note = await _repo.get(widget.note.id);
    final parsed = <Map<String, Object?>>[];
    int? storedCoverColor;
    String? storedCoverIcon;
    String? storedCoverKey;
    if (note?.contentJson != null) {
      try {
        final json = jsonDecode(note!.contentJson!);
        if (json is Map<String, dynamic>) {
          storedCoverColor = (json['coverColor'] as num?)?.toInt();
          storedCoverIcon = json['coverIcon']?.toString();
          storedCoverKey = json['coverKey']?.toString();
          final raw = json['pages'];
          if (raw is List) {
            for (final item in raw) {
              if (item is Map) {
                final page = _normalize(item.cast<String, Object?>());
                storedCoverColor ??= (page['coverColor'] as num?)?.toInt();
                storedCoverIcon ??= page['coverIcon']?.toString();
                parsed.add(page);
              }
            }
          }
          final delta = json['text_delta'];
          if (delta is List) {
            try { _quill.document = Document.fromJson(delta); } catch (_) {}
          }
        }
      } catch (_) {}
    }
    if (parsed.isEmpty) parsed.add(_newPage());
    if (!mounted) return;
    setState(() {
      _pages = parsed;
      _page = 0;
      _noteCoverColor = storedCoverColor;
      _noteCoverIcon = storedCoverIcon;
      _noteCoverKey = storedCoverKey;
      _loading = false;
    });
    _restoreToolbar();
    await _keepAwake();
  }

  Map<String, Object?> _normalize(Map<String, Object?> source) {
    final p = Map<String, Object?>.from(source);
    p['id'] ??= DateTime.now().microsecondsSinceEpoch.toString();
    p['template'] ??= PageTemplate.dotted.name;
    p['paperColor'] ??= 0xffffffff;
    p['lineColor'] ??= 0xffd8dee8;
    p['lineOpacity'] ??= .85;
    p['spacing'] ??= 28.0;
    p['lineWidth'] ??= .7;
    p['pageSize'] ??= 'A4';
    p['cornellAssist'] ??= false;
    p['orientation'] ??= 'vertical';
    p['strokes'] ??= <Object?>[];
    p['images'] ??= <Object?>[];
    return p;
  }

  Map<String, Object?> _newPage() {
    // Continue with the current paper when adding a page. On initial load,
    // respect the configured default instead of forcing every new page to dots.
    final inheritedTemplate = _pages.isNotEmpty
        ? (pageData['template']?.toString() ?? _settings.getString('defaultPageTemplate'))
        : _settings.getString('defaultPageTemplate');
    final knownTemplate = PageTemplate.values.any((template) => template.name == inheritedTemplate)
        ? inheritedTemplate
        : PageTemplate.dotted.name;
    final inheritedColor = _pages.isNotEmpty ? _pageColor().toARGB32() : 0xffffffff;
    final inheritedLineColor = _pages.isNotEmpty
        ? (pageData['lineColor'] is num ? (pageData['lineColor'] as num).toInt() : 0xffd8dee8)
        : 0xffd8dee8;
    final inheritedOpacity = _pages.isNotEmpty ? _pageDouble('lineOpacity', .85) : .85;
    final inheritedSpacing = _pages.isNotEmpty ? _pageDouble('spacing', 28) : 28.0;
    final inheritedCornell = _pages.isNotEmpty && pageData['cornellAssist'] == true;
    final inheritedOrientation = _pages.isNotEmpty ? (pageData['orientation']?.toString() ?? 'vertical') : 'vertical';
    return {
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'template': knownTemplate,
      'paperColor': inheritedColor,
      'lineColor': inheritedLineColor,
      'lineOpacity': inheritedOpacity,
      'spacing': inheritedSpacing,
      'lineWidth': _pages.isNotEmpty ? _pageDouble('lineWidth', .7) : .7,
      'pageSize': _pages.isNotEmpty ? (pageData['pageSize']?.toString() ?? 'A4') : 'A4',
      'cornellAssist': inheritedCornell,
      'orientation': inheritedOrientation,
      'strokes': <Object?>[],
      'images': <Object?>[],
    };
  }

  void _restoreToolbar() {
    _showcaseDock = _settings.getString('toolShowcaseDockSide');
    _showcaseX = _settings.getDouble('toolShowcaseX') == 0 ? 12 : _settings.getDouble('toolShowcaseX');
    _showcaseY = _settings.getDouble('toolShowcaseY') == 0 ? 140 : _settings.getDouble('toolShowcaseY');
    if (!const {'left', 'right', 'top', 'bottom', 'free'}.contains(_showcaseDock)) _showcaseDock = 'right';
    final x = pageData['toolbarX'];
    final y = pageData['toolbarY'];
    const dockSides = {'left', 'right', 'top', 'bottom', 'free'};
    final savedDock = _settings.getString('toolbarDock');
    final pageDock = pageData['toolbarDock']?.toString();
    // Prefer the latest dock choice across notes: an older note snapshot can
    // otherwise restore "free" after the user already re-attached the toolbox.
    final dock = dockSides.contains(savedDock)
        ? savedDock
        : (dockSides.contains(pageDock) ? pageDock! : 'left');
    _docked = const {'left', 'right', 'top', 'bottom'}.contains(dock);
    final savedAxis = pageData['toolbarAxis']?.toString();
    _floatingAxis = savedAxis == 'horizontal'
        ? Axis.horizontal
        : savedAxis == 'vertical'
            ? Axis.vertical
            : (_dockSide == 'left' || _dockSide == 'right')
                ? Axis.vertical
                : Axis.horizontal;
    if (_docked) {
      _dockSide = dock!;
      if (x is num) _toolbarX = x.toDouble();
      if (y is num) _toolbarY = y.toDouble();
    } else {
      // Older saved positions defaulted to 16px and overlapped the fixed rail.
      _toolbarX = math.max(8, x is num ? x.toDouble() : 16.0);
      _toolbarY = y is num ? y.toDouble() : 0;
    }
    _toolbarOffset.value = Offset(_toolbarX, _toolbarY);
  }

  void _scheduleSave() {
    if (_loading || (_locked && !_unlocked)) return;
    _savePending = true;
    _saveTimer?.cancel();
    if (!_settings.getBool('autoSave')) return;
    _saveTimer = Timer(const Duration(milliseconds: 700), () {
      unawaited(_save());
    });
  }

  Future<void> _save({bool force = false}) async {
    if (_loading || _pages.isEmpty || (_locked && !_unlocked)) return;
    _saveTimer?.cancel();
    _saveTimer = null;
    if (_saveInFlight) {
      _savePending = true;
      return;
    }
    if (!force && !_savePending) return;
    _savePending = false;
    _saveInFlight = true;
    try {
      await _repo.saveContent(widget.note.id, {
        'version': 5,
        'coverColor': _noteCoverColor,
        'coverIcon': _noteCoverIcon,
        'coverKey': _noteCoverKey,
        'pages': _pages,
        'text_delta': _quill.document.toDelta().toJson(),
      });
      final title = _title.text.trim();
      if (title.isNotEmpty && title != widget.note.title) {
        await _repo.rename(widget.note.id, title);
      }
    } finally {
      _saveInFlight = false;
      if (_savePending && mounted) {
        _saveTimer = Timer(const Duration(milliseconds: 700), () {
          unawaited(_save());
        });
      }
    }
  }

  Future<void> _flushSave() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (_savePending || _saveInFlight) {
      if (!_saveInFlight) {
        await _save(force: true);
      }
      while (_saveInFlight) {
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
      if (_savePending && mounted) await _save(force: true);
    }
  }

  Future<void> _keepAwake() async {
    await WakelockPlus.toggle(enable: _settings.getBool('keepScreenOn'));
  }

  void _changed(Map<String, Object?> value) {
    // Canvas changes do not affect the editor chrome. Avoid rebuilding the
    // entire page on every completed stroke; only persist the latest snapshot.
    _pages[_page] = Map<String, Object?>.from(pageData)..addAll(value);
    _scheduleSave();
  }

  double _defaultToolSize(CanvasTool tool) {
    if (tool == CanvasTool.eraser || tool == CanvasTool.pixelEraser) return 12;
    if (tool == CanvasTool.highlighter) return 8;
    if (tool == CanvasTool.marker || tool == CanvasTool.brush) return 5;
    if (tool == CanvasTool.pencil) return 1.7;
    if (tool.isShape) return 2.2;
    return 3;
  }

  Color _defaultToolColor(CanvasTool tool) {
    if (tool == CanvasTool.highlighter) return const Color(0xffffd54f);
    if (tool == CanvasTool.marker) return const Color(0xff1565c0);
    return const Color(0xff263238);
  }

  void _selectTool(CanvasTool tool) {
    setState(() {
      _tool = tool;
      _penSize = _toolSizeOverrides[tool.name] ?? _defaultToolSize(tool);
      _penColor = _toolColorOverrides[tool.name] ?? _defaultToolColor(tool);
      _dashed = _toolDashedOverrides[tool.name] ?? false;
      _pan = false;
      _shapePanel = false;
      if (tool != CanvasTool.sticker) _sticker = null;
    });
  }

  void _addPage() {
    setState(() {
      _pages.add(_newPage());
      if (_settings.getBool('jumpToNewPage')) _page = _pages.length - 1;
    });
    _scheduleSave();
  }

  void _previousPage() {
    if (_page > 0) _selectPage(_page - 1);
  }

  void _nextPage() {
    if (_page + 1 < _pages.length) {
      _selectPage(_page + 1);
    } else if (_settings.getBool('autoAddPage')) {
      _addPage();
    }
  }

  void _selectPage(int value) {
    if (value < 0 || value >= _pages.length) return;
    unawaited(_save(force: true));
    setState(() {
      _page = value;
      _selected = 0;
    });
    _restoreToolbar();
  }

  void _pageSwipe(DragEndDetails d) {
    if (!_settings.getBool('pageSwipe')) return;
    final speed = d.primaryVelocity ?? 0;
    if (speed < -350) _nextPage();
    if (speed > 350) _previousPage();
  }

  Future<void> _chooseNoteCover() async {
    final chosen = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => FolderCoverLibraryPage(
          selectionMode: true,
          initialCoverKey: _noteCoverKey ?? 'cover:0',
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    setState(() => _noteCoverKey = chosen);
    await _save(force: true);
  }

  Future<void> _lockNote() async {
    if (_locked) {
      final password = await _passwordDialog('Unlock note');
      if (password == null) return;
      final ok = await _lock.unlock(widget.note.id, password);
      if (!mounted) return;
      if (ok) {
        setState(() { _locked = false; _unlocked = true; });
        await _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Wrong password.')));
      }
      return;
    }

    final hasPassword = await _lock.hasPassword(widget.note.id);
    if (!hasPassword) {
      final password = await _setPasswordDialog();
      if (password == null) return;
      await _lock.setPassword(widget.note.id, password);
    } else {
      await _lock.lock(widget.note.id);
    }
    if (mounted) setState(() => _locked = true);
  }

  Future<String?> _passwordDialog(String title) async {
    final input = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(controller: input, autofocus: true, obscureText: true, decoration: const InputDecoration(labelText: 'Note password')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, input.text), child: const Text('Continue')),
        ],
      ),
    );
    input.dispose();
    return result;
  }

  Future<String?> _setPasswordDialog() async {
    final one = TextEditingController();
    final two = TextEditingController();
    var error = '';
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialog) => AlertDialog(
          title: const Text('Set note password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Custom note password. It is not the device screen lock.'),
              TextField(controller: one, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
              TextField(controller: two, obscureText: true, decoration: const InputDecoration(labelText: 'Confirm')),
              if (error.isNotEmpty) Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (one.text.length < 4) {
                  setDialog(() => error = 'Use at least 4 characters.');
                } else if (one.text != two.text) {
                  setDialog(() => error = 'Passwords do not match.');
                } else {
                  Navigator.pop(dialogContext, one.text);
                }
              },
              child: const Text('Lock note'),
            ),
          ],
        ),
      ),
    );
    one.dispose();
    two.dispose();
    return result;
  }

  void _toggleFullscreen() {
    setState(() => _full = !_full);
    SystemChrome.setEnabledSystemUIMode(_full ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _snoteOpenNoteTabs.removeListener(_onOpenTabsChanged);
    _saveTimer?.cancel();
    _quill.removeListener(_scheduleSave);
    _quill.dispose();
    _title.dispose();
    _calculatorInput.dispose();
    _focus.dispose();
    _scroll.dispose();
    _canvas.dispose();
    _toolbarOffset.dispose();
    unawaited(WakelockPlus.disable());
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return _lockedView();

    return PopScope(
      canPop: !_settings.getBool('disableBackGesture'),
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) {
          await _flushSave();
          if (mounted) Navigator.maybePop(context);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xffe9edf2),
        body: SafeArea(
          child: Stack(
            key: _editorStackKey,
            children: [
              Positioned.fill(
                top: _full ? 0 : 34,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  supportedDevices: const {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.trackpad,
                  },
                  onHorizontalDragEnd: (_pan || _selected > 0) ? null : _pageSwipe,
                  onDoubleTap: () => setState(() => _toolbar = !_toolbar),
                  onLongPress: _settings.getBool('fingerLongPressSelection')
                      ? () => _selectTool(CanvasTool.lasso)
                      : null,
                  child: _pageView(),
                ),
              ),
              if (!_full) _header(),
              if (!_full && _tabsVisible) _openNotesTabsBar(),
              if (!_full && !_readingMode) _movablePageChanger(),
              if (_preview && !_full && !_readingMode) _previewRail(),
              if (_toolbar && _draw && !_readingMode) _toolbarWidget(),
              if (_shapePanel && !_full && !_readingMode) _shapePanelWidget(),
              if (_showcaseOpen && !_full && !_readingMode) _showcaseWidget(),
              if (!_toolbar && !_full && !_readingMode) _toolbarOpen(),
              if (_full) _fullExit(),
              if (_selected > 0 && !_readingMode) _selectionTools(),
              if (_eyedropperActive)
                Positioned(
                  left: 0,
                  right: 0,
                  top: _full ? 0 : 80,
                  bottom: 0,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (details) => unawaited(_samplePageColor(details.globalPosition)),
                    child: Container(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: .035),
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Chip(
                          avatar: const Icon(Icons.colorize_rounded),
                          label: const Text('Tap anywhere on this page to sample its colour'),
                          onDeleted: () => setState(() => _eyedropperActive = false),
                          deleteIcon: const Icon(Icons.close_rounded),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _lockedView() {
    if (!_locked) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: Text(widget.note.title)),
      body: Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.lock_rounded, size: 56),
              const SizedBox(height: 16),
              const Text('Note locked', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () async {
                  final password = await _passwordDialog('Unlock note');
                  if (password == null) return;
                  final ok = await _lock.unlock(widget.note.id, password);
                  if (!mounted) return;
                  if (ok) {
                    setState(() { _locked = false; _unlocked = true; });
                    await _load();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Wrong password.')));
                  }
                },
                icon: const Icon(Icons.key_rounded),
                label: const Text('Unlock'),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _pageView() {
    final sizeKey = pageData['pageSize']?.toString() ?? 'A4';
    final horizontal = pageData['orientation']?.toString() == 'horizontal';
    final baseAspectRatio = switch (sizeKey) {
      'A3' => 297 / 420,
      'A5' => 148 / 210,
      'Letter' => 215.9 / 279.4,
      'Legal' => 215.9 / 355.6,
      'Infinite' => 1.0,
      _ => 210 / 297,
    };
    final aspectRatio = horizontal ? 1 / baseAspectRatio : baseAspectRatio;
    final infiniteCanvas = sizeKey == 'Infinite';

    final pageSurface = Material(
      elevation: SnoteThemeController.instance.eInk ? 0 : 10,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(3),
        side: BorderSide(color: Colors.black.withValues(alpha: .09), width: .8),
      ),
      clipBehavior: Clip.antiAlias,
      color: _pageColor(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: CustomPaint(
              painter: PageBackground(
                template: _template(),
                paperColor: _pageColor(),
                lineColor: _pageColor('lineColor', const Color(0xffd8dee8)),
                spacing: _pageDouble('spacing', 28),
                lineOpacity: _pageDouble('lineOpacity', .85),
                lineWidth: _pageDouble('lineWidth', .7),
                cornellAssist: pageData['cornellAssist'] == true,
              ),
            ),
          ),
          if (pageData['backgroundImage'] is String &&
              (pageData['backgroundImage'] as String).isNotEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: Image.memory(
                  base64Decode(pageData['backgroundImage']! as String),
                  fit: BoxFit.fill,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
          if (_draw)
            IgnorePointer(
              ignoring: _readingMode,
              child: RepaintBoundary(
                key: _canvasRenderKey,
                child: SnoteCanvas(
                  key: ValueKey(widget.note.id + '-' + _page.toString()),
                  pen: pen,
                  tool: _tool,
                  controller: _canvas,
                  initialDocument: pageData,
                  backgroundColor: Colors.transparent,
                  shapeFill: _fill,
                  customShapeSides: _sides,
                  stickerText: _sticker,
                  onChanged: _changed,
                  onSelectionChanged: (count) {
                    if (mounted && count != _selected) {
                      setState(() => _selected = count);
                    }
                  },
                  onSelectionBoundsChanged: _positionSelectionTools,
                  autoRecognition: _settings.getBool('autoRecognition'),
                  onEraserMiss: _settings.getBool('eraseClickSwitch') &&
                          _tool == CanvasTool.eraser
                      ? () => _selectTool(CanvasTool.ballpoint)
                      : null,
                  onStylusDoubleTap:
                      _settings.getBool('stylusDoubleTapUndo')
                          ? _canvas.undo
                          : null,
                  pressureErase: _settings.getBool('pressureErase'),
                  pressureEraseArea: _settings.getBool('pressureEraseArea'),
                  pressureEraseThreshold:
                      _settings.getDouble('pressureEraseThreshold'),
                  eraseWithStylusButton: true,
                  eraseMark: true,
                  eraserMode: _settings.getString('eraserMode'),
                  stylusHoldActions: _settings.getBool('stylusHoldActions'),
                  dashed: _dashed ||
                      (_toolDashedOverrides[_tool.name] ?? false) ||
                      (_tool == CanvasTool.lasso &&
                          _settings.getString('lassoStyle') == 'dashed'),
                  fillColor: _fillColor,
                  fillOpacity: _opacity,
                  smoothing: _settings.getDouble('strokeSmoothing'),
                  showPerformanceOverlay:
                      const bool.fromEnvironment('SNOTE_PERF'),
                  palmRejection: _settings.getBool('palmRejection'),
                ),
              ),
            )
          else
            IgnorePointer(
              ignoring: _readingMode,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: QuillEditor(
                  focusNode: _focus,
                  scrollController: _scroll,
                  controller: _quill,
                  config: const QuillEditorConfig(
                    placeholder: 'Start writing…',
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: IgnorePointer(
              ignoring: _readingMode,
              child: LayoutBuilder(
                builder: (_, constraints) => Stack(
                  clipBehavior: Clip.none,
                  children: _pageImages
                      .map((image) => _pageImageItem(
                            image,
                            constraints.maxWidth,
                            constraints.maxHeight,
                          ))
                      .toList(),
                ),
              ),
            ),
          ),
          if (_settings.getBool('showPageNumbers'))
            Positioned(
              right: 10,
              bottom: 8,
              child: Text(
                (_page + 1).toString(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
    );

    final Widget child;
    if (infiniteCanvas) {
      child = Center(
        child: SizedBox(
          width: 2400,
          height: 2400,
          child: pageSurface,
        ),
      );
    } else {
      child = Center(
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: pageSurface,
        ),
      );
    }

    return RepaintBoundary(
      key: _pageCaptureKey,
      child: NotebookViewport(
        allowSingleFingerPan: _pan || _readingMode,
        minScale: .5,
        maxScale: 4,
        initialScale: _settings.getDouble('noteZoom'),
        child: Padding(
          padding: EdgeInsets.only(
            left: 8,
            right: 8,
            top: _full ? 0 : 46,
            bottom: _full ? 0 : 12,
          ),
          child: child,
        ),
      ),
    );
  }

  List<Map<String, Object?>> get _pageImages {
    final raw = pageData['images'];
    if (raw is! List) return <Map<String, Object?>>[];
    return raw.whereType<Map>().map((item) => item.cast<String, Object?>()).toList();
  }

  Widget _pageImageItem(Map<String, Object?> image, double pageWidth, double pageHeight) {
    final id = image['id']?.toString() ?? '';
    final x = (image['x'] as num?)?.toDouble() ?? .12;
    final y = (image['y'] as num?)?.toDouble() ?? .16;
    final width = (image['width'] as num?)?.toDouble() ?? .68;
    final height = (image['height'] as num?)?.toDouble() ?? .42;
    final data = image['data']?.toString() ?? '';
    if (data.isEmpty) return const SizedBox.shrink();
    final bytes = base64Decode(data);
    return Positioned(
      left: (x * pageWidth).clamp(0.0, math.max(0.0, pageWidth - 56)).toDouble(),
      top: (y * pageHeight).clamp(0.0, math.max(0.0, pageHeight - 56)).toDouble(),
      width: (width * pageWidth).clamp(56.0, math.max(56.0, pageWidth)).toDouble(),
      height: (height * pageHeight).clamp(56.0, math.max(56.0, pageHeight)).toDouble(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) {
          setState(() {
            image['x'] = (x + details.delta.dx / math.max(1.0, pageWidth)).clamp(0.0, .85);
            image['y'] = (y + details.delta.dy / math.max(1.0, pageHeight)).clamp(0.0, .85);
          });
          _scheduleSave();
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).colorScheme.primary, width: 1.2),
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Image.memory(
                bytes,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_outlined)),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: Material(
                color: Theme.of(context).colorScheme.surface.withValues(alpha: .92),
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: 'Remove inserted image',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                  padding: EdgeInsets.zero,
                  iconSize: 16,
                  onPressed: () {
                    setState(() => _pageImages.removeWhere((candidate) => candidate['id'] == id));
                    _scheduleSave();
                  },
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _insertScreenshot() async {
    final source = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose a screenshot or image'),
            onTap: () => Navigator.pop(sheetContext, 'gallery'),
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined),
            title: const Text('Capture with camera'),
            onTap: () => Navigator.pop(sheetContext, 'camera'),
          ),
          ListTile(
            leading: const Icon(Icons.mobile_screen_share_rounded),
            title: const Text('Share a screenshot from another app'),
            subtitle: const Text('Use Android screenshot preview → Share → Snote Beta'),
            onTap: () => Navigator.pop(sheetContext, 'share-help'),
          ),
        ]),
      ),
    );
    if (source == null) return;
    if (source == 'share-help') {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Add screenshots without opening Gallery'),
          content: const Text(
            'Open the other app and take a screenshot. In Android’s screenshot preview, tap Share and choose Snote Beta. Snote will ask which note to add the image to, then open that note. This uses Android’s share permission and does not capture other apps in the background.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Got it'),
            ),
          ],
        ),
      );
      return;
    }
    try {
      final picked = await ImagePicker().pickImage(
        source: source == 'camera' ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 90,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (bytes.isEmpty || !mounted) return;
      setState(() {
        _pageImages.add({
          'id': DateTime.now().microsecondsSinceEpoch.toString(),
          'name': picked.name,
          'data': base64Encode(bytes),
          'x': .12,
          'y': .16,
          'width': .68,
          'height': .42,
        });
        pageData['images'] = _pageImages;
      });
      _scheduleSave();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not insert image: $error')),
        );
      }
    }
  }

  Future<void> _importPdfIntoNote() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
      if (file == null) return;
      final sourceBytes = await file.readAsBytes();
      if (sourceBytes.isEmpty) throw StateError('The selected PDF is empty.');
      final document = await PdfDocument.openData(sourceBytes);
      final totalPages = document.pagesCount;
      final importCount = math.min(totalPages, 40);
      final imported = <Map<String, Object?>>[];
      try {
        for (var index = 1; index <= importCount; index++) {
          final pdfPage = await document.getPage(index);
          try {
            const maxDimension = 1500.0;
            final scale = math.min(
              maxDimension / pdfPage.width,
              maxDimension / pdfPage.height,
            );
            final rendered = await pdfPage.render(
              width: (pdfPage.width * scale).roundToDouble(),
              height: (pdfPage.height * scale).roundToDouble(),
              format: PdfPageImageFormat.png,
              backgroundColor: '#ffffff',
            );
            if (rendered == null || rendered.bytes.isEmpty) {
              throw StateError('Could not render PDF page $index.');
            }
            imported.add({
              'id': '${DateTime.now().microsecondsSinceEpoch}-$index',
              'template': PageTemplate.blank.name,
              'paperColor': 0xffffffff,
              'lineColor': 0xffd8dee8,
              'lineOpacity': .85,
              'spacing': 28.0,
              'lineWidth': .7,
              'pageSize': 'A4',
              'cornellAssist': false,
              'orientation': pdfPage.width > pdfPage.height ? 'horizontal' : 'vertical',
              'backgroundImage': base64Encode(rendered.bytes),
              'pdfSourceName': file.name,
              'pdfSourcePage': index,
              'strokes': <Object?>[],
              'images': <Object?>[],
            });
          } finally {
            await pdfPage.close();
          }
        }
      } finally {
        await document.close();
      }
      if (!mounted || imported.isEmpty) return;
      setState(() {
        final insertionIndex = (_page + 1).clamp(0, _pages.length);
        _pages.insertAll(insertionIndex, imported);
        _page = insertionIndex;
        _normalize(pageData);
      });
      _scheduleSave();
      if (mounted) {
        final message = totalPages > importCount
            ? 'Imported $importCount of $totalPages PDF pages. Split large PDFs into smaller files to keep this note responsive.'
            : 'Imported $totalPages PDF pages into this note.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF import failed: $error')),
        );
      }
    }
  }

  Future<void> _exportPagePdf() async {
    if (_pdfExporting) return;
    setState(() => _pdfExporting = true);
    try {
      await _flushSave();
      await WidgetsBinding.instance.endOfFrame;
      final renderObject = _pageCaptureKey.currentContext?.findRenderObject();
      if (renderObject is! RenderRepaintBoundary) {
        throw StateError('The page is not ready for PDF export.');
      }
      final image = await renderObject.toImage(pixelRatio: 2);
      final pngData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (pngData == null) throw StateError('Could not render this page.');
      final pdf = pw.Document();
      pdf.addPage(pw.Page(
        pageFormat: pdfcore.PdfPageFormat.a4,
        build: (_) => pw.Center(
          child: pw.Image(pw.MemoryImage(pngData.buffer.asUint8List()), fit: pw.BoxFit.contain),
        ),
      ));
      final safeTitle = _title.text.trim().replaceAll(RegExp(r'[^a-zA-Z0-9 _-]'), '').replaceAll(' ', '_');
      final bytes = await pdf.save();
      final saved = await FilePicker.saveFile(
        dialogTitle: 'Save current note page as PDF',
        fileName: '${safeTitle.isEmpty ? 'Snote' : safeTitle}-page-${_page + 1}.pdf',
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        bytes: bytes,
      );
      if (mounted && saved != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF export saved: $saved')));
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF export failed: $error')));
    } finally {
      if (mounted) setState(() => _pdfExporting = false);
    }
  }

  Future<void> _studyTimerSheet() async {
    await showDialog<void>(
      context: context,
      builder: (_) => const _StudyTimerDialog(),
    );
  }

  Future<void> _calculatorSheet() async {
    const keys = [
      'sin', 'cos', 'tan', 'sqrt',
      '(', ')', 'AC', 'DEL',
      '7', '8', '9', '÷',
      '4', '5', '6', '×',
      '1', '2', '3', '−',
      '0', '.', 'π', '+',
      '%', '^', 'Ans', '=',
    ];
    _calculatorInput.text = _calculatorInput.text.isEmpty ? '0' : _calculatorInput.text;
    _calculatorResult = '0';
    var keypadScale = 1.0;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (_, setModal) => SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 780),
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(children: [
                        const Icon(Icons.calculate_rounded, size: 25),
                        const SizedBox(width: 10),
                        const Expanded(child: Text('Calculator', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900))),
                        IconButton(
                          tooltip: 'Close calculator',
                          onPressed: () => Navigator.pop(sheetContext),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ]),
                      TextField(
                        controller: _calculatorInput,
                        textAlign: TextAlign.end,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                        decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Expression'),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text('= $_calculatorResult', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                        ),
                      ),
                      Row(children: [
                        const Text('Key size', style: TextStyle(fontWeight: FontWeight.w700)),
                        Expanded(
                          child: Slider(
                            value: keypadScale,
                            min: .75,
                            max: 1.35,
                            divisions: 12,
                            label: keypadScale.toStringAsFixed(2) + '×',
                            onChanged: (value) => setModal(() => keypadScale = value),
                          ),
                        ),
                      ]),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final columns = constraints.maxWidth >= 600 ? 7 : 4;
                          return GridView.count(
                            crossAxisCount: columns,
                            shrinkWrap: true,
                            mainAxisSpacing: 7,
                            crossAxisSpacing: 7,
                            childAspectRatio: (columns >= 7 ? 1.45 : 1.7) / keypadScale,
                            physics: const NeverScrollableScrollPhysics(),
                            children: keys.map((key) => FilledButton(
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
                                backgroundColor: key == '='
                                    ? Theme.of(context).colorScheme.primary
                                    : const Color(0xffe7eaf0),
                                foregroundColor: key == '='
                                    ? Theme.of(context).colorScheme.onPrimary
                                    : const Color(0xff17191d),
                              ),
                              onPressed: () {
                                setModal(() {
                                  final current = _calculatorInput.text;
                                  if (key == 'AC') {
                                    _calculatorInput.text = '0';
                                    _calculatorResult = '0';
                                  } else if (key == 'DEL') {
                                    _calculatorInput.text = current.length <= 1 ? '0' : current.substring(0, current.length - 1);
                                  } else if (key == 'Ans') {
                                    _calculatorInput.text = _calculatorResult;
                                  } else if (key == '=') {
                                    try {
                                      final value = _CalculatorParser(_calculatorInput.text).parse();
                                      if (!value.isFinite) {
                                        _calculatorResult = 'Undefined';
                                      } else {
                                        final formatted = value.toStringAsPrecision(10);
                                        _calculatorResult = formatted.contains('.')
                                            ? formatted.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
                                            : formatted;
                                      }
                                    } catch (_) {
                                      _calculatorResult = 'Error';
                                    }
                                  } else {
                                    final token = key == '×' ? '*' : key == '÷' ? '/' : key == '−' ? '-' : key == 'π' ? 'pi' : key;
                                    _calculatorInput.text = current == '0' && RegExp(r'^\d$').hasMatch(token) ? token : current + token;
                                  }
                                });
                              },
                              child: Text(key, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                            )).toList(),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  PageTemplate _template() {
    final name = pageData['template']?.toString();
    return PageTemplate.values.firstWhere(
      (value) => value.name == name,
      orElse: () => PageTemplate.dotted,
    );
  }

  Color _pageColor([String key = 'paperColor', Color fallback = Colors.white]) {
    final value = pageData[key];
    return value is num ? Color(value.toInt()) : fallback;
  }

  double _pageDouble(String key, double fallback) {
    final value = pageData[key];
    return value is num ? value.toDouble() : fallback;
  }

  Widget _header() => Positioned(
        left: 0,
        right: 0,
        top: 0,
        child: Material(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: .98),
          child: SizedBox(
            height: 46,
            child: Row(children: [
              _compactAction(
                tooltip: 'Back to notes',
                icon: Icons.menu_rounded,
                onPressed: () async { await _flushSave(); if (mounted) Navigator.maybePop(context); },
              ),
              AnimatedBuilder(
                animation: _canvas,
                builder: (_, __) => Row(mainAxisSize: MainAxisSize.min, children: [
                  _compactAction(tooltip: 'Undo', icon: Icons.undo_rounded, onPressed: _canvas.canUndo ? _canvas.undo : null),
                  _compactAction(tooltip: 'Redo', icon: Icons.redo_rounded, onPressed: _canvas.canRedo ? _canvas.redo : null),
                  _compactAction(
                    tooltip: _tabsVisible ? 'Hide note tabs' : 'Show note tabs',
                    icon: Icons.tab_outlined,
                    onPressed: () => setState(() => _tabsVisible = !_tabsVisible),
                  ),
                ]),
              ),
              Expanded(
                child: TextField(
                  controller: _title,
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    border: InputBorder.none,
                    hintText: 'Untitled note',
                  ),
                  onChanged: (_) => _refreshCurrentOpenTab(),
                  onSubmitted: (_) => _save(force: true),
                ),
              ),
              _compactAction(tooltip: 'Save note', icon: Icons.save_outlined, onPressed: () => _save(force: true)),







              _compactAction(tooltip: 'Pages / thumbnails', icon: Icons.view_sidebar_outlined, onPressed: () => setState(() => _preview = !_preview)),

              _compactAction(tooltip: 'Shapes and diagrams', icon: Icons.category_outlined, onPressed: () => setState(() => _shapePanel = !_shapePanel)),
              _compactAction(tooltip: _draw ? 'Text mode' : 'Handwriting mode', icon: _draw ? Icons.text_fields_rounded : Icons.draw_rounded, onPressed: () => setState(() => _draw = !_draw)),
              _compactAction(tooltip: 'Lock note', icon: _locked ? Icons.lock_rounded : Icons.lock_outline_rounded, onPressed: _lockNote),
              _compactAction(tooltip: 'Fullscreen', icon: _full ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded, onPressed: _toggleFullscreen),
              _compactAction(
                 tooltip: 'Note settings',
                 icon: Icons.settings_outlined,
                 onPressed: () => Navigator.push(
                   context,
                   MaterialPageRoute(builder: (_) => const SettingsPage(noteOnly: true)),
                 ).then((_) {
                   if (mounted) {
                     setState(() {});
                     _keepAwake();
                   }
                 }),
               ),
            ]),
          ),
        ),
      );

  Widget _compactAction({
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
  }) => IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        constraints: const BoxConstraints.tightFor(width: 34, height: 40),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        icon: Icon(icon, size: 20),
      );


  Widget _movablePageChanger() {
    final size = MediaQuery.sizeOf(context);
    return Positioned(
      left: _pageChangerX < 0 ? null : _pageChangerX,
      right: _pageChangerX < 0 ? 8 : null,
      top: _pageChangerY.clamp(50.0, math.max(50.0, size.height - 62)),
      child: Material(
        elevation: 8,
        color: Theme.of(context).colorScheme.surface.withValues(alpha: .94),
        borderRadius: BorderRadius.circular(16),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                final x = _pageChangerX < 0 ? size.width - 166 : _pageChangerX;
                _pageChangerX = (x + details.delta.dx).clamp(4.0, math.max(4.0, size.width - 170));
                _pageChangerY = (_pageChangerY + details.delta.dy).clamp(50.0, math.max(50.0, size.height - 62));
              });
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 5, vertical: 8),
              child: Icon(Icons.drag_indicator_rounded, size: 18),
            ),
          ),
          IconButton(
            onPressed: _previousPage,
            tooltip: 'Previous page',
            constraints: const BoxConstraints.tightFor(width: 30, height: 34),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chevron_left_rounded, size: 20),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Text('${_page + 1}/${_pages.length}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
          ),
          IconButton(
            onPressed: _nextPage,
            tooltip: 'Next page',
            constraints: const BoxConstraints.tightFor(width: 30, height: 34),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chevron_right_rounded, size: 20),
          ),
          IconButton(
            onPressed: _addPage,
            tooltip: 'Add page',
            constraints: const BoxConstraints.tightFor(width: 30, height: 34),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add_rounded, size: 18),
          ),
        ]),
      ),
    );
  }

  Widget _toolbarOpen() => Positioned(
        right: 8,
        top: MediaQuery.sizeOf(context).height * .45,
        child: FloatingActionButton.small(heroTag: 'tools-open', onPressed: () => setState(() => _toolbar = true), child: const Icon(Icons.edit_rounded)),
      );

  Widget _fullExit() => Positioned(
        right: 12,
        top: 12,
        child: SafeArea(child: FloatingActionButton.small(heroTag: 'full-exit', onPressed: _toggleFullscreen, child: const Icon(Icons.fullscreen_exit_rounded))),
      );

  Widget _toolbarWidget() {
    final screen = MediaQuery.sizeOf(context);
    final axis = _docked
        ? (_dockSide == 'left' || _dockSide == 'right'
            ? Axis.vertical
            : Axis.horizontal)
        : _floatingAxis;
    final constraints = axis == Axis.vertical
        ? BoxConstraints(
            maxWidth: 128,
            maxHeight: math.max(160, screen.height - 76),
          )
        : BoxConstraints(
            maxWidth: math.max(120, screen.width - 16),
            maxHeight: 92,
          );
    final toolbar = ConstrainedBox(
      constraints: constraints,
      child: _toolbarSurface(
        _toolbarContent(axis, docked: _docked),
        key: _toolbarKey,
      ),
    );

    // Always keep the same Positioned -> toolbar subtree. Only the position
    // changes, so a drag can be released and snapped repeatedly.
    return ValueListenableBuilder<Offset>(
      valueListenable: _toolbarOffset,
      builder: (_, offset, child) {
        if (_docked) {
          return Positioned(
            left: _dockSide == 'left' ? 0 : null,
            right: _dockSide == 'right' ? 0 : null,
            top: _dockSide == 'top' ? (_full ? 0 : 46) : null,
            bottom: _dockSide == 'bottom' ? 0 : null,
            child: child!,
          );
        }

        final fallbackY = screen.height - math.min(screen.height - 72, 112);
        return Positioned(
          left: offset.dx.clamp(4.0, math.max(4.0, screen.width - 144)).toDouble(),
          top: (offset.dy == 0 ? fallbackY : offset.dy)
              .clamp(_full ? 4.0 : 54.0, math.max(_full ? 4.0 : 54.0, screen.height - 104))
              .toDouble(),
          child: child!,
        );
      },
      child: toolbar,
    );
  }

  Widget _toolbarSurface(Widget child, {Key? key}) {
    final blur = SnoteThemeController.instance.eInk ? 0.0 : 12.0;
    return ClipRRect(
      key: key,
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Material(
          elevation: SnoteThemeController.instance.eInk ? 0 : 8,
          color: Theme.of(context).colorScheme.surface.withValues(alpha: .70),
          child: child,
        ),
      ),
    );
  }

  Widget _toolbarContent(Axis axis, {required bool docked}) {
    final configured = _settings.getString('pencaseTools').split(',').where((v) => v.isNotEmpty).toSet();
    final defaultTools = <CanvasTool>[
      CanvasTool.ballpoint,
      CanvasTool.fountain,
      CanvasTool.pencil,
      CanvasTool.highlighter,
      CanvasTool.marker,
      CanvasTool.brush,
      CanvasTool.eraser,
      CanvasTool.lasso,
      CanvasTool.line,
      CanvasTool.arrow,
      CanvasTool.rectangle,
      CanvasTool.ellipse,
      CanvasTool.cartesianPlane,
      CanvasTool.dashedLine,
      CanvasTool.dottedLine,
      CanvasTool.ruler,
      CanvasTool.compass,
      CanvasTool.protractor, CanvasTool.divider,
    ];
    final pencaseTools = defaultTools.where((tool) => tool != CanvasTool.pixelEraser && configured.contains(tool.name)).toList();

    final items = <Widget>[
      GestureDetector(
        onPanUpdate: (details) {
          final stackRenderObject = _editorStackKey.currentContext?.findRenderObject();
          final viewport = stackRenderObject is RenderBox
              ? stackRenderObject.size
              : MediaQuery.sizeOf(context);
          final wasDocked = _docked;
          final renderObject = _toolbarKey.currentContext?.findRenderObject();
          final currentSize = renderObject is RenderBox ? renderObject.size : const Size(64, 360);
          final movingAxis = wasDocked
              ? (_dockSide == 'left' || _dockSide == 'right' ? Axis.vertical : Axis.horizontal)
              : _floatingAxis;
          final freeWidth = !wasDocked
              ? currentSize.width
              : movingAxis == Axis.vertical
                  ? currentSize.width
                  : math.min(viewport.width - 8, 420.0);
          final freeHeight = !wasDocked
              ? currentSize.height
              : movingAxis == Axis.vertical
                  ? math.min(viewport.height - 62, 420.0)
                  : currentSize.height;
          var origin = Offset(_toolbarX, _toolbarY);
          if (_docked) {
            final toolbarObject = _toolbarKey.currentContext?.findRenderObject();
            final stackObject = _editorStackKey.currentContext?.findRenderObject();
            if (toolbarObject is RenderBox && stackObject is RenderBox) {
              origin = stackObject.globalToLocal(toolbarObject.localToGlobal(Offset.zero));
            }
          }
          setState(() {
            if (wasDocked) {
              _floatingAxis = movingAxis;
            }
            _docked = false;
            _toolbarX = (origin.dx + details.delta.dx)
                .clamp(4.0, math.max(4.0, viewport.width - freeWidth - 4))
                .toDouble();
            _toolbarY = (origin.dy + details.delta.dy)
                .clamp(54.0, math.max(54.0, viewport.height - freeHeight - 8))
                .toDouble();
            _toolbarOffset.value = Offset(_toolbarX, _toolbarY);
          });
          pageData['toolbarAxis'] = _floatingAxis.name;
        },
        // Keep this callback installed when a drag undocks the toolbar, otherwise
        // the rebuilding GestureDetector may discard the release event.
        onPanEnd: (_) => _snapToolbar(MediaQuery.sizeOf(context)),
        onPanCancel: () => _snapToolbar(MediaQuery.sizeOf(context)),
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Icon(Icons.drag_indicator_rounded, size: 19, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
      ...pencaseTools.map((tool) => _toolButton(tool, _toolIcon(tool))),
      IconButton.filledTonal(
        onPressed: () => setState(() => _shapePanel = !_shapePanel),
        icon: const Icon(Icons.category_outlined),
        tooltip: 'Shapes',
      ),
      IconButton.filledTonal(
        onPressed: _stickers,
        icon: const Icon(Icons.emoji_emotions_outlined),
        tooltip: 'Stickers',
      ),
      PopupMenuButton<String>(
        tooltip: 'More tools',
        icon: const Icon(Icons.more_horiz_rounded),
        onSelected: (action) async {
          switch (action) {
            case 'calculator':
              await _calculatorSheet();
              break;
            case 'templates':
              await _paperSheet();
              break;
            case 'reading':
              setState(() => _readingMode = !_readingMode);
              break;
            case 'timer':
              await _studyTimerSheet();
              break;
            case 'palm':
              await _settings.setBool('palmRejection', !_settings.getBool('palmRejection'));
              if (mounted) setState(() {});
              break;
            case 'pdf':
              await _importPdfIntoNote();
              break;
            case 'showcase':
              setState(() => _showcaseOpen = !_showcaseOpen);
              break;
            case 'cover':
              await _chooseNoteCover();
              break;
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'calculator', child: Row(children: [Icon(Icons.calculate_outlined, size: 19), SizedBox(width: 10), Text('Calculator')])),
          PopupMenuItem(value: 'templates', child: Row(children: [Icon(Icons.grid_4x4_rounded, size: 19), SizedBox(width: 10), Text('Page templates')])),
          PopupMenuItem(value: 'reading', child: Row(children: [Icon(Icons.chrome_reader_mode_outlined, size: 19), SizedBox(width: 10), Text('Reading mode')])),
          PopupMenuItem(value: 'timer', child: Row(children: [Icon(Icons.timer_outlined, size: 19), SizedBox(width: 10), Text('Study timer')])),
          PopupMenuItem(value: 'palm', child: Row(children: [Icon(Icons.back_hand_outlined, size: 19), SizedBox(width: 10), Text('Toggle palm rejection')])),
          PopupMenuItem(value: 'pdf', child: Row(children: [Icon(Icons.picture_as_pdf_outlined, size: 19), SizedBox(width: 10), Text('Insert PDF pages')])),
          PopupMenuItem(value: 'showcase', child: Row(children: [Icon(Icons.inventory_2_outlined, size: 19), SizedBox(width: 10), Text('Tool showcase')])),
          PopupMenuItem(value: 'cover', child: Row(children: [Icon(Icons.photo_album_outlined, size: 19), SizedBox(width: 10), Text('Note cover page')])),
        ],
      ),
      IconButton(
        onPressed: _colorSheet,
        icon: Icon(Icons.circle, color: _toolColorOverrides[_tool.name] ?? _penColor, size: 22),
        tooltip: 'Current pen color',
      ),
      IconButton(
        onPressed: () {
          _toolOptionsAnchorPosition = _toolbarOptionsAnchor();
          unawaited(_styleSheet());
        },
        icon: const Icon(Icons.tune_rounded),
        tooltip: 'Tool style',
      ),
      IconButton(
        onPressed: () => setState(() => _draw = !_draw),
        icon: Icon(_draw ? Icons.text_fields_rounded : Icons.draw_rounded),
        tooltip: 'Text / draw',
      ),
      IconButton(
        onPressed: () => setState(() => _toolbar = false),
        icon: const Icon(Icons.close_rounded),
        tooltip: 'Close tools',
      ),
    ];

    return SingleChildScrollView(
      scrollDirection: axis == Axis.horizontal ? Axis.horizontal : Axis.vertical,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        child: IconButtonTheme(
          data: IconButtonThemeData(
            style: IconButton.styleFrom(
              fixedSize: const Size(34, 34),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
          ),
          child: Flex(direction: axis, mainAxisSize: MainAxisSize.min, children: items),
        ),
      ),
    );
  }

  IconData _toolIcon(CanvasTool tool) {
    // Keep pen, lasso, erasers and common geometry visually distinct. The
    // remaining specialist shapes use related, recognizable study icons.
    const exact = <CanvasTool, IconData>{
      CanvasTool.ballpoint: Icons.edit_rounded,
      CanvasTool.fountain: Icons.draw_rounded,
      CanvasTool.pencil: Icons.edit_note_rounded,
      CanvasTool.highlighter: Icons.highlight_rounded,
      CanvasTool.marker: Icons.border_color_rounded,
      CanvasTool.brush: Icons.brush_rounded,
      CanvasTool.eraser: Icons.auto_fix_normal_rounded,
      CanvasTool.pixelEraser: Icons.auto_fix_high_rounded,
      CanvasTool.lasso: Icons.gesture_rounded,
      CanvasTool.line: Icons.horizontal_rule_rounded,
      CanvasTool.dottedLine: Icons.more_horiz_rounded,
      CanvasTool.dashedLine: Icons.linear_scale_rounded,
      CanvasTool.arrow: Icons.arrow_right_alt_rounded,
      CanvasTool.vectorArrow: Icons.north_east_rounded,
      CanvasTool.projectilePath: Icons.trending_up_rounded,
      CanvasTool.rectangle: Icons.crop_square_rounded,
      CanvasTool.roundedRectangle: Icons.rounded_corner_rounded,
      CanvasTool.ellipse: Icons.circle_outlined,
      CanvasTool.circle: Icons.circle_outlined,
      CanvasTool.triangle: Icons.change_history_outlined,
      CanvasTool.diamond: Icons.diamond_outlined,
      CanvasTool.hexagon: Icons.hexagon_outlined,
      CanvasTool.star: Icons.star_border_rounded,
      CanvasTool.customPolygon: Icons.hdr_strong_rounded,
      CanvasTool.coordinateAxes: Icons.grid_4x4_rounded,
      CanvasTool.cartesianPlane: Icons.grid_on_rounded,
      CanvasTool.parabola: Icons.show_chart_rounded,
      CanvasTool.sineWave: Icons.waves_rounded,
      CanvasTool.cubicGraph: Icons.show_chart_rounded,
      CanvasTool.exponentialGraph: Icons.trending_up_rounded,
      CanvasTool.logarithmicGraph: Icons.stacked_line_chart_rounded,
      CanvasTool.tangentGraph: Icons.multiline_chart_rounded,
      CanvasTool.histogram: Icons.bar_chart_rounded,
      CanvasTool.barChart: Icons.bar_chart_rounded,
      CanvasTool.pieChart: Icons.pie_chart_outline_rounded,
      CanvasTool.tableGrid: Icons.table_chart_outlined,
      CanvasTool.checklist: Icons.checklist_rounded,
      CanvasTool.ruler: Icons.straighten_rounded,
      CanvasTool.compass: Icons.explore_outlined,
      CanvasTool.protractor: Icons.architecture_rounded,
      CanvasTool.divider: Icons.straighten_rounded,
      CanvasTool.rayDiagram: Icons.light_mode_outlined,
      CanvasTool.convexLens: Icons.lens_outlined,
      CanvasTool.concaveLens: Icons.remove_red_eye_outlined,
      CanvasTool.planeMirror: Icons.flip_rounded,
      CanvasTool.forceDiagram: Icons.device_hub_outlined,
      CanvasTool.pulley: Icons.settings_input_component_outlined,
      CanvasTool.circuitResistor: Icons.electrical_services_outlined,
      CanvasTool.circuitBattery: Icons.battery_charging_full_rounded,
      CanvasTool.capacitor: Icons.electrical_services_outlined,
      CanvasTool.circuitSwitch: Icons.toggle_on_outlined,
      CanvasTool.circuitLamp: Icons.lightbulb_outline_rounded,
      CanvasTool.atom: Icons.hub_outlined,
      CanvasTool.molecule: Icons.bubble_chart_outlined,
      CanvasTool.benzeneRing: Icons.hexagon_outlined,
      CanvasTool.beaker: Icons.science_outlined,
      CanvasTool.testTube: Icons.science_outlined,
      CanvasTool.conicalFlask: Icons.science_outlined,
      CanvasTool.orbital: Icons.blur_circular_rounded,
      CanvasTool.animalCell: Icons.circle_outlined,
      CanvasTool.plantCell: Icons.crop_square_rounded,
      CanvasTool.dnaHelix: Icons.biotech_outlined,
      CanvasTool.neuron: Icons.hub_outlined,
      CanvasTool.leaf: Icons.eco_outlined,
      CanvasTool.microscope: Icons.biotech_outlined,
      CanvasTool.sticker: Icons.emoji_emotions_outlined,
    };
    final chosen = exact[tool];
    if (chosen != null) return chosen;
    switch (tool) {
      case CanvasTool.pentagon:
      case CanvasTool.parallelogram:
      case CanvasTool.trapezoid:
      case CanvasTool.cube:
      case CanvasTool.cuboid:
      case CanvasTool.cylinder:
      case CanvasTool.cone:
      case CanvasTool.pyramid:
      case CanvasTool.triangularPrism:
      case CanvasTool.sphere:
      case CanvasTool.arc:
      case CanvasTool.semicircle:
      case CanvasTool.sector:
      case CanvasTool.ring:
      case CanvasTool.crescent:
      case CanvasTool.cross:
      case CanvasTool.plus:
      case CanvasTool.heart:
      case CanvasTool.cloud:
      case CanvasTool.speechBubble:
      case CanvasTool.callout:
      case CanvasTool.curlyBrace:
      case CanvasTool.bracket:
      case CanvasTool.dimensionLine:
      case CanvasTool.numberLine:
        return Icons.category_outlined;
      case CanvasTool.unitCircle:
      case CanvasTool.ellipseAxes:
      case CanvasTool.vectorField:
      case CanvasTool.polarGraph:
        return Icons.grid_4x4_rounded;
      case CanvasTool.flowchartTerminator:
      case CanvasTool.flowchartProcess:
      case CanvasTool.flowchartDecision:
      case CanvasTool.flowchartInputOutput:
      case CanvasTool.flowchartDocument:
      case CanvasTool.flowchartDatabase:
      case CanvasTool.flowchartConnector:
      case CanvasTool.timeline:
        return Icons.account_tree_outlined;
      case CanvasTool.waveform:
      case CanvasTool.spring:
      case CanvasTool.lever:
      case CanvasTool.inclinedPlane:
      case CanvasTool.gear:
      case CanvasTool.magnet:
      case CanvasTool.thermometer:
      case CanvasTool.stopwatch:
        return Icons.science_outlined;
      default:
        return Icons.category_outlined;
    }
  }

  List<Color> get _penPalette => const [
    Color(0xff111111), Color(0xff374151), Color(0xff6b7280), Color(0xff9ca3af),
    Color(0xffb91c1c), Color(0xffef4444), Color(0xfff97316), Color(0xfff59e0b),
    Color(0xffca8a04), Color(0xff16a34a), Color(0xff22c55e), Color(0xff0f766e),
    Color(0xff0891b2), Color(0xff2563eb), Color(0xff4f46e5), Color(0xff7c3aed),
    Color(0xffc026d3), Color(0xffdb2777), Color(0xffbe185d), Color(0xff92400e),
    Color(0xff65a30d), Color(0xff0d9488), Color(0xff0284c7), Color(0xfff8fafc),
  ];

  void _snapToolbar(Size screenSize) {
    final stackObject = _editorStackKey.currentContext?.findRenderObject();
    final bounds = stackObject is RenderBox ? stackObject.size : screenSize;
    final box = _toolbarKey.currentContext?.findRenderObject();
    final toolbarSize = box is RenderBox ? box.size : const Size(128, 360);
    final topLimit = _full ? 0.0 : 46.0;
    final distances = <String, double>{
      'left': _toolbarX,
      'right': bounds.width - (_toolbarX + toolbarSize.width),
      'top': _toolbarY - topLimit,
      'bottom': bounds.height - (_toolbarY + toolbarSize.height),
    };
    final nearest = distances.entries.reduce(
      (a, b) => a.value.abs() <= b.value.abs() ? a : b,
    );
    if (nearest.value.abs() < 84) {
      setState(() {
        _docked = true;
        _dockSide = nearest.key;
      });
    } else {
      setState(() {
        _docked = false;
        _toolbarX = _toolbarX
            .clamp(4.0, math.max(4.0, bounds.width - toolbarSize.width - 4))
            .toDouble();
        _toolbarY = _toolbarY
            .clamp(topLimit + 4, math.max(topLimit + 4, bounds.height - toolbarSize.height - 4))
            .toDouble();
      });
    }

    _toolbarOffset.value = Offset(_toolbarX, _toolbarY);
    pageData['toolbarX'] = _toolbarX;
    pageData['toolbarY'] = _toolbarY;
    pageData['toolbarDock'] = _docked ? _dockSide : 'free';
    pageData['toolbarAxis'] = _floatingAxis.name;
    unawaited(_settings.setString('toolbarDock', _docked ? _dockSide : 'free'));
    unawaited(_settings.setDouble('toolbarX', _toolbarX));
    unawaited(_settings.setDouble('toolbarY', _toolbarY));
    _scheduleSave();
  }

  Future<void> _commitToolOptions({
    required CanvasTool target,
    required double size,
    required Color color,
    required double opacity,
    required bool fill,
    bool? dashed,
    int? sides,
  }) async {
    _toolSizeOverrides[target.name] = size;
    _toolColorOverrides[target.name] = color;
    if (dashed != null) _toolDashedOverrides[target.name] = dashed;
    if (target == _tool) {
      setState(() {
        _penSize = size;
        _penColor = color;
        _opacity = opacity;
        _fill = fill;
        _fillColor = fill ? color : null;
        if (dashed != null) _dashed = dashed;
        if (sides != null) _sides = sides;
      });
      await _settings.setDouble('penOpacity', opacity);
    } else {
      setState(() {});
    }
    await _settings.setString('toolSizes', jsonEncode(_toolSizeOverrides));
    await _settings.setString('toolColors', jsonEncode({
      for (final entry in _toolColorOverrides.entries) entry.key: entry.value.toARGB32(),
    }));
    await _settings.setString('toolDashed', jsonEncode(_toolDashedOverrides));
  }

  Future<void> _showInlineToolOptions(CanvasTool target, Offset globalPosition) async {
    _toolOptionsAnchorPosition = globalPosition;
    var size = _toolSizeOverrides[target.name] ?? _defaultToolSize(target);
    var opacity = target == _tool ? _opacity : 1.0;
    var color = _toolColorOverrides[target.name] ?? _defaultToolColor(target);
    var fill = target == _tool && _fill;
    var showAdvanced = false;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Tool options',
      barrierColor: Colors.black12,
      pageBuilder: (popupContext, animation, secondaryAnimation) {
        final screen = MediaQuery.sizeOf(popupContext);
        final left = (globalPosition.dx + 12).clamp(8.0, math.max(8.0, screen.width - 308)).toDouble();
        final top = (globalPosition.dy - 30).clamp(52.0, math.max(52.0, screen.height - 370)).toDouble();
        return StatefulBuilder(
          builder: (dialogContext, setPopup) => Stack(
            children: [
              Positioned(
                left: left,
                top: top,
                width: 296,
                child: Material(
                  elevation: 18,
                  color: Theme.of(dialogContext).colorScheme.surface,
                  borderRadius: BorderRadius.circular(18),
                  clipBehavior: Clip.antiAlias,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(children: [
                              Icon(_toolIcon(target), size: 20),
                              const SizedBox(width: 8),
                              Expanded(child: Text('${target.label} settings', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
                              IconButton(
                                tooltip: 'Close',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => Navigator.pop(dialogContext),
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ]),
                            Text('Stroke size: ${size.toStringAsFixed(1)} px'),
                            Slider(
                              value: size.clamp(.5, 60).toDouble(),
                              min: .5,
                              max: 60,
                              onChanged: (value) {
                                setPopup(() => size = value);
                                unawaited(_commitToolOptions(target: target, size: value, color: color, opacity: opacity, fill: fill));
                              },
                            ),
                            Text('Opacity: ${(opacity * 100).round()}%'),
                            Slider(
                              value: opacity.clamp(.05, 1).toDouble(),
                              min: .05,
                              max: 1,
                              onChanged: (value) {
                                setPopup(() => opacity = value);
                                unawaited(_commitToolOptions(target: target, size: size, color: color, opacity: value, fill: fill));
                              },
                            ),
                            const Text('Color', style: TextStyle(fontWeight: FontWeight.w800)),
                            const SizedBox(height: 7),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _penPalette.take(18).map((choice) => InkWell(
                                onTap: () {
                                  setPopup(() => color = choice);
                                  unawaited(_commitToolOptions(target: target, size: size, color: choice, opacity: opacity, fill: fill));
                                },
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  width: 27,
                                  height: 27,
                                  decoration: BoxDecoration(
                                    color: choice,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: choice.toARGB32() == color.toARGB32()
                                          ? Theme.of(dialogContext).colorScheme.primary
                                          : Colors.black26,
                                      width: choice.toARGB32() == color.toARGB32() ? 3 : 1,
                                    ),
                                  ),
                                ),
                              )).toList(),
                            ),
                            if (target.isShape)
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                value: fill,
                                onChanged: (value) {
                                  setPopup(() => fill = value);
                                  unawaited(_commitToolOptions(target: target, size: size, color: color, opacity: opacity, fill: value));
                                },
                                title: const Text('Fill shape'),
                              ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: () {
                                  Navigator.pop(dialogContext);
                                  showAdvanced = true;
                                },
                                icon: const Icon(Icons.tune_rounded, size: 18),
                                label: const Text('More settings'),
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () => _collectToolToShowcase(target, size: size, color: color, opacity: opacity),
                                icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                                label: const Text('Collect to showcase'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (showAdvanced && mounted) await _styleSheet(target);
  }

  Future<void> _samplePageColor(Offset globalPosition) async {
    try {
      await WidgetsBinding.instance.endOfFrame;
      final renderObject = _pageCaptureKey.currentContext?.findRenderObject();
      if (renderObject is! RenderRepaintBoundary) {
        throw StateError('The page is not ready to sample.');
      }
      final image = await renderObject.toImage(pixelRatio: 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) {
        image.dispose();
        throw StateError('Could not read the page pixels.');
      }
      final local = renderObject.globalToLocal(globalPosition);
      final x = local.dx.round().clamp(0, image.width - 1);
      final y = local.dy.round().clamp(0, image.height - 1);
      final offset = (y * image.width + x) * 4;
      final sampled = Color.fromARGB(
        data.getUint8(offset + 3),
        data.getUint8(offset),
        data.getUint8(offset + 1),
        data.getUint8(offset + 2),
      );
      image.dispose();
      if (!mounted) return;
      setState(() {
        _penColor = sampled;
        _toolColorOverrides[_tool.name] = sampled;
        _eyedropperActive = false;
      });
      await _settings.setString('toolColors', jsonEncode({
        for (final entry in _toolColorOverrides.entries) entry.key: entry.value.toARGB32(),
      }));
    } catch (error) {
      if (mounted) {
        setState(() => _eyedropperActive = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not sample colour: $error')),
        );
      }
    }
  }

  Future<void> _collectToolToShowcase(
    CanvasTool target, {
    required double size,
    required Color color,
    required double opacity,
  }) async {
    final controller = TextEditingController(text: target.label + ' ' + (_savedPenPresets.length + 1).toString());
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Collect to showcase'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Tool preset name', hintText: 'Blue fountain pen'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text), child: const Text('Collect')),
        ],
      ),
    );
    controller.dispose();
    if (name == null) return;
    final presets = _savedPenPresets;
    presets.insert(0, <String, dynamic>{
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'name': name.trim().isEmpty ? target.label + ' ' + (presets.length + 1).toString() : name.trim(),
      'tool': target.name,
      'color': color.toARGB32(),
      'size': size.clamp(.5, 60).toDouble(),
      'opacity': opacity.clamp(.05, 1).toDouble(),
    });
    await _settings.setString('pencasePresets', jsonEncode(presets));
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tool added to your showcase.')));
    }
  }

  Widget _toolButton(CanvasTool tool, IconData icon) => GestureDetector(
        onDoubleTapDown: (details) => _showInlineToolOptions(tool, details.globalPosition),
        child: IconButton(
          onPressed: () => _selectTool(tool),
          constraints: const BoxConstraints.tightFor(width: 29, height: 30),
          padding: EdgeInsets.zero,
          visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
          style: IconButton.styleFrom(
            backgroundColor: _tool == tool ? Theme.of(context).colorScheme.primaryContainer : null,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          icon: Icon(icon, size: 18),
          tooltip: '${tool.label} (double-tap for options)',
        ),
      );

  Future<void> _selectionColorSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _penPalette.map((color) => InkWell(
            onTap: () {
              _canvas.changeColor(color);
              Navigator.pop(sheetContext);
            },
            child: CircleAvatar(backgroundColor: color, radius: 17),
          )).toList(),
        ),
      ),
    );
  }

  Future<void> _selectionSizeSheet() async {
    var size = _penSize;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (_, setModal) => Padding(
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Selected stroke ' + size.toStringAsFixed(1)),
            Slider(
              value: size.clamp(.5, 24),
              min: .5,
              max: 24,
              divisions: 47,
              onChanged: (v) {
                setModal(() => size = v);
                _canvas.changeSize(v);
              },
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: () => Navigator.pop(sheetContext), child: const Text('Done')),
            ),
          ]),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> get _savedPenPresets {
    try {
      final decoded = jsonDecode(_settings.getString('pencasePresets'));
      if (decoded is List) {
        return decoded.whereType<Map>().map((entry) => Map<String, dynamic>.from(entry)).toList();
      }
    } catch (_) {}
    return <Map<String, dynamic>>[];
  }

  Future<void> _applyPenPreset(Map<String, dynamic> preset) async {
    final toolName = preset['tool']?.toString() ?? CanvasTool.ballpoint.name;
    final target = CanvasTool.values.firstWhere(
      (tool) => tool.name == toolName,
      orElse: () => CanvasTool.ballpoint,
    );
    final colorValue = (preset['color'] as num?)?.toInt() ?? _penColor.toARGB32();
    final size = (preset['size'] as num?)?.toDouble() ?? _penSize;
    final opacity = (preset['opacity'] as num?)?.toDouble() ?? _opacity;
    setState(() {
      _tool = target;
      _penColor = Color(colorValue);
      _toolColorOverrides[target.name] = Color(colorValue);
      _penSize = size.clamp(.5, 60).toDouble();
      _toolSizeOverrides[target.name] = _penSize;
      _opacity = opacity.clamp(.05, 1).toDouble();
    });
    await _settings.setString('toolColors', jsonEncode({
      for (final entry in _toolColorOverrides.entries) entry.key: entry.value.toARGB32(),
    }));
    await _settings.setString('toolSizes', jsonEncode(_toolSizeOverrides));
  }

  Widget _presetToolButton(Map<String, dynamic> preset) {
    final name = preset['name']?.toString() ?? 'Saved pen';
    final colorValue = (preset['color'] as num?)?.toInt() ?? _penColor.toARGB32();
    return IconButton(
      tooltip: name,
      onPressed: () => unawaited(_applyPenPreset(preset)),
      icon: Container(
        width: 21,
        height: 21,
        decoration: BoxDecoration(
          color: Color(colorValue),
          shape: BoxShape.circle,
          border: Border.all(
            color: Theme.of(context).colorScheme.outline,
            width: 1.4,
          ),
        ),
        child: const Icon(Icons.edit_rounded, size: 12, color: Colors.white),
      ),
    );
  }

  Widget _showcaseWidget() {
    final presets = _savedPenPresets;
    final side = _showcaseDock;
    return Positioned(
      left: side == 'left' ? 8 : (side == 'free' ? _showcaseX : null),
      right: side == 'right' ? 8 : null,
      top: side == 'top' ? 54 : (side == 'free' ? _showcaseY : null),
      bottom: side == 'bottom' ? 8 : null,
      child: Material(
        key: _showcaseKey,
        elevation: 14,
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 250,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onPanUpdate: (details) {
                  final size = MediaQuery.sizeOf(context);
                  final panelObject = _showcaseKey.currentContext?.findRenderObject();
                  final stackObject = _editorStackKey.currentContext?.findRenderObject();
                  var origin = Offset(_showcaseX, _showcaseY);
                  if (panelObject is RenderBox && stackObject is RenderBox) {
                    origin = stackObject.globalToLocal(panelObject.localToGlobal(Offset.zero));
                  }
                  setState(() {
                    _showcaseDock = 'free';
                    _showcaseX = (origin.dx + details.delta.dx).clamp(4.0, math.max(4.0, size.width - 260)).toDouble();
                    _showcaseY = (origin.dy + details.delta.dy).clamp(50.0, math.max(50.0, size.height - 300)).toDouble();
                  });
                },
                onPanEnd: (_) {
                  final size = MediaQuery.sizeOf(context);
                  final distances = <String, double>{
                    'left': _showcaseX,
                    'right': size.width - (_showcaseX + 250),
                    'top': _showcaseY - 50,
                    'bottom': size.height - (_showcaseY + 280),
                  };
                  final nearest = distances.entries.reduce((a, b) => a.value < b.value ? a : b);
                  if (nearest.value.abs() < 70) {
                    setState(() => _showcaseDock = nearest.key);
                    unawaited(_settings.setString('toolShowcaseDockSide', nearest.key));
                  } else {
                    unawaited(_settings.setString('toolShowcaseDockSide', 'free'));
                    unawaited(_settings.setDouble('toolShowcaseX', _showcaseX));
                    unawaited(_settings.setDouble('toolShowcaseY', _showcaseY));
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 9, 4, 8),
                  child: Row(
                    children: [
                      const Icon(Icons.drag_indicator_rounded),
                      const SizedBox(width: 6),
                      const Expanded(child: Text('Tool showcase', style: TextStyle(fontWeight: FontWeight.w900))),
                      PopupMenuButton<String>(
                        tooltip: 'Attach showcase to an edge',
                        onSelected: (value) {
                          setState(() => _showcaseDock = value);
                          unawaited(_settings.setString('toolShowcaseDockSide', value));
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'left', child: Text('Attach left')),
                          PopupMenuItem(value: 'right', child: Text('Attach right')),
                          PopupMenuItem(value: 'top', child: Text('Attach top')),
                          PopupMenuItem(value: 'bottom', child: Text('Attach bottom')),
                          PopupMenuItem(value: 'free', child: Text('Float freely')),
                        ],
                        icon: const Icon(Icons.dock_rounded),
                      ),
                      IconButton(
                        tooltip: 'Close showcase',
                        onPressed: () => setState(() => _showcaseOpen = false),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              if (presets.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(18),
                  child: Text('Open any tool options and choose “Collect to showcase” to save reusable colors and sizes.'),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: presets.length,
                    itemBuilder: (context, index) {
                      final preset = presets[index];
                      final color = Color((preset['color'] as num?)?.toInt() ?? 0xff263238);
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(backgroundColor: color, radius: 13, child: const Icon(Icons.edit_rounded, size: 13, color: Colors.white)),
                        title: Text(preset['name']?.toString() ?? 'Saved tool', maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text((preset['tool']?.toString() ?? 'pen') + ' · ' + ((preset['size'] as num?)?.toStringAsFixed(1) ?? '3') + ' px'),
                        onTap: () => unawaited(_applyPenPreset(preset)),
                        trailing: IconButton(
                          tooltip: 'Remove from showcase',
                          icon: const Icon(Icons.remove_circle_outline_rounded),
                          onPressed: () async {
                            final items = _savedPenPresets;
                            items.removeWhere((item) => item['id'] == preset['id']);
                            await _settings.setString('pencasePresets', jsonEncode(items));
                            if (mounted) setState(() {});
                          },
                        ),
                      );
                    },
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      setState(() => _showcaseOpen = false);
                      _pencaseSheet();
                    },
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Manage showcase tools'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pencaseSheet() async {
    const tools = <CanvasTool>[
      CanvasTool.ballpoint, CanvasTool.fountain, CanvasTool.pencil,
      CanvasTool.highlighter, CanvasTool.marker, CanvasTool.brush,
      CanvasTool.eraser, CanvasTool.lasso, CanvasTool.line,
      CanvasTool.arrow, CanvasTool.rectangle, CanvasTool.ellipse,
    ];
    final selected = _settings.getString('pencaseTools').split(',').where((v) => v.isNotEmpty).toSet();
    final presets = _savedPenPresets;
    final nameController = TextEditingController(text: '${_tool.label} ${presets.length + 1}');
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (_, setModal) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .86,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Align(alignment: Alignment.centerLeft, child: Text('Tool showcase', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900))),
                const SizedBox(height: 6),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Save the same pen multiple times with different colours and widths. Saved presets also appear in the floating toolbox.'),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Visible tools', style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: tools.map((tool) => FilterChip(
                          avatar: Icon(_toolIcon(tool), size: 18),
                          label: Text(tool.label),
                          selected: selected.contains(tool.name),
                          onSelected: (value) {
                            setModal(() {
                              if (value) {
                                selected.add(tool.name);
                              } else {
                                selected.remove(tool.name);
                              }
                            });
                            unawaited(_settings.setString('pencaseTools', selected.join(',')));
                          },
                        )).toList(),
                      ),
                      const Divider(height: 28),
                      const Text('Save the current pen as a preset', style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Preset name',
                          hintText: 'Blue fountain pen',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: _toolColorOverrides[_tool.name] ?? _penColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: Theme.of(context).colorScheme.outline),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text('${_tool.label} · ${(_toolSizeOverrides[_tool.name] ?? _penSize).toStringAsFixed(1)} px')),
                        FilledButton.icon(
                          onPressed: () async {
                            final name = nameController.text.trim().isEmpty
                                ? '${_tool.label} ${presets.length + 1}'
                                : nameController.text.trim();
                            final entry = <String, dynamic>{
                              'id': DateTime.now().microsecondsSinceEpoch.toString(),
                              'name': name,
                              'tool': _tool.name,
                              'color': (_toolColorOverrides[_tool.name] ?? _penColor).toARGB32(),
                              'size': _toolSizeOverrides[_tool.name] ?? _penSize,
                              'opacity': _opacity,
                            };
                            setModal(() => presets.insert(0, entry));
                            await _settings.setString('pencasePresets', jsonEncode(presets));
                            nameController.text = '${_tool.label} ${presets.length + 1}';
                          },
                          icon: const Icon(Icons.bookmark_add_outlined),
                          label: const Text('Save pen'),
                        ),
                      ]),
                      const Divider(height: 28),
                      Row(children: [
                        const Expanded(child: Text('Saved pen presets', style: TextStyle(fontWeight: FontWeight.w800))),
                        Text('${presets.length}'),
                      ]),
                      if (presets.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 18),
                          child: Text('No saved presets yet. Save a named pen above.'),
                        ),
                      for (final preset in presets)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: Color((preset['color'] as num?)?.toInt() ?? 0xff303030),
                            child: Icon(_toolIcon(CanvasTool.values.firstWhere(
                              (tool) => tool.name == preset['tool'],
                              orElse: () => CanvasTool.ballpoint,
                            )), color: Colors.white, size: 19),
                          ),
                          title: Text(preset['name']?.toString() ?? 'Saved pen'),
                          subtitle: Text('${preset['tool'] ?? 'ballpoint'} · ${((preset['size'] as num?)?.toDouble() ?? 3).toStringAsFixed(1)} px'),
                          onTap: () async {
                            Navigator.pop(sheetContext);
                            await _applyPenPreset(preset);
                          },
                          trailing: IconButton(
                            tooltip: 'Delete preset',
                            onPressed: () async {
                              final id = preset['id'];
                              setModal(() => presets.removeWhere((value) => value['id'] == id));
                              await _settings.setString('pencasePresets', jsonEncode(presets));
                            },
                            icon: const Icon(Icons.delete_outline_rounded),
                          ),
                        ),
                    ]),
                  ),
                ),
                const SizedBox(height: 10),
              ]),
            ),
          ),
        ),
      ),
    );
    nameController.dispose();
  }

  Widget _shapePanelWidget() => Positioned(
        right: 8,
        top: 88,
        bottom: 72,
        width: math.min(356, MediaQuery.sizeOf(context).width - 72),
        child: Material(
          elevation: 14,
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: DefaultTabController(
            length: 7,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 6, 0),
                child: Row(children: [
                  const Expanded(child: Text('Shapes & study diagrams', style: TextStyle(fontWeight: FontWeight.w900))),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Close shapes',
                    onPressed: () => setState(() => _shapePanel = false),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ]),
              ),
              const TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: 'Basic'),
                  Tab(text: 'Geometry'),
                  Tab(text: 'Maths'),
                  Tab(text: 'Diagrams'),
                  Tab(text: 'Physics'),
                  Tab(text: 'Chemistry'),
                  Tab(text: 'Biology'),
                ],
              ),
              Expanded(child: TabBarView(children: [
                _shapeGrid([
                  CanvasTool.line, CanvasTool.arrow, CanvasTool.dottedLine,
                  CanvasTool.dashedLine, CanvasTool.rectangle, CanvasTool.roundedRectangle,
                  CanvasTool.ellipse, CanvasTool.circle, CanvasTool.triangle,
                  CanvasTool.diamond, CanvasTool.hexagon, CanvasTool.star,
                  CanvasTool.customPolygon, CanvasTool.cartesianPlane,
                ]),
                _shapeGrid([
                  CanvasTool.pentagon, CanvasTool.parallelogram, CanvasTool.trapezoid,
                  CanvasTool.cube, CanvasTool.cuboid, CanvasTool.cylinder,
                  CanvasTool.cone, CanvasTool.pyramid, CanvasTool.triangularPrism,
                  CanvasTool.sphere, CanvasTool.arc, CanvasTool.semicircle,
                  CanvasTool.sector, CanvasTool.ring, CanvasTool.crescent,
                  CanvasTool.cross, CanvasTool.plus, CanvasTool.heart,
                  CanvasTool.cloud, CanvasTool.speechBubble, CanvasTool.callout,
                  CanvasTool.curlyBrace, CanvasTool.bracket, CanvasTool.dimensionLine,
                ]),
                _shapeGrid([
                  CanvasTool.coordinateAxes, CanvasTool.parabola, CanvasTool.sineWave,
                  CanvasTool.angle, CanvasTool.vectorArrow, CanvasTool.projectilePath,
                  CanvasTool.numberLine, CanvasTool.unitCircle, CanvasTool.cubicGraph,
                  CanvasTool.exponentialGraph, CanvasTool.logarithmicGraph, CanvasTool.tangentGraph,
                  CanvasTool.ellipseAxes, CanvasTool.vectorField, CanvasTool.polarGraph,
                ]),
                _shapeGrid([
                  CanvasTool.histogram, CanvasTool.barChart, CanvasTool.pieChart,
                  CanvasTool.flowchartTerminator, CanvasTool.flowchartProcess,
                  CanvasTool.flowchartDecision, CanvasTool.flowchartInputOutput,
                  CanvasTool.flowchartDocument, CanvasTool.flowchartDatabase,
                  CanvasTool.flowchartConnector, CanvasTool.timeline, CanvasTool.tableGrid,
                  CanvasTool.checklist, CanvasTool.waveform,
                ]),
                _shapeGrid([
                  CanvasTool.rayDiagram, CanvasTool.convexLens, CanvasTool.concaveLens,
                  CanvasTool.planeMirror, CanvasTool.forceDiagram, CanvasTool.pulley,
                  CanvasTool.circuitResistor, CanvasTool.circuitBattery, CanvasTool.capacitor,
                  CanvasTool.circuitSwitch, CanvasTool.circuitLamp, CanvasTool.spring,
                  CanvasTool.lever, CanvasTool.inclinedPlane, CanvasTool.gear,
                  CanvasTool.magnet, CanvasTool.thermometer, CanvasTool.stopwatch,
                  CanvasTool.ruler, CanvasTool.compass, CanvasTool.protractor,
                ]),
                _shapeGrid([
                  CanvasTool.atom, CanvasTool.molecule, CanvasTool.benzeneRing,
                  CanvasTool.beaker, CanvasTool.testTube, CanvasTool.conicalFlask,
                  CanvasTool.orbital,
                ]),
                _shapeGrid([
                  CanvasTool.animalCell, CanvasTool.plantCell, CanvasTool.dnaHelix,
                  CanvasTool.neuron, CanvasTool.leaf, CanvasTool.microscope,
                ]),
              ])),
            ]),
          ),
        ),
      );

  Widget _shapeGrid(List<CanvasTool> tools) => GridView.builder(
        padding: const EdgeInsets.all(10),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 7,
          mainAxisSpacing: 7,
          childAspectRatio: 1.05,
        ),
        itemCount: tools.length,
        itemBuilder: (_, index) {
          final tool = tools[index];
          return Tooltip(
            message: tool.label,
            child: GestureDetector(
              onDoubleTapDown: (details) => _showInlineToolOptions(tool, details.globalPosition),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _selectTool(tool),
                child: Ink(
                  decoration: BoxDecoration(
                    color: _tool == tool
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _tool == tool
                          ? Theme.of(context).colorScheme.primary
                          : Colors.transparent,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(_toolIcon(tool), size: 25),
                      const SizedBox(height: 5),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Text(
                          tool.label,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10, height: 1.05),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );

  void _positionSelectionTools(Rect? localBounds) {
    if (!mounted || localBounds == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final canvasObject = _canvasRenderKey.currentContext?.findRenderObject();
      final stackObject = _editorStackKey.currentContext?.findRenderObject();
      if (canvasObject is! RenderBox || stackObject is! RenderBox) return;
      final globalPoint = canvasObject.localToGlobal(localBounds.topRight);
      final point = stackObject.globalToLocal(globalPoint);
      const toolbarWidth = 270.0;
      final preferredX = point.dx + 12 + toolbarWidth <= stackObject.size.width
          ? point.dx + 12
          : point.dx - toolbarWidth - 12;
      final nextX = preferredX.clamp(4.0, math.max(4.0, stackObject.size.width - toolbarWidth)).toDouble();
      final nextY = (point.dy - 18).clamp(52.0, math.max(52.0, stackObject.size.height - 76)).toDouble();
      setState(() {
        _selectionToolbarX = nextX;
        _selectionToolbarY = nextY;
      });
    });
  }

  Widget _selectionTools() => Positioned(
        left: _selectionToolbarX < 0 ? 8 : _selectionToolbarX,
        right: _selectionToolbarX < 0 ? 8 : null,
        top: _selectionToolbarY < 0 ? null : _selectionToolbarY,
        bottom: _selectionToolbarY < 0 ? 82 : null,
        child: GestureDetector(
          onPanUpdate: (details) {
            final bounds = MediaQuery.sizeOf(context);
            setState(() {
              final baseX = _selectionToolbarX < 0 ? 8.0 : _selectionToolbarX;
              final baseY = _selectionToolbarY < 0 ? math.max(56.0, bounds.height - 150) : _selectionToolbarY;
              _selectionToolbarX = (baseX + details.delta.dx).clamp(4.0, math.max(4.0, bounds.width - 100));
              _selectionToolbarY = (baseY + details.delta.dy).clamp(52.0, math.max(52.0, bounds.height - 70));
            });
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Material(
                color: Theme.of(context).colorScheme.surface.withValues(alpha: .84),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: const Tooltip(message: 'Drag to move selection tools', child: Icon(Icons.drag_indicator_rounded, size: 18)),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text('$_selected selected', style: const TextStyle(fontWeight: FontWeight.w800)),
                    ),
                    IconButton(onPressed: _selectionColorSheet, icon: const Icon(Icons.palette_outlined), tooltip: 'Color'),
                    IconButton(onPressed: _selectionSizeSheet, icon: const Icon(Icons.line_weight_rounded), tooltip: 'Stroke'),
                    IconButton(onPressed: _canvas.toggleFill, icon: const Icon(Icons.format_color_fill_outlined), tooltip: 'Fill'),
                    IconButton(onPressed: _canvas.bringToFront, icon: const Icon(Icons.vertical_align_top_rounded), tooltip: 'Bring to front'),
                    IconButton(onPressed: _canvas.sendToBack, icon: const Icon(Icons.vertical_align_bottom_rounded), tooltip: 'Send to back'),
                    IconButton(onPressed: () => _canvas.moveSelection(-8, 0), icon: const Icon(Icons.arrow_back_rounded), tooltip: 'Move left'),
                    IconButton(onPressed: () => _canvas.moveSelection(8, 0), icon: const Icon(Icons.arrow_forward_rounded), tooltip: 'Move right'),
                    IconButton(onPressed: () => _canvas.scaleSelection(.9), icon: const Icon(Icons.remove_circle_outline_rounded), tooltip: 'Scale down'),
                    IconButton(onPressed: () => _canvas.scaleSelection(1.1), icon: const Icon(Icons.add_circle_outline_rounded), tooltip: 'Scale up'),
                    IconButton(onPressed: _canvas.duplicateSelection, icon: const Icon(Icons.copy_rounded), tooltip: 'Duplicate'),
                    IconButton(onPressed: _canvas.deleteSelection, icon: const Icon(Icons.delete_outline_rounded), tooltip: 'Delete'),
                    IconButton(onPressed: _canvas.selectAll, icon: const Icon(Icons.select_all_rounded), tooltip: 'Select all'),
                    IconButton(onPressed: _canvas.clearSelection, icon: const Icon(Icons.close_rounded), tooltip: 'Close'),
                  ]),
                ),
              ),
            ),
          ),
        ),
      );

  Map<String, Object?> _clonePage(Map<String, Object?> source) =>
      Map<String, Object?>.from(jsonDecode(jsonEncode(source)) as Map);

  void _insertBlankPage(int index) {
    final target = (index + 1).clamp(0, _pages.length);
    _pages.insert(target, _newPage());
    setState(() => _page = target);
    _scheduleSave();
  }

  void _duplicatePage(int index) {
    final page = _clonePage(_pages[index]);
    page['id'] = DateTime.now().microsecondsSinceEpoch.toString();
    _pages.insert(index + 1, page);
    setState(() => _page = index + 1);
    _scheduleSave();
  }

  void _deletePage(int index) {
    if (_pages.length <= 1) {
      _pages[0] = _newPage();
      setState(() => _page = 0);
    } else {
      _pages.removeAt(index);
      setState(() => _page = _page.clamp(0, _pages.length - 1));
    }
    _scheduleSave();
  }

  void _movePageBy(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _pages.length) return;
    final page = _pages.removeAt(index);
    _pages.insert(target, page);
    setState(() => _page = target);
    _scheduleSave();
  }

  Future<void> _changePageBackground(int index) async {
    const colors = [
      Color(0xffffffff), Color(0xfff4f4f2), Color(0xffeef3f7),
      Color(0xfffff4cf), Color(0xffececec), Color(0xffe7edf9),
      Color(0xfff6e9f3), Color(0xffeaf5ea),
    ];
    final choice = await showModalBottomSheet<Color?>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: colors.map((color) => InkWell(
            onTap: () => Navigator.pop(sheetContext, color),
            child: CircleAvatar(backgroundColor: color, radius: 20),
          )).toList(),
        ),
      ),
    );
    if (choice == null) return;
    setState(() => _pages[index]['paperColor'] = choice.toARGB32());
    _scheduleSave();
  }

  Future<void> _addPageToAnotherNote(int index, {bool cut = false}) async {
    final targets = (await _repo.listAllVisible()).where((n) => n.id != widget.note.id).toList();
    if (targets.isEmpty) return;
    final target = await showDialog<LocalNote?>(
      context: context,
      builder: (dialog) => SimpleDialog(
        title: const Text('Add page to note'),
        children: targets.map((n) => SimpleDialogOption(
          onPressed: () => Navigator.pop(dialog, n),
          child: Text(n.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        )).toList(),
      ),
    );
    if (target == null) return;

    final targetNote = await _repo.get(target.id);
    final data = <String, Object?>{'version': 5, 'pages': <Object?>[]};
    if (targetNote?.contentJson != null) {
      try {
        final decoded = jsonDecode(targetNote!.contentJson!);
        if (decoded is Map) {
          if (decoded['pages'] is List) data['pages'] = List<Object?>.from(decoded['pages'] as List);
          if (decoded['text_delta'] is List) data['text_delta'] = List<Object?>.from(decoded['text_delta'] as List);
        }
      } catch (_) {}
    }
    final pages = List<Object?>.from(data['pages'] as List);
    pages.add(_clonePage(_pages[index]));
    data['pages'] = pages;
    await _repo.saveContent(target.id, data);
    if (cut) _deletePage(index);
  }

  Widget _previewRail() => Positioned(
        left: 0,
        top: 0,
        bottom: 0,
        width: 156,
        child: Material(
          elevation: SnoteThemeController.instance.eInk ? 0 : 12,
          color: Theme.of(context).colorScheme.surface.withValues(alpha: .94),
          child: SafeArea(
            child: Column(children: [
              Row(children: [
                const Expanded(child: Padding(padding: EdgeInsets.only(left: 12), child: Text('Pages', style: TextStyle(fontWeight: FontWeight.w900)))),
                IconButton(onPressed: () => setState(() => _preview = false), icon: const Icon(Icons.close_rounded)),
              ]),
              Expanded(
                child: ReorderableListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _pages.length,
                  onReorder: (oldIndex, newIndex) {
                    if (newIndex > oldIndex) newIndex--;
                    final item = _pages.removeAt(oldIndex);
                    _pages.insert(newIndex, item);
                    setState(() => _page = newIndex);
                    _scheduleSave();
                  },
                  itemBuilder: (_, index) {
                    final page = _pages[index];
                    final templateName = page['template']?.toString();
                    final template = PageTemplate.values.firstWhere(
                      (t) => t.name == templateName,
                      orElse: () => PageTemplate.dotted,
                    );
                    return Padding(
                      key: ValueKey(page['id'].toString()),
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Stack(
                        children: [
                          InkWell(
                            borderRadius: BorderRadius.circular(11),
                            onTap: () => _selectPage(index),
                            child: Container(
                              height: 160,
                              decoration: BoxDecoration(
                                color: _pageColorAt(index),
                                borderRadius: BorderRadius.circular(11),
                                border: Border.all(
                                  color: index == _page ? Theme.of(context).colorScheme.primary : Colors.black12,
                                  width: index == _page ? 2 : 1,
                                ),
                              ),
                              child: _settings.getBool('securePagePreviews')
                                  ? const Center(child: Icon(Icons.lock_outline_rounded, size: 27))
                                  : CustomPaint(
                                      painter: PageBackground(
                                        template: template,
                                        paperColor: _pageColorAt(index),
                                        lineColor: page['lineColor'] is num ? Color((page['lineColor'] as num).toInt()) : const Color(0xffaab2bd),
                                        spacing: page['spacing'] is num ? (page['spacing'] as num).toDouble() : 20,
                                        lineOpacity: page['lineOpacity'] is num ? (page['lineOpacity'] as num).toDouble() : .8,
                                      ),
                                    ),
                            ),
                          ),
                          Positioned(
                            right: 4,
                            bottom: 4,
                            child: Material(
                              color: Theme.of(context).colorScheme.surface.withValues(alpha: .84),
                              borderRadius: BorderRadius.circular(9),
                              child: PopupMenuButton<String>(
                                tooltip: 'Page actions',
                                onSelected: (action) {
                                  switch (action) {
                                    case 'blank': _insertBlankPage(index); break;
                                    case 'duplicate': _duplicatePage(index); break;
                                    case 'background': _changePageBackground(index); break;
                                    case 'up': _movePageBy(index, -1); break;
                                    case 'down': _movePageBy(index, 1); break;
                                    case 'copy': _addPageToAnotherNote(index); break;
                                    case 'cut': _addPageToAnotherNote(index, cut: true); break;
                                    case 'delete': _deletePage(index); break;
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(value: 'blank', child: Text('Insert blank page')),
                                  PopupMenuItem(value: 'duplicate', child: Text('Duplicate page')),
                                  PopupMenuItem(value: 'background', child: Text('Change background')),
                                  PopupMenuItem(value: 'up', child: Text('Move up')),
                                  PopupMenuItem(value: 'down', child: Text('Move down')),
                                  PopupMenuItem(value: 'copy', child: Text('Add to another note')),
                                  PopupMenuItem(value: 'cut', child: Text('Cut to another note')),
                                  PopupMenuItem(value: 'delete', child: Text('Delete page')),
                                ],
                                icon: const Icon(Icons.more_horiz_rounded, size: 18),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 7,
                            bottom: 7,
                            child: Text((index + 1).toString(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              IconButton.filledTonal(
                onPressed: () => _insertBlankPage(_pages.length - 1),
                icon: const Icon(Icons.add_rounded),
                tooltip: 'Insert blank page',
              ),
            ]),
          ),
        ),
      );

  Color _pageColorAt(int index) {
    final v = _pages[index]['paperColor'];
    return v is num ? Color(v.toInt()) : Colors.white;
  }

  Future<void> _paperSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => DefaultTabController(
        length: 3,
        child: StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            _templateSheetRefresh = setSheetState;
            return SizedBox(
              height: MediaQuery.sizeOf(context).height * .88,
              child: Column(children: [
                const TabBar(tabs: [Tab(text: 'Paper'), Tab(text: 'Featured'), Tab(text: 'Custom')]),
                Expanded(child: TabBarView(children: [
                  _paperTab([PageTemplate.grid, PageTemplate.lined, PageTemplate.dotted, PageTemplate.blank, PageTemplate.cornell]),
                  _paperTab([PageTemplate.dotGrid, PageTemplate.isometric, PageTemplate.planner, PageTemplate.music, PageTemplate.checklist, PageTemplate.dark]),
                  _customPaper(),
                ])),
              ]),
            );
          },
        ),
      ),
    ).whenComplete(() => _templateSheetRefresh = null);
  }

  List<double> _paperDimensions(String size) {
    switch (size) {
      case 'A3': return const [297, 420];
      case 'A5': return const [148, 210];
      case 'Letter': return const [215.9, 279.4];
      case 'Legal': return const [215.9, 355.6];
      case 'Infinite': return const [0, 0];
      default: return const [210, 297];
    }
  }

  Widget _paperTab(List<PageTemplate> templates) {
    final sizeKey = pageData['pageSize']?.toString() ?? 'A4';
    final horizontal = pageData['orientation']?.toString() == 'horizontal';
    final dimensions = _paperDimensions(sizeKey);
    return ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text('Paper', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: templates.map((t) => GestureDetector(
              onTap: () => _setTemplate(t),
              child: Container(
                width: 122,
                height: 170,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: _pageColor(), borderRadius: BorderRadius.circular(11), border: Border.all(color: _template() == t ? Theme.of(context).colorScheme.primary : Colors.black12, width: _template() == t ? 2 : 1)),
                child: Column(children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: PageBackground(template: t, paperColor: _pageColor(), lineColor: _pageColor('lineColor', const Color(0xffaab2bd)), spacing: 20, lineOpacity: .8),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                ]),
              ),
            )).toList(),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: const {'A3', 'A4', 'A5', 'Letter', 'Legal', 'Infinite'}.contains(sizeKey) ? sizeKey : 'A4',
            decoration: const InputDecoration(labelText: 'Paper size'),
            items: const ['A3', 'A4', 'A5', 'Letter', 'Legal', 'Infinite'].map((size) =>
              DropdownMenuItem(value: size, child: Text(size == 'Infinite' ? 'Infinite canvas (large workspace)' : size))
            ).toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() => pageData['pageSize'] = value);
              _scheduleSave();
            },
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _infoBox('Width', sizeKey == 'Infinite' ? 'Unlimited workspace' : '${dimensions[horizontal ? 1 : 0]} mm')),
            const SizedBox(width: 10),
            Expanded(child: _infoBox('Height', sizeKey == 'Infinite' ? 'Unlimited workspace' : '${dimensions[horizontal ? 0 : 1]} mm')),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _infoBox('Orientation', pageData['orientation'] == 'horizontal' ? 'Landscape' : 'Portrait', onTap: () {
              setState(() => pageData['orientation'] = pageData['orientation'] == 'horizontal' ? 'vertical' : 'horizontal');
              _scheduleSave();
            })),
            const SizedBox(width: 10),
            Expanded(child: _infoBox('Rule width', '${_pageDouble('lineWidth', .7).toStringAsFixed(2)} px')),
          ]),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            ...[const Color(0xfffffbef), const Color(0xffedf3f8), const Color(0xfff2f2f2), Colors.white, const Color(0xff252525)].map((c) => Padding(
              padding: const EdgeInsets.all(4),
              child: InkWell(onTap: () { setState(() => pageData['paperColor'] = c.toARGB32()); _scheduleSave(); }, child: CircleAvatar(backgroundColor: c, radius: 13)),
            )),
            IconButton(onPressed: _paperColorPicker, icon: const Icon(Icons.colorize_rounded)),
          ]),
          SwitchListTile(contentPadding: EdgeInsets.zero, value: pageData['cornellAssist'] == true, onChanged: (v) { setState(() => pageData['cornellAssist'] = v); _scheduleSave(); }, title: const Text('Add Cornell Assist Line')),
          _range('Line Opacity', _pageDouble('lineOpacity', .85), 0, 1, (v) { setState(() => pageData['lineOpacity'] = v); _scheduleSave(); }),
          _range('Line Width', _pageDouble('lineWidth', .7), .25, 4, (v) { setState(() => pageData['lineWidth'] = v); _scheduleSave(); }),
          _range('Line Spacing', _pageDouble('spacing', 28), 12, 64, (v) { setState(() => pageData['spacing'] = v); _scheduleSave(); }),
          ListTile(
            leading: const Icon(Icons.copy_all_rounded),
            title: const Text('Copy current paper settings to all pages'),
            subtitle: const Text('Immediately copy the selected template, color, orientation and rule spacing.'),
            onTap: _copyCurrentPaperSettingsToAllPages,
          ),
        ],
      );
  }

  void _copyCurrentPaperSettingsToAllPages() {
    const keys = [
      'template',
      'paperColor',
      'lineColor',
      'lineOpacity',
      'lineWidth',
      'spacing',
      'pageSize',
      'orientation',
      'cornellAssist',
    ];
    for (final page in _pages) {
      for (final key in keys) {
        page[key] = pageData[key];
      }
    }
    setState(() {});
    _scheduleSave();
    Navigator.pop(context);
  }

  Widget _customPaper() => ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text('Custom', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          FilledButton.tonal(onPressed: _paperColorPicker, child: const Text('Paper color')),
          FilledButton.tonal(onPressed: _lineColorPicker, child: const Text('Line color')),
          _range('Spacing', _pageDouble('spacing', 28), 12, 64, (v) { setState(() => pageData['spacing'] = v); _scheduleSave(); }),
          _range('Line width', _pageDouble('lineWidth', .7), .25, 4, (v) { setState(() => pageData['lineWidth'] = v); _scheduleSave(); }),
          _range('Line opacity', _pageDouble('lineOpacity', .85), 0, 1, (v) { setState(() => pageData['lineOpacity'] = v); _scheduleSave(); }),
          SwitchListTile(contentPadding: EdgeInsets.zero, value: pageData['cornellAssist'] == true, onChanged: (v) { setState(() => pageData['cornellAssist'] = v); _scheduleSave(); }, title: const Text('Cornell assist line')),
          ListTile(
            leading: const Icon(Icons.copy_all_rounded),
            title: const Text('Copy current paper settings to all pages'),
            subtitle: const Text('Immediately copy the selected template, color, orientation and rule spacing.'),
            onTap: _copyCurrentPaperSettingsToAllPages,
          ),
        ],
      );

  Widget _infoBox(String label, String value, {VoidCallback? onTap}) => InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label), Text(value, style: const TextStyle(fontWeight: FontWeight.w800))]),
        ),
      );

  Widget _range(String label, double value, double min, double max, ValueChanged<double> onChanged) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Text(label + ' ' + value.toStringAsFixed(1)), Slider(value: value.clamp(min, max), min: min, max: max, onChanged: onChanged)],
      );

  void _setTemplate(PageTemplate template) {
    setState(() {
      pageData['template'] = template.name;
      pageData['templateUpdatedAt'] = DateTime.now().millisecondsSinceEpoch;
    });
    // The modal sheet is a separate route; update it explicitly so the
    // selected template, preview card and active canvas stay in sync.
    _templateSheetRefresh?.call(() {});
    _scheduleSave();
  }

  Future<void> _paperColorPicker() async {
    var color = _pageColor();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialog) => AlertDialog(
          title: const Text('Paper color'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 70, height: 70, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14), border: Border.all())),
            Slider(value: color.red.toDouble(), min: 0, max: 255, onChanged: (v) => setDialog(() => color = color.withRed(v.round()))),
            Slider(value: color.green.toDouble(), min: 0, max: 255, onChanged: (v) => setDialog(() => color = color.withGreen(v.round()))),
            Slider(value: color.blue.toDouble(), min: 0, max: 255, onChanged: (v) => setDialog(() => color = color.withBlue(v.round()))),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(onPressed: () { setState(() => pageData['paperColor'] = color.toARGB32()); _scheduleSave(); Navigator.pop(dialogContext); }, child: const Text('Use')),
          ],
        ),
      ),
    );
  }

  Future<void> _lineColorPicker() async {
    final colors = [Colors.blueGrey, Colors.grey, Colors.red, Colors.orange, Colors.green, Colors.blue, Colors.purple, Colors.black];
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Line color'),
        content: Wrap(spacing: 8, runSpacing: 8, children: colors.map((c) => InkWell(onTap: () { setState(() => pageData['lineColor'] = c.toARGB32()); _scheduleSave(); Navigator.pop(dialogContext); }, child: CircleAvatar(backgroundColor: c))).toList()),
      ),
    );
  }

  List<Color> _spectrumColorGrid() {
    final colors = <Color>[];
    // A 13-column palette: grayscale at the left and a smooth hue spectrum
    // with progressively stronger saturation and lower value down the grid.
    for (var row = 0; row < 10; row++) {
      final grey = (255 * (1 - row / 9)).round().clamp(0, 255);
      colors.add(Color.fromARGB(255, grey, grey, grey));
      for (var column = 0; column < 12; column++) {
        final hue = column * 30.0;
        final saturation = (.12 + row * .095).clamp(0.0, 1.0).toDouble();
        final value = (1.0 - row * .075).clamp(.22, 1.0).toDouble();
        colors.add(HSVColor.fromAHSV(1, hue, saturation, value).toColor());
      }
    }
    return colors;
  }

  Future<void> _colorSheet() async {
    var color = _toolColorOverrides[_tool.name] ?? _penColor;
    var paletteOpacity = _opacity;
    var applyColorToFill = _fillColor != null;
    var hexText = color.toARGB32().toRadixString(16).substring(2).toUpperCase();
    final hexController = TextEditingController(text: '#$hexText');
    var useEyedropper = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialog) {
          void commitPalette(Color nextColor, double nextOpacity, bool useForFill) {
            setState(() {
              color = nextColor;
              _penColor = nextColor;
              _toolColorOverrides[_tool.name] = nextColor;
              _opacity = nextOpacity;
              _fill = useForFill;
              _fillColor = useForFill ? nextColor : null;
            });
            unawaited(_settings.setDouble('penOpacity', nextOpacity));
            unawaited(_settings.setString('toolColors', jsonEncode({
              for (final entry in _toolColorOverrides.entries) entry.key: entry.value.toARGB32(),
            })));
          }

          void updateColor(Color next) {
            setDialog(() {
              color = next;
              hexText = '#${next.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
              hexController.value = TextEditingValue(
                text: hexText,
                selection: TextSelection.collapsed(offset: hexText.length),
              );
            });
            commitPalette(next, paletteOpacity, applyColorToFill);
          }

          final palette = _spectrumColorGrid();
          final hsv = HSVColor.fromColor(color);
          return AlertDialog(
            title: const Text('Color palette'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Theme.of(context).colorScheme.outline),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: hexController,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            labelText: 'HEX color',
                            hintText: '#313131',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (value) {
                            final normalized = value.trim().replaceFirst('#', '');
                            if (normalized.length == 6) {
                              final parsed = int.tryParse(normalized, radix: 16);
                              if (parsed != null) {
                                setDialog(() => color = Color(0xff000000 | parsed));
                              }
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        tooltip: 'Darken color',
                        onPressed: () => updateColor(HSVColor.fromColor(color).withValue((hsv.value - .08).clamp(.08, 1).toDouble()).toColor()),
                        icon: const Icon(Icons.remove_circle_outline_rounded),
                      ),
                      IconButton(
                        tooltip: 'Lighten color',
                        onPressed: () => updateColor(HSVColor.fromColor(color).withValue((hsv.value + .08).clamp(.08, 1).toDouble()).toColor()),
                        icon: const Icon(Icons.add_circle_outline_rounded),
                      ),
                      IconButton(
                        tooltip: 'Sample color from this page',
                        onPressed: () {
                          useEyedropper = true;
                          Navigator.pop(dialogContext);
                        },
                        icon: const Icon(Icons.colorize_rounded),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: palette.length,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 13,
                        crossAxisSpacing: 2,
                        mainAxisSpacing: 2,
                        childAspectRatio: 1.05,
                      ),
                      itemBuilder: (_, index) {
                        final choice = palette[index];
                        final selected = choice.toARGB32() == color.toARGB32();
                        return Tooltip(
                          message: '#${choice.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
                          child: InkWell(
                            onTap: () => updateColor(choice),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: choice,
                                borderRadius: BorderRadius.circular(3),
                                border: Border.all(
                                  color: selected ? Theme.of(context).colorScheme.primary : Colors.black12,
                                  width: selected ? 3 : 1,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: applyColorToFill,
                      onChanged: (value) {
                        setDialog(() => applyColorToFill = value);
                        commitPalette(color, paletteOpacity, value);
                      },
                      title: const Text('Use this color for shape fill'),
                    ),
                    Text('Opacity: ' + (paletteOpacity * 100).round().toString() + '%', style: const TextStyle(fontWeight: FontWeight.w800)),
                    Slider(
                      value: paletteOpacity.clamp(.05, 1).toDouble(),
                      min: .05,
                      max: 1,
                      divisions: 19,
                      onChanged: (value) {
                        setDialog(() => paletteOpacity = value);
                        commitPalette(color, value, applyColorToFill);
                      },
                    ),
                    const Text('Recent colors', style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: _penPalette.map((choice) => InkWell(
                        onTap: () => updateColor(choice),
                        borderRadius: BorderRadius.circular(22),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: choice,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: choice.toARGB32() == color.toARGB32()
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.black26,
                              width: choice.toARGB32() == color.toARGB32() ? 3 : 1,
                            ),
                          ),
                        ),
                      )).toList(),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Done')),
            ],
          );
        },
      ),
    ).whenComplete(() {
      hexController.dispose();
      if (useEyedropper && mounted) {
        setState(() => _eyedropperActive = true);
      }
    });
  }

  Offset _toolbarOptionsAnchor() {
    final object = _toolbarKey.currentContext?.findRenderObject();
    if (object is RenderBox) {
      final origin = object.localToGlobal(Offset.zero);
      return origin + Offset(object.size.width / 2, object.size.height / 2);
    }
    return const Offset(72, 120);
  }

  Future<void> _styleSheet([CanvasTool? requestedTool]) async {
    final target = requestedTool ?? _tool;
    var size = _toolSizeOverrides[target.name] ?? _defaultToolSize(target);
    var opacity = _opacity;
    var fill = _fill;
    var sides = _sides;
    var color = _toolColorOverrides[target.name] ?? _defaultToolColor(target);
    var dashed = _toolDashedOverrides[target.name] ?? _dashed;
    var curve = _settings.getString('pressureCurve');
    var exponent = _settings.getDouble('pressureExponent');
    var lassoStyle = _settings.getString('lassoStyle');
    var eraserMode = _settings.getString('eraserMode');
    var pressureErase = _settings.getBool('pressureErase');
    var pressureEraseArea = _settings.getBool('pressureEraseArea');

    final anchor = _toolOptionsAnchorPosition ?? _toolbarOptionsAnchor();
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '${target.label} options',
      barrierColor: Colors.black12,
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final screen = MediaQuery.sizeOf(dialogContext);
        final popupWidth = math.min(360.0, screen.width - 16);
        final popupHeight = math.min(680.0, screen.height * .82);
        final placeRight = anchor.dx < screen.width / 2;
        final left = (placeRight ? anchor.dx + 28 : anchor.dx - popupWidth - 12)
            .clamp(8.0, math.max(8.0, screen.width - popupWidth - 8))
            .toDouble();
        final requestedTop = anchor.dy > screen.height * .62
            ? anchor.dy - popupHeight
            : anchor.dy + 8;
        final top = requestedTop
            .clamp(52.0, math.max(52.0, screen.height - popupHeight - 8))
            .toDouble();
        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              width: popupWidth,
              height: popupHeight,
              child: Material(
                elevation: 18,
                color: Theme.of(dialogContext).colorScheme.surface,
                borderRadius: BorderRadius.circular(18),
                clipBehavior: Clip.antiAlias,
                child: StatefulBuilder(
                  builder: (_, setModal) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${target.label} options', style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Text('Stroke size: ${size.toStringAsFixed(1)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  Slider(value: size.clamp(.5, 60), min: .5, max: 60, divisions: 119, onChanged: (v) {
                    setModal(() => size = v);
                    unawaited(_commitToolOptions(target: target, size: v, color: color, opacity: opacity, fill: fill, dashed: dashed, sides: sides));
                  }),
                  Text('Opacity: ${(opacity * 100).round()}%'),
                  Slider(value: opacity.clamp(.05, 1), min: .05, max: 1, onChanged: (v) {
                    setModal(() => opacity = v);
                    unawaited(_commitToolOptions(target: target, size: size, color: color, opacity: v, fill: fill, dashed: dashed, sides: sides));
                  }),
                  const SizedBox(height: 4),
                  const Text('Color', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _penPalette.map((choice) => InkWell(
                      onTap: () {
                        setModal(() => color = choice);
                        unawaited(_commitToolOptions(target: target, size: size, color: choice, opacity: opacity, fill: fill, dashed: dashed, sides: sides));
                      },
                      borderRadius: BorderRadius.circular(30),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: choice,
                          shape: BoxShape.circle,
                          border: Border.all(color: choice.toARGB32() == color.toARGB32() ? Theme.of(context).colorScheme.primary : Colors.black26, width: choice.toARGB32() == color.toARGB32() ? 3 : 1),
                        ),
                      ),
                    )).toList(),
                  ),
                  const SizedBox(height: 10),
                  if (target == CanvasTool.eraser || target == CanvasTool.pixelEraser) ...[
                    const Text('Erasing mode', style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'stroke', label: Text('Stroke eraser'), icon: Icon(Icons.gesture_rounded)),
                        ButtonSegment(value: 'pixel', label: Text('Pixel eraser'), icon: Icon(Icons.auto_fix_high_rounded)),
                      ],
                      selected: {eraserMode},
                      onSelectionChanged: (values) {
                        setModal(() => eraserMode = values.first);
                        unawaited(_settings.setString('eraserMode', values.first));
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: pressureErase,
                      onChanged: (value) {
                        setModal(() => pressureErase = value);
                        unawaited(_settings.setBool('pressureErase', value));
                      },
                      title: const Text('Pressure-responsive radius'),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: pressureEraseArea,
                      onChanged: (value) {
                        setModal(() => pressureEraseArea = value);
                        unawaited(_settings.setBool('pressureEraseArea', value));
                      },
                      title: const Text('Increase radius with pressure'),
                    ),
                  ],
                  if (target == CanvasTool.lasso) ...[
                    const SizedBox(height: 8),
                    const Text('Selection outline', style: TextStyle(fontWeight: FontWeight.w800)),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'solid', label: Text('Solid'), icon: Icon(Icons.horizontal_rule_rounded)),
                        ButtonSegment(value: 'dashed', label: Text('Dashed'), icon: Icon(Icons.more_horiz_rounded)),
                      ],
                      selected: {lassoStyle},
                      onSelectionChanged: (values) {
                        setModal(() => lassoStyle = values.first);
                        unawaited(_settings.setString('lassoStyle', values.first));
                      },
                    ),
                    const SizedBox(height: 6),
                    const Text('Draw around content with the lasso, then drag the selection toolbar to place its options wherever you need them.'),
                  ] else if (target.isShape) ...[
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: dashed,
                      onChanged: (value) {
                        setModal(() => dashed = value);
                        unawaited(_commitToolOptions(target: target, size: size, color: color, opacity: opacity, fill: fill, dashed: value, sides: sides));
                      },
                      title: const Text('Dashed outline'),
                    ),
                  ],
                  if (target.isShape)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: fill,
                      onChanged: (value) {
                        setModal(() => fill = value);
                        unawaited(_commitToolOptions(target: target, size: size, color: color, opacity: opacity, fill: value, dashed: dashed, sides: sides));
                      },
                      title: const Text('Fill shape'),
                    ),
                  if (target == CanvasTool.customPolygon)
                    ListTile(
                      title: Text('Polygon sides: $sides'),
                      subtitle: Slider(value: sides.toDouble(), min: 3, max: 24, divisions: 21, onChanged: (v) {
                          setModal(() => sides = v.round());
                          unawaited(_commitToolOptions(target: target, size: size, color: color, opacity: opacity, fill: fill, dashed: dashed, sides: v.round()));
                        }),
                    ),
                  if (target.isPen) ...[
                    const SizedBox(height: 6),
                    const Text('Pressure response', style: TextStyle(fontWeight: FontWeight.w800)),
                    DropdownButtonFormField<String>(
                      value: curve,
                      items: const [
                        DropdownMenuItem(value: 'soft', child: Text('Soft')),
                        DropdownMenuItem(value: 'linear', child: Text('Linear')),
                        DropdownMenuItem(value: 'firm', child: Text('Firm')),
                        DropdownMenuItem(value: 'custom', child: Text('Custom')),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setModal(() => curve = value);
                        unawaited(_settings.setString('pressureCurve', value));
                        setState(() {});
                      },
                    ),
                    if (curve == 'custom')
                      ListTile(
                        title: Text('Custom pressure curve: ${exponent.toStringAsFixed(2)}'),
                        subtitle: Slider(value: exponent.clamp(.35, 2.5), min: .35, max: 2.5, onChanged: (v) {
                          setModal(() => exponent = v);
                          unawaited(_settings.setDouble('pressureExponent', v));
                          setState(() {});
                        }),
                      ),
                  ],
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Done'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _stickers() async {
    const categories = <String, List<String>>{
      'Study': ['📚','📖','📝','📓','📒','📔','📕','📗','📘','📙','🗂️','🗒️','📌','✅','❌','⭐','💡','🎯','🧠','🔖','📅','🗓️'],
      'Science': ['🔬','🧪','🧬','⚗️','🧫','🛰️','🌍','🪐','☄️','📐','📏','🧮','💻','🔒','🫀','🫁','🦴','🧑‍🔬'],
      'Nature': ['☀️','🌙','🌈','🌱','🌿','🍀','🌸','🌻','🍁','🪴','🐝','🦋','🌌','💎'],
      'Symbols': ['⚠️','❗','❓','‼️','⁉️','➕','➖','✖️','➗','⭕','☑️','☒','🔘','❇️','✳️','❎','💠','⬛','⬜','🔷','🔶','🔺','🔻'],
      'Arrows & Math': ['↗️','↘️','↔️','↕️','🔁','🔄','🔀','📈','📉','📊','🧭','🧩','⚙️','🛠️','📐','📏','🧮','➕','➖','✖️','➗'],
      'Fun': ['⭐','❤️','😊','👍','✨','🎉','☕','🔥','🚀','🎨','🎼','🎵','🎹','🏆','🥇','🥈','🥉','🚩','🏁','💯','💬','🗯️','💭','🟢','🟡','🟠','🔵','🟣','🟤','🩷','🩵','🩶','💜','💙','💚','💛','🧡','🤍','🖤','🤎'],
    };
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => DefaultTabController(
        length: categories.length,
        child: SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * .78,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(18, 4, 18, 10),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Sticker library', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
                  ),
                ),
                TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [for (final name in categories.keys) Tab(text: name)],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      for (final items in categories.values)
                        GridView.builder(
                          padding: const EdgeInsets.all(18),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 6,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                          itemCount: items.length,
                          itemBuilder: (_, index) => InkWell(
                            onTap: () {
                              setState(() {
                                _tool = CanvasTool.sticker;
                                _sticker = items[index];
                              });
                              Navigator.pop(sheetContext);
                            },
                            child: Center(child: Text(items[index], style: const TextStyle(fontSize: 30))),
                          ),
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
  }
}

class _StudyTimerDialog extends StatefulWidget {
  const _StudyTimerDialog();

  @override
  State<_StudyTimerDialog> createState() => _StudyTimerDialogState();
}

class _StudyTimerDialogState extends State<_StudyTimerDialog> {
  final Stopwatch _watch = Stopwatch();
  Timer? _ticker;

  String get _clock {
    final elapsed = _watch.elapsed;
    final hours = elapsed.inHours.toString().padLeft(2, '0');
    final minutes = (elapsed.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return hours + ':' + minutes + ':' + seconds;
  }

  void _startPause() {
    setState(() {
      if (_watch.isRunning) {
        _watch.stop();
        _ticker?.cancel();
        _ticker = null;
      } else {
        _watch.start();
        _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() {});
        });
      }
    });
  }

  void _reset() {
    setState(() {
      _watch
        ..stop()
        ..reset();
      _ticker?.cancel();
      _ticker = null;
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _watch.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final running = _watch.isRunning;
    return AlertDialog(
      title: const Text('Study timer'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(running ? Icons.timer_rounded : Icons.hourglass_empty_rounded, size: 42, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(_clock, style: Theme.of(context).textTheme.displaySmall?.copyWith(fontFeatures: const [ui.FontFeature.tabularFigures()], fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(running ? 'Study session in progress' : 'Session paused', style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
      actions: [
        TextButton.icon(onPressed: _reset, icon: const Icon(Icons.restart_alt_rounded), label: const Text('Reset')),
        FilledButton.icon(
          onPressed: _startPause,
          icon: Icon(running ? Icons.pause_rounded : Icons.play_arrow_rounded),
          label: Text(running ? 'Pause' : 'Start'),
        ),
      ],
    );
  }
}

class _CalculatorParser {
  _CalculatorParser(this.source);
  final String source;
  int _cursor = 0;

  double parse() {
    final value = _sum();
    _skipSpaces();
    if (_cursor != source.length) throw const FormatException('Unexpected input');
    if (!value.isFinite) throw const FormatException('Result is not finite');
    return value;
  }

  double _sum() {
    var value = _product();
    while (true) {
      if (_take('+')) {
        value += _product();
      } else if (_take('-')) {
        value -= _product();
      } else {
        return value;
      }
    }
  }

  double _product() {
    var value = _power();
    while (true) {
      if (_take('*')) {
        value *= _power();
      } else if (_take('/')) {
        final divisor = _power();
        if (divisor == 0) throw const FormatException('Division by zero');
        value /= divisor;
      } else if (_take('%')) {
        final divisor = _power();
        if (divisor == 0) throw const FormatException('Division by zero');
        value %= divisor;
      } else {
        return value;
      }
    }
  }

  double _power() {
    final base = _unary();
    if (_take('^')) return math.pow(base, _power()).toDouble();
    return base;
  }

  double _unary() {
    if (_take('+')) return _unary();
    if (_take('-')) return -_unary();
    return _primary();
  }

  double _primary() {
    _skipSpaces();
    if (_take('(')) {
      final value = _sum();
      if (!_take(')')) throw const FormatException('Missing closing parenthesis');
      return value;
    }
    final identifier = RegExp(r'[a-zA-Z]+').matchAsPrefix(source.substring(_cursor));
    if (identifier != null) {
      final name = identifier.group(0)!.toLowerCase();
      _cursor += identifier.group(0)!.length;
      if (name == 'pi') return math.pi;
      if (name == 'e') return math.e;
      if (!_take('(')) throw const FormatException('Function needs parentheses');
      final value = _sum();
      if (!_take(')')) throw const FormatException('Missing closing parenthesis');
      switch (name) {
        case 'sin': return math.sin(value);
        case 'cos': return math.cos(value);
        case 'tan': return math.tan(value);
        case 'sqrt': if (value < 0) throw const FormatException('Negative square root'); return math.sqrt(value);
        case 'abs': return value.abs();
        case 'ln': if (value <= 0) throw const FormatException('Invalid logarithm'); return math.log(value);
        case 'log': if (value <= 0) throw const FormatException('Invalid logarithm'); return math.log(value) / math.ln10;
        default: throw const FormatException('Unknown function');
      }
    }
    final number = RegExp(r'(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?').matchAsPrefix(source.substring(_cursor));
    if (number == null) throw const FormatException('Expected a number');
    _cursor += number.group(0)!.length;
    return double.parse(number.group(0)!);
  }

  bool _take(String token) {
    _skipSpaces();
    if (!source.startsWith(token, _cursor)) return false;
    _cursor += token.length;
    return true;
  }

  void _skipSpaces() {
    while (_cursor < source.length && source[_cursor].trim().isEmpty) {
      _cursor++;
    }
  }
}
