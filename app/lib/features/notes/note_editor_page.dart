import 'dart:math' as math;
import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart' as pdfcore;
import 'package:pdf/widgets.dart' as pw;

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

class NoteEditorPage extends StatefulWidget {
  final LocalNote note;
  const NoteEditorPage({super.key, required this.note});
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
  final Map<String, double> _toolSizeOverrides = <String, double>{};
  final Map<String, Color> _toolColorOverrides = <String, Color>{};
  final Map<String, bool> _toolDashedOverrides = <String, bool>{};
  double _pageChangerX = -1;
  double _pageChangerY = 130;
  double _selectionToolbarX = -1;
  double _selectionToolbarY = -1;
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
  bool _toolbar = true;
  bool _docked = false;
  String _dockSide = 'bottom';
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
  String? _sticker;
  int _selected = 0;
  Timer? _saveTimer;
  bool _savePending = false;
  bool _saveInFlight = false;
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
    if (note?.contentJson != null) {
      try {
        final json = jsonDecode(note!.contentJson!);
        if (json is Map<String, dynamic>) {
          final raw = json['pages'];
          if (raw is List) {
            for (final item in raw) {
              if (item is Map) parsed.add(_normalize(item.cast<String, Object?>()));
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
      'cornellAssist': inheritedCornell,
      'orientation': inheritedOrientation,
      'strokes': <Object?>[],
      'images': <Object?>[],
    };
  }

  void _restoreToolbar() {
    final x = pageData['toolbarX'];
    final y = pageData['toolbarY'];
    final dock = pageData['toolbarDock']?.toString();
    _docked = const {'left', 'right', 'top', 'bottom'}.contains(dock);
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

  void _selectTool(CanvasTool tool) {
    setState(() {
      _tool = tool;
      _penSize = _toolSizeOverrides[tool.name] ?? _penSize;
      _penColor = _toolColorOverrides[tool.name] ?? _penColor;
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
            children: [
              Positioned.fill(
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
              if (!_full) _movablePageChanger(),
              if (_preview && !_full) _previewRail(),
              if (_toolbar && _draw) _toolbarWidget(),
              if (_shapePanel && !_full) _shapePanelWidget(),
              if (!_toolbar && !_full) _toolbarOpen(),
              if (_full) _fullExit(),
              if (_selected > 0) _selectionTools(),
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
    final horizontal = pageData['orientation']?.toString() == 'horizontal';
    final child = Center(
      child: AspectRatio(
        aspectRatio: horizontal ? 297 / 210 : 210 / 297,
        child: Material(
          elevation: SnoteThemeController.instance.eInk ? 0 : 4,
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
                    cornellAssist: pageData['cornellAssist'] == true,
                  ),
                ),
              ),
              if (_draw)
                RepaintBoundary(
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
                    if (mounted && count != _selected) setState(() => _selected = count);
                  },
                  autoRecognition: _settings.getBool('autoRecognition'),
                  onEraserMiss: _settings.getBool('eraseClickSwitch') && _tool == CanvasTool.eraser
                      ? () => _selectTool(CanvasTool.ballpoint)
                      : null,
                  onStylusDoubleTap: _settings.getBool('stylusDoubleTapUndo') ? _canvas.undo : null,
                  pressureErase: _settings.getBool('pressureErase'),
                  pressureEraseArea: _settings.getBool('pressureEraseArea'),
                  pressureEraseThreshold: _settings.getDouble('pressureEraseThreshold'),
                  eraseWithStylusButton: true,
                  eraseMark: true,
                  eraserMode: _settings.getString('eraserMode'),
                  stylusHoldActions: _settings.getBool('stylusHoldActions'),
                  dashed: _dashed || (_toolDashedOverrides[_tool.name] ?? false) || (_tool == CanvasTool.lasso && _settings.getString('lassoStyle') == 'dashed'),
                  fillColor: _fillColor,
                  smoothing: _settings.getDouble('strokeSmoothing'),
                  showPerformanceOverlay: const bool.fromEnvironment('SNOTE_PERF'),
                ),
              )
              else
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: QuillEditor(
                    focusNode: _focus,
                    scrollController: _scroll,
                    controller: _quill,
                    config: const QuillEditorConfig(placeholder: 'Start writing…'),
                  ),
                ),
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (_, constraints) => Stack(
                    clipBehavior: Clip.none,
                    children: _pageImages.map((image) => _pageImageItem(
                      image, constraints.maxWidth, constraints.maxHeight,
                    )).toList(),
                  ),
                ),
              ),
              if (_settings.getBool('showPageNumbers'))
                Positioned(right: 10, bottom: 8, child: Text((_page + 1).toString(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800))),
            ],
          ),
        ),
      ),
    );
    return RepaintBoundary(
      key: _pageCaptureKey,
      child: NotebookViewport(
        allowSingleFingerPan: _pan,
        minScale: .5,
        maxScale: 4,
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
        ]),
      ),
    );
    if (source == null) return;
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
    _calculatorInput.text = '0';
    _calculatorResult = '0';
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (_, setModal) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Align(alignment: Alignment.centerLeft, child: Text('Calculator', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900))),
                const SizedBox(height: 8),
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
                    child: Text('= $_calculatorResult', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  ),
                ),
                GridView.count(
                  crossAxisCount: 4,
                  shrinkWrap: true,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                  childAspectRatio: 1.7,
                  physics: const NeverScrollableScrollPhysics(),
                  children: keys.map((key) => FilledButton.tonal(
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
                    child: Text(key, style: const TextStyle(fontWeight: FontWeight.w800)),
                  )).toList(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PageTemplate _template() {
    final name = pageData['template']?.toString();
    return PageTemplate.values.firstWhere((v) => v.name == name, orElse: () => PageTemplate.dotted);
  }

  Color _pageColor([String key = 'paperColor', Color fallback = Colors.white]) {
    final v = pageData[key];
    return v is num ? Color(v.toInt()) : fallback;
  }

  double _pageDouble(String key, double fallback) {
    final v = pageData[key];
    return v is num ? v.toDouble() : fallback;
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
                  onSubmitted: (_) => _save(force: true),
                ),
              ),
              _compactAction(tooltip: 'Save note', icon: Icons.save_outlined, onPressed: () => _save(force: true)),
              _compactAction(tooltip: 'Pages / thumbnails', icon: Icons.view_sidebar_outlined, onPressed: () => setState(() => _preview = !_preview)),
              _compactAction(tooltip: 'Page templates', icon: Icons.grid_4x4_rounded, onPressed: _paperSheet),
              _compactAction(tooltip: 'Shapes and diagrams', icon: Icons.category_outlined, onPressed: () => setState(() => _shapePanel = !_shapePanel)),
              _compactAction(tooltip: _draw ? 'Text mode' : 'Handwriting mode', icon: _draw ? Icons.text_fields_rounded : Icons.draw_rounded, onPressed: () => setState(() => _draw = !_draw)),
              _compactAction(tooltip: 'Lock note', icon: _locked ? Icons.lock_rounded : Icons.lock_outline_rounded, onPressed: _lockNote),
              _compactAction(tooltip: 'Fullscreen', icon: _full ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded, onPressed: _toggleFullscreen),
              _compactAction(tooltip: 'Settings', icon: Icons.settings_outlined, onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage())).then((_) => _keepAwake())),
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

  Widget _fixedLeftRail() {
    final tools = <CanvasTool>[
      CanvasTool.ballpoint, CanvasTool.fountain, CanvasTool.pencil,
      CanvasTool.highlighter, CanvasTool.marker, CanvasTool.brush,
      CanvasTool.eraser, CanvasTool.pixelEraser, CanvasTool.lasso,
      CanvasTool.line, CanvasTool.arrow, CanvasTool.rectangle,
      CanvasTool.ellipse, CanvasTool.triangle, CanvasTool.diamond,
      CanvasTool.hexagon, CanvasTool.star,
    ];
    return Positioned(
      left: 0,
      top: 46,
      bottom: 0,
      width: 44,
      child: Material(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: .96),
        child: SafeArea(
          top: false,
          bottom: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Pens and erasers above; the lasso appears once below the
              // text/shapes shortcuts, like the reference tool rail.
              for (final tool in tools.take(8))
                _railToolButton(tool),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                child: Divider(height: 1),
              ),
              _railButton('Text box', Icons.text_fields_rounded, () => setState(() => _draw = false)),
              _railButton('Shapes and diagrams', Icons.category_outlined, () => setState(() => _shapePanel = !_shapePanel)),
              _railToolButton(CanvasTool.lasso),
              for (final tool in tools.skip(9))
                _railToolButton(tool),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                child: Divider(height: 1),
              ),
              for (final color in _penPalette.take(16))
                Tooltip(
                  message: 'Pen color: #${color.value.toRadixString(16).padLeft(8, '0')}',
                  child: InkWell(
                    onTap: () => setState(() => _penColor = color),
                    child: SizedBox(
                    width: 34,
                    height: 25,
                    child: Center(
                      child: Container(
                        width: _penColor.value == color.value ? 19 : 14,
                        height: _penColor.value == color.value ? 19 : 14,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(color: _penColor.value == color.value ? Theme.of(context).colorScheme.primary : Colors.black26, width: _penColor.value == color.value ? 2 : 1),
                        ),
                      ),
                    ),
                  ),
                  ),
                ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                child: Divider(height: 1),
              ),
              _railButton('Paper template', Icons.grid_4x4_rounded, _paperSheet),
              _railButton('Floating toolbox', Icons.drag_indicator_rounded, () => setState(() => _toolbar = !_toolbar)),
              _railButton('Pan and zoom', Icons.pan_tool_outlined, () => setState(() => _pan = !_pan)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _railToolButton(CanvasTool tool) => _railButton(
        tool.label,
        _toolIcon(tool),
        () => _selectTool(tool),
        selected: _tool == tool,
      );

  Widget _railButton(String tooltip, IconData icon, VoidCallback onPressed, {bool selected = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: IconButton(
          onPressed: onPressed,
          tooltip: tooltip,
          constraints: const BoxConstraints.tightFor(width: 38, height: 36),
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          style: IconButton.styleFrom(
            backgroundColor: selected ? Theme.of(context).colorScheme.primaryContainer : null,
            foregroundColor: selected ? Theme.of(context).colorScheme.primary : null,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
          ),
          icon: Icon(icon, size: 20),
        ),
      );

  Widget _fixedRightRail() => Positioned(
        right: 0,
        top: 46,
        bottom: 0,
        width: 42,
        child: Material(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: .96),
          child: SafeArea(
            top: false,
            bottom: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _railButton('Previous page', Icons.keyboard_arrow_up_rounded, _previousPage),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Text('${_page + 1}/${_pages.length}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
                ),
                _railButton('Next page', Icons.keyboard_arrow_down_rounded, _nextPage),
                _railButton('Add page', Icons.add_rounded, _addPage),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 7, vertical: 3), child: Divider(height: 1)),
                _railButton('Page thumbnails and reorder', Icons.layers_outlined, () => setState(() => _preview = !_preview)),
                _railButton('Duplicate page', Icons.content_copy_rounded, () => _duplicatePage(_page)),
                _railButton('Delete page', Icons.delete_outline_rounded, () => _confirmDeletePage()),
                _railButton('Templates', Icons.grid_on_rounded, _paperSheet),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 7, vertical: 3), child: Divider(height: 1)),
                _railButton('Selected object: duplicate', Icons.copy_rounded, _canvas.duplicateSelection),
                _railButton('Selected object: delete', Icons.delete_outline_rounded, _canvas.deleteSelection),
                _railButton('Clear selection', Icons.close_rounded, _canvas.clearSelection),
              ]),
            ),
          ),
        ),
      );

  Future<void> _confirmDeletePage() async {
    if (_pages.length <= 1) {
      _deletePage(0);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete page?'),
        content: Text('Delete page ${_page + 1}? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true) _deletePage(_page);
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
    final size = MediaQuery.sizeOf(context);
    if (_docked) {
      final vertical = _dockSide == 'left' || _dockSide == 'right';
      return Positioned(
        left: _dockSide == 'left' ? 0 : null,
        right: _dockSide == 'right' ? 0 : null,
        top: _dockSide == 'top' ? (_full ? 0 : 46) : null,
        bottom: _dockSide == 'bottom' ? 0 : null,
        child: SafeArea(child: _toolbarSurface(_toolbarContent(vertical ? Axis.vertical : Axis.horizontal, docked: true))),
      );
    }

    return ValueListenableBuilder<Offset>(
      valueListenable: _toolbarOffset,
      builder: (_, offset, child) {
        final y = offset.dy == 0 ? size.height - 112 : offset.dy;
        return Positioned(
          left: offset.dx.clamp(8, math.max(8, size.width - 160)),
          top: y.clamp(60, math.max(60, size.height - 92)),
          child: GestureDetector(
            onPanUpdate: (d) {
              _toolbarX = (_toolbarX + d.delta.dx).clamp(8, math.max(8, size.width - 160));
              _toolbarY = ((_toolbarY == 0 ? y : _toolbarY) + d.delta.dy).clamp(60, math.max(60, size.height - 92));
              _toolbarOffset.value = Offset(_toolbarX, _toolbarY);
            },
            onPanEnd: (_) => _snapToolbar(size),
            child: child,
          ),
        );
      },
      child: _toolbarSurface(_toolbarContent(Axis.horizontal, docked: false)),
    );
  }

  Widget _toolbarSurface(Widget child) {
    final blur = SnoteThemeController.instance.eInk ? 0.0 : 12.0;
    return ClipRRect(
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
    ];
    final pencaseTools = defaultTools.where((tool) => configured.contains(tool.name)).toList();

    final items = <Widget>[
      GestureDetector(
        onPanUpdate: docked
            ? (_) {
                if (!mounted) return;
                setState(() {
                  _docked = false;
                  // Undock into the usable canvas area, not underneath the
                  // fixed left toolbar.
                  _toolbarX = 16;
                  _toolbarY = 100;
                  _toolbarOffset.value = Offset(_toolbarX, _toolbarY);
                });
              }
            : null,
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
      IconButton(
        onPressed: _colorSheet,
        icon: Icon(Icons.circle, color: _toolColorOverrides[_tool.name] ?? _penColor, size: 22),
        tooltip: 'Current pen color',
      ),
      IconButton(
        onPressed: _insertScreenshot,
        icon: const Icon(Icons.add_photo_alternate_outlined),
        tooltip: 'Insert screenshot or image',
      ),
      IconButton(
        onPressed: _pdfExporting ? null : _exportPagePdf,
        icon: const Icon(Icons.picture_as_pdf_outlined),
        tooltip: 'Save current page as PDF',
      ),
      IconButton(
        onPressed: _calculatorSheet,
        icon: const Icon(Icons.calculate_outlined),
        tooltip: 'Calculator',
      ),
      IconButton(
        onPressed: _styleSheet,
        icon: const Icon(Icons.tune_rounded),
        tooltip: 'Tool style',
      ),
      IconButton(
        onPressed: _pencaseSheet,
        icon: const Icon(Icons.inventory_2_outlined),
        tooltip: 'Pencase',
      ),
      IconButton(
        onPressed: () => setState(() => _pan = !_pan),
        icon: Icon(_pan ? Icons.pan_tool_rounded : Icons.pan_tool_outlined),
        tooltip: 'Pan and zoom',
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
      CanvasTool.dashedLine: Icons.more_horiz_rounded,
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

  void _snapToolbar(Size size) {
    final map = {
      'left': _toolbarX,
      'right': (size.width - _toolbarX).abs(),
      'top': (_toolbarY - 60).abs(),
      'bottom': (size.height - _toolbarY).abs(),
    };
    final side = map.entries.reduce((a, b) => a.value < b.value ? a : b).key;
    if (map[side]! < 40) {
      setState(() {
        _docked = true;
        _dockSide = side;
      });
    } else {
      // If the toolbox was released near (but not docked to) the left edge,
      // snap it clear of the fixed tool rail instead of leaving an overlap.
      _toolbarX = math.max(8, _toolbarX);
      _toolbarOffset.value = Offset(_toolbarX, _toolbarY);
    }
    pageData['toolbarX'] = _toolbarX;
    pageData['toolbarY'] = _toolbarY;
    pageData['toolbarDock'] = _docked ? _dockSide : 'free';
    _scheduleSave();
  }

  Widget _toolButton(CanvasTool tool, IconData icon) => GestureDetector(
        onDoubleTap: () => _styleSheet(tool),
        child: IconButton(
          onPressed: () => _selectTool(tool),
          constraints: const BoxConstraints.tightFor(width: 34, height: 34),
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          style: IconButton.styleFrom(
            backgroundColor: _tool == tool ? Theme.of(context).colorScheme.primaryContainer : null,
          ),
          icon: Icon(icon, size: 20),
          tooltip: '${tool.label} (double-tap for options)',
        ),
      );

  Widget _colorDot(Color color) => InkWell(
        onTap: () => setState(() => _penColor = color),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: CircleAvatar(radius: _penColor.value == color.value ? 13 : 10, backgroundColor: color, child: _penColor.value == color.value ? const Icon(Icons.check, size: 13, color: Colors.white) : null),
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
            Slider(value: size.clamp(.5, 24), min: .5, max: 24, divisions: 47, onChanged: (v) => setModal(() => size = v)),
            FilledButton(onPressed: () { _canvas.changeSize(size); Navigator.pop(sheetContext); }, child: const Text('Apply')),
          ]),
        ),
      ),
    );
  }

  Future<void> _pencaseSheet() async {
    const tools = <CanvasTool>[
      CanvasTool.ballpoint, CanvasTool.fountain, CanvasTool.pencil,
      CanvasTool.highlighter, CanvasTool.marker, CanvasTool.brush,
      CanvasTool.eraser, CanvasTool.pixelEraser, CanvasTool.lasso,
      CanvasTool.line, CanvasTool.arrow, CanvasTool.rectangle,
    ];
    final selected = _settings.getString('pencaseTools').split(',').where((v) => v.isNotEmpty).toSet();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (_, setModal) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Align(alignment: Alignment.centerLeft, child: Text('Pencase', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900))),
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Keep your most-used tools in the floating toolbar.'),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: tools.map((tool) => FilterChip(
                  avatar: Icon(_toolIcon(tool), size: 18),
                  label: Text(tool.label),
                  selected: selected.contains(tool.name),
                  onSelected: (value) => setModal(() {
                    if (value) {
                      selected.add(tool.name);
                    } else {
                      selected.remove(tool.name);
                    }
                  }),
                )).toList(),
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: () async {
                  await _settings.setString('pencaseTools', selected.join(','));
                  if (mounted) Navigator.pop(sheetContext);
                },
                child: const Text('Save pencase'),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _shapePanelWidget() => Positioned(
        right: 8,
        top: 54,
        bottom: 72,
        width: 300,
        child: Material(
          elevation: 14,
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: DefaultTabController(
            length: 6,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 2),
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
                tabs: [
                  Tab(text: 'Basic'),
                  Tab(text: 'Maths'),
                  Tab(text: 'Physics'),
                  Tab(text: 'Chemistry'),
                  Tab(text: 'Biology'),
                  Tab(text: 'More'),
                ],
              ),
              Expanded(child: TabBarView(children: [
                _shapeGrid([
                  CanvasTool.line, CanvasTool.arrow, CanvasTool.rectangle,
                  CanvasTool.roundedRectangle, CanvasTool.ellipse, CanvasTool.circle,
                  CanvasTool.triangle, CanvasTool.diamond, CanvasTool.hexagon,
                  CanvasTool.star, CanvasTool.customPolygon,
                ]),
                _shapeGrid([
                  CanvasTool.coordinateAxes, CanvasTool.parabola, CanvasTool.sineWave,
                  CanvasTool.angle, CanvasTool.vectorArrow,
                ]),
                _shapeGrid([
                  CanvasTool.vectorArrow, CanvasTool.projectilePath, CanvasTool.rayDiagram,
                  CanvasTool.convexLens, CanvasTool.concaveLens, CanvasTool.planeMirror,
                  CanvasTool.forceDiagram, CanvasTool.pulley,
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
                _shapeGrid([
                  CanvasTool.pentagon,
                  CanvasTool.parallelogram,
                  CanvasTool.trapezoid,
                  CanvasTool.cube,
                  CanvasTool.cuboid,
                  CanvasTool.cylinder,
                  CanvasTool.cone,
                  CanvasTool.pyramid,
                  CanvasTool.triangularPrism,
                  CanvasTool.sphere,
                  CanvasTool.arc,
                  CanvasTool.semicircle,
                  CanvasTool.sector,
                  CanvasTool.ring,
                  CanvasTool.crescent,
                  CanvasTool.cross,
                  CanvasTool.plus,
                  CanvasTool.heart,
                  CanvasTool.cloud,
                  CanvasTool.speechBubble,
                  CanvasTool.callout,
                  CanvasTool.curlyBrace,
                  CanvasTool.bracket,
                  CanvasTool.dimensionLine,
                  CanvasTool.numberLine,
                  CanvasTool.unitCircle,
                  CanvasTool.cubicGraph,
                  CanvasTool.exponentialGraph,
                  CanvasTool.logarithmicGraph,
                  CanvasTool.tangentGraph,
                  CanvasTool.ellipseAxes,
                  CanvasTool.vectorField,
                  CanvasTool.polarGraph,
                  CanvasTool.histogram,
                  CanvasTool.barChart,
                  CanvasTool.pieChart,
                  CanvasTool.flowchartTerminator,
                  CanvasTool.flowchartProcess,
                  CanvasTool.flowchartDecision,
                  CanvasTool.flowchartInputOutput,
                  CanvasTool.flowchartDocument,
                  CanvasTool.flowchartDatabase,
                  CanvasTool.flowchartConnector,
                  CanvasTool.timeline,
                  CanvasTool.tableGrid,
                  CanvasTool.checklist,
                  CanvasTool.waveform,
                  CanvasTool.spring,
                  CanvasTool.lever,
                  CanvasTool.inclinedPlane,
                  CanvasTool.gear,
                  CanvasTool.magnet,
                  CanvasTool.thermometer,
                  CanvasTool.stopwatch,
                  CanvasTool.ruler,
                  CanvasTool.compass,
                  CanvasTool.protractor,
                  CanvasTool.dottedLine,
                  CanvasTool.dashedLine,
                  CanvasTool.cartesianPlane,
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
          );
        },
      );

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
                      child: Icon(Icons.drag_indicator_rounded, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
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

  Widget _paperTab(List<PageTemplate> templates) => ListView(
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
          Row(children: [
            Expanded(child: _infoBox('Width', pageData['orientation'] == 'horizontal' ? '2105' : '1487')),
            const SizedBox(width: 10),
            Expanded(child: _infoBox('Height', pageData['orientation'] == 'horizontal' ? '1487' : '2105')),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _infoBox('Size', 'A4')),
            const SizedBox(width: 10),
            Expanded(child: _infoBox('Orientation', pageData['orientation'] == 'horizontal' ? 'Horizontal' : 'Vertical', onTap: () {
              setState(() => pageData['orientation'] = pageData['orientation'] == 'horizontal' ? 'vertical' : 'horizontal');
              _scheduleSave();
            })),
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
          _range('Line Spacing', _pageDouble('spacing', 28), 12, 64, (v) { setState(() => pageData['spacing'] = v); _scheduleSave(); }),
          FilledButton(onPressed: () {
            for (final page in _pages) {
              page['template'] = pageData['template'];
              page['paperColor'] = pageData['paperColor'];
              page['lineColor'] = pageData['lineColor'];
              page['lineOpacity'] = pageData['lineOpacity'];
              page['spacing'] = pageData['spacing'];
              page['cornellAssist'] = pageData['cornellAssist'];
            }
            setState(() {});
            _scheduleSave();
            Navigator.pop(context);
          }, child: const Text('Apply All Pages')),
        ],
      );

  Widget _customPaper() => ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text('Custom', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          FilledButton.tonal(onPressed: _paperColorPicker, child: const Text('Paper color')),
          FilledButton.tonal(onPressed: _lineColorPicker, child: const Text('Line color')),
          _range('Spacing', _pageDouble('spacing', 28), 12, 64, (v) { setState(() => pageData['spacing'] = v); _scheduleSave(); }),
          _range('Line opacity', _pageDouble('lineOpacity', .85), 0, 1, (v) { setState(() => pageData['lineOpacity'] = v); _scheduleSave(); }),
          SwitchListTile(contentPadding: EdgeInsets.zero, value: pageData['cornellAssist'] == true, onChanged: (v) { setState(() => pageData['cornellAssist'] = v); _scheduleSave(); }, title: const Text('Cornell assist line')),
          FilledButton(onPressed: () {
            for (final page in _pages) {
              page['template'] = pageData['template'];
              page['paperColor'] = pageData['paperColor'];
              page['lineColor'] = pageData['lineColor'];
              page['lineOpacity'] = pageData['lineOpacity'];
              page['spacing'] = pageData['spacing'];
              page['cornellAssist'] = pageData['cornellAssist'];
            }
            Navigator.pop(context);
            _scheduleSave();
          }, child: const Text('Apply to all pages')),
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

  Future<void> _colorSheet() async {
    var color = _penColor;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialog) => AlertDialog(
          title: const Text('Pen color'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 70, height: 70, decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all())),
            Slider(value: color.red.toDouble(), min: 0, max: 255, onChanged: (v) => setDialog(() => color = color.withRed(v.round()))),
            Slider(value: color.green.toDouble(), min: 0, max: 255, onChanged: (v) => setDialog(() => color = color.withGreen(v.round()))),
            Slider(value: color.blue.toDouble(), min: 0, max: 255, onChanged: (v) => setDialog(() => color = color.withBlue(v.round()))),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(onPressed: () {
              setState(() {
                _penColor = color;
                _toolColorOverrides[_tool.name] = color;
              });
              unawaited(_settings.setString('toolColors', jsonEncode({
                for (final entry in _toolColorOverrides.entries) entry.key: entry.value.toARGB32(),
              })));
              Navigator.pop(dialogContext);
            }, child: const Text('Use')),
          ],
        ),
      ),
    );
  }

  Future<void> _styleSheet([CanvasTool? requestedTool]) async {
    final target = requestedTool ?? _tool;
    var size = _toolSizeOverrides[target.name] ?? _penSize;
    var opacity = _opacity;
    var fill = _fill;
    var sides = _sides;
    var color = _toolColorOverrides[target.name] ?? _penColor;
    var dashed = _toolDashedOverrides[target.name] ?? _dashed;
    var curve = _settings.getString('pressureCurve');
    var exponent = _settings.getDouble('pressureExponent');
    var lassoStyle = _settings.getString('lassoStyle');
    var eraserMode = _settings.getString('eraserMode');
    var pressureErase = _settings.getBool('pressureErase');
    var pressureEraseArea = _settings.getBool('pressureEraseArea');

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
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
                  Slider(value: size.clamp(.5, 60), min: .5, max: 60, divisions: 119, onChanged: (v) => setModal(() => size = v)),
                  Text('Opacity: ${(opacity * 100).round()}%'),
                  Slider(value: opacity.clamp(.05, 1), min: .05, max: 1, onChanged: (v) => setModal(() => opacity = v)),
                  const SizedBox(height: 4),
                  const Text('Color', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _penPalette.map((choice) => InkWell(
                      onTap: () => setModal(() => color = choice),
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
                      onSelectionChanged: (values) => setModal(() => eraserMode = values.first),
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
                      onSelectionChanged: (values) => setModal(() => lassoStyle = values.first),
                    ),
                    const SizedBox(height: 6),
                    const Text('Draw around content with the lasso, then drag the selection toolbar to place its options wherever you need them.'),
                  ] else if (target.isShape) ...[
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: dashed,
                      onChanged: (value) => setModal(() => dashed = value),
                      title: const Text('Dashed outline'),
                    ),
                  ],
                  if (target.isShape)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: fill,
                      onChanged: (value) => setModal(() => fill = value),
                      title: const Text('Fill shape'),
                    ),
                  if (target == CanvasTool.customPolygon)
                    ListTile(
                      title: Text('Polygon sides: $sides'),
                      subtitle: Slider(value: sides.toDouble(), min: 3, max: 24, divisions: 21, onChanged: (v) => setModal(() => sides = v.round())),
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
                      onChanged: (value) { if (value != null) setModal(() => curve = value); },
                    ),
                    if (curve == 'custom')
                      ListTile(
                        title: Text('Custom pressure curve: ${exponent.toStringAsFixed(2)}'),
                        subtitle: Slider(value: exponent.clamp(.35, 2.5), min: .35, max: 2.5, onChanged: (v) => setModal(() => exponent = v)),
                      ),
                  ],
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () async {
                        setState(() {
                          _toolSizeOverrides[target.name] = size;
                          _toolColorOverrides[target.name] = color;
                          _toolDashedOverrides[target.name] = dashed;
                          if (target == _tool) {
                            _penSize = size;
                            _penColor = color;
                            _opacity = opacity;
                            _fill = fill;
                            _dashed = dashed;
                            _sides = sides;
                          }
                        });
                        await _settings.setString('toolSizes', jsonEncode(_toolSizeOverrides));
                        await _settings.setString('toolColors', jsonEncode({for (final entry in _toolColorOverrides.entries) entry.key: entry.value.toARGB32()}));
                        await _settings.setString('toolDashed', jsonEncode(_toolDashedOverrides));
                        await _settings.setString('pressureCurve', curve);
                        await _settings.setDouble('pressureExponent', exponent);
                        if (target == CanvasTool.lasso) await _settings.setString('lassoStyle', lassoStyle);
                        if (target == CanvasTool.eraser || target == CanvasTool.pixelEraser) {
                          await _settings.setString('eraserMode', eraserMode);
                        }
                        if (mounted) Navigator.pop(sheetContext);
                      },
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Save tool options'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _stickers() async {
    const items = ['⭐','❤️','✅','❌','⚠️','💡','📌','🎯','🔥','🚀','📚','📝','😊','👍','✨','🎉','☀️','🌙','☕','💻','🔒','📖','🧠','🟢'];
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => GridView.builder(
        padding: const EdgeInsets.all(18),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 6, crossAxisSpacing: 8, mainAxisSpacing: 8),
        itemCount: items.length,
        itemBuilder: (_, index) => InkWell(
          onTap: () { setState(() { _tool = CanvasTool.sticker; _sticker = items[index]; }); Navigator.pop(sheetContext); },
          child: Center(child: Text(items[index], style: const TextStyle(fontSize: 30))),
        ),
      ),
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
