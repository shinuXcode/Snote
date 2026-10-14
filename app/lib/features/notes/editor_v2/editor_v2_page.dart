import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:pdf/pdf.dart' as pdfcore;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfx/pdfx.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../canvas_engine/models/pen_config.dart';
import '../../../canvas_engine/models/stroke.dart';
import '../../../canvas_engine/models/stroke_codec.dart';
import '../../../canvas_engine/widgets/page_background.dart';
import '../../../core/security/note_lock_service.dart';
import '../../../core/settings/app_settings.dart';
import '../../../data/local/file_document_repository.dart';
import '../../../data/local/note_repository.dart';
import '../note_content_compatibility.dart';
import 'editor_v2_document.dart';
import 'editor_v2_ink_painter.dart';

/// Replacement note editor surface. It shares only Snote's persistence and
/// stroke-format contracts; pointer handling, selection, drawing, and painting
/// are implemented here rather than delegated to the legacy SnoteCanvas.
class EditorV2Page extends StatefulWidget {
  final LocalNote note;
  final Uint8List? initialPdfBytes;
  final String? initialPdfName;

  const EditorV2Page({
    super.key,
    required this.note,
    this.initialPdfBytes,
    this.initialPdfName,
  });

  @override
  State<EditorV2Page> createState() => _EditorV2PageState();
}

class _EditorV2PageState extends State<EditorV2Page>
    with WidgetsBindingObserver {
  static const double _pageWidth = 816;
  static const double _pageHeight = 1152;
  static const int _maxPdfPagesPerImport = 40;
  static const List<Color> _palette = <Color>[
    Color(0xff17202a),
    Color(0xff263238),
    Color(0xff1565c0),
    Color(0xff00897b),
    Color(0xff7b1fa2),
    Color(0xffc62828),
    Color(0xffef6c00),
    Color(0xffd4a900),
    Color(0xff2e7d32),
    Color(0xffec407a),
    Color(0xffffffff),
  ];
  static const List<CanvasTool> _quickTools = <CanvasTool>[
    CanvasTool.ballpoint,
    CanvasTool.fountain,
    CanvasTool.pencil,
    CanvasTool.highlighter,
    CanvasTool.marker,
    CanvasTool.brush,
    CanvasTool.eraser,
    CanvasTool.pixelEraser,
    CanvasTool.lasso,
    CanvasTool.line,
    CanvasTool.arrow,
    CanvasTool.rectangle,
    CanvasTool.ellipse,
    CanvasTool.triangle,
    CanvasTool.dashedLine,
    CanvasTool.dottedLine,
  ];

  final NoteRepository _repo = NoteRepository();
  final FileDocumentRepository _documents = FileDocumentRepository();
  final NoteLockService _lock = const NoteLockService();
  final SnoteSettings _settings = SnoteSettings.instance;
  final TextEditingController _title = TextEditingController();
  final QuillController _quill = QuillController.basic();
  final FocusNode _quillFocus = FocusNode();
  final ScrollController _quillScroll = ScrollController();
  final TransformationController _transform = TransformationController();
  final GlobalKey _pageCaptureKey = GlobalKey();
  final Map<String, TextEditingController> _textControllers =
      <String, TextEditingController>{};
  final Map<String, Uint8List> _backgroundBytesCache = <String, Uint8List>{};
  final Map<String, Uint8List> _imageBytesCache = <String, Uint8List>{};
  final Set<int> _activePointers = <int>{};
  final Set<int> _ignoredPointers = <int>{};
  final Set<int> _stylusPointers = <int>{};
  Timer? _holdTimer;
  Offset? _holdStartPosition;
  bool _longPressTriggered = false;
  final List<List<Map<String, Object?>>> _undoStack =
      <List<Map<String, Object?>>>[];
  final List<List<Map<String, Object?>>> _redoStack =
      <List<Map<String, Object?>>>[];

  Map<String, Object?> _rootContent = <String, Object?>{};
  List<Map<String, Object?>> _pages = <Map<String, Object?>>[];
  List<Map<String, Object?>> _favoritePens = <Map<String, Object?>>[];
  List<int> _bookmarkedPages = <int>[];
  int _page = 0;
  CanvasTool _tool = CanvasTool.ballpoint;
  Color _color = const Color(0xff17202a);
  double _size = 3;
  double _opacity = 1;
  double _pressureSensitivity = .55;
  double _velocitySensitivity = .65;
  PressureCurve _pressureCurve = PressureCurve.linear;
  bool _loading = true;
  bool _saving = false;
  bool _savePending = false;
  bool _saveInFlight = false;
  bool _locked = false;
  bool _unlocked = true;
  bool _panMode = false;
  bool _textMode = false;
  bool _floatingToolbar = false;
  bool _favoritesVertical = false;
  bool _fitInitialized = false;
  bool _exporting = false;
  String _toolbarDock = 'top';
  String? _loadError;
  String? _saveError;
  Timer? _saveTimer;
  Timer? _studyTimer;
  int _studySeconds = 0;
  int _studyRemaining = 0;
  int? _activePointer;
  Offset? _gestureStart;
  Offset? _eraserCursor;
  Offset _floatingOffset = const Offset(12, 12);
  List<StrokePoint> _livePoints = <StrokePoint>[];
  Stroke? _liveStroke;
  Rect? _lassoRect;
  final Set<String> _selectedStrokeIds = <String>{};
  final Map<String, Map<String, Object?>> _toolProfiles = <String, Map<String, Object?>>{};
  List<Map<String, Object?>> _strokeClipboard = <Map<String, Object?>>[];
  Map<String, Object?>? _pageClipboard;
  bool _showFavoritesShowcase = true;
  bool _showPageNavigation = true;
  bool _floatingPageNavigation = false;
  bool _fullScreenMode = false;
  bool _pressureEraseActive = false;
  bool _pressureEraseUsed = false;
  CanvasTool? _toolBeforePressureErase;
  Offset _favoriteOffset = const Offset(16, 220);
  Offset _pageNavOffset = const Offset(8, 280);
  double _calculatorWidth = 330;
  double _calculatorHeight = 470;

  Map<String, Object?> get _pageData {
    if (_pages.isEmpty) return <String, Object?>{};
    if (_page < 0 || _page >= _pages.length) {
      _page = EditorV2DocumentCodec.clampPage(_page, _pages.length);
    }
    return _pages[_page];
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _title.text = widget.note.title;
    _quill.addListener(_scheduleSave);
    _toolbarDock = const <String>{'top', 'bottom', 'left', 'right'}
            .contains(_settings.getString('editorV2ToolbarDock'))
        ? _settings.getString('editorV2ToolbarDock')
        : 'top';
    _floatingToolbar = _settings.getBool('editorV2FloatingToolbar');
    _favoritesVertical = _settings.getBool('editorV2FavoritesVertical');
    _showPageNavigation = _settings.getBool('showPageNavigation');
    _floatingPageNavigation = _settings.getBool('editorV2FloatingPageNavigation');
    _showFavoritesShowcase = _settings.getBool('editorV2ShowFavoritesShowcase');
    _restoreToolProfiles();
    _pressureSensitivity = .55;
    _pressureCurve = PressureCurve.values.firstWhere(
      (curve) => curve.name == _settings.getString('pressureCurve'),
      orElse: () => PressureCurve.linear,
    );
    _restoreFavoritePens();
    debugPrint(
      '[Snote][EditorV2] mount noteId=${widget.note.id} '
      'platform=${defaultTargetPlatform.name} '
      'pdfBytes=${widget.initialPdfBytes?.length ?? 0}',
    );
    _prepare();
    if (_settings.getBool('keepScreenOn')) {
      unawaited(WakelockPlus.enable().catchError((Object error) {
        debugPrint('[Snote][EditorV2] optional wakelock setup failed: $error');
      }));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_fitInitialized) return;
    _fitInitialized = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final availableWidth = MediaQuery.sizeOf(context).width - 30;
      final scale = (availableWidth / _pageWidth).clamp(.32, 1.0).toDouble();
      _transform.value = Matrix4.identity()..scale(scale);
    });
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
    try {
      final locked = await _lock.isLocked(widget.note.id);
      if (!mounted) return;
      if (locked) {
        setState(() {
          _locked = true;
          _unlocked = false;
          _loading = false;
        });
        return;
      }
      await _loadDocument();
    } catch (error, stackTrace) {
      debugPrint(
        '[Snote][EditorV2] initialization failed noteId=${widget.note.id}: '
        '$error\n$stackTrace',
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError =
            'The document could not be opened. Your saved content was not replaced.\n$error';
      });
    }
  }

  Future<void> _loadDocument() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final saved = await _repo.get(widget.note.id);
    if (saved == null) {
      throw StateError('This note no longer exists in the current local account.');
    }
    final root = EditorV2DocumentCodec.decodeRoot(saved.contentJson);
    final delta = root['text_delta'];
    if (delta is List) {
      try {
        _quill.document = Document.fromJson(delta);
      } catch (error, stackTrace) {
        debugPrint('[Snote][EditorV2] rich-text delta restore failed: $error\n$stackTrace');
      }
    }
    final pages = EditorV2DocumentCodec.decodePages(root);

    Uint8List? pdfBytes = widget.initialPdfBytes;
    String? pdfName = widget.initialPdfName;
    DocumentAsset? sourcePdf;
    final assets = await _documents.listForNote(widget.note.id);
    for (final asset in assets.reversed) {
      final type = asset.type.toLowerCase();
      final name = asset.name.toLowerCase();
      if (type == 'pdf' || type == 'application/pdf' || name.endsWith('.pdf')) {
        sourcePdf = asset;
        break;
      }
    }
    final hasPdfAttachment = sourcePdf != null;
    if ((pdfBytes == null || pdfBytes.isEmpty) && sourcePdf != null) {
      pdfBytes = await _documents.readBytes(sourcePdf);
      pdfName = sourcePdf.name;
      if (pdfBytes.isEmpty) {
        throw StateError(
          'The original PDF attachment is empty. It has been preserved.',
        );
      }
    }

    var renderedPdf = false;
    var totalPdfPages = 0;
    if (pdfBytes != null && pdfBytes.isNotEmpty) {
      final sourceHash = sha256.convert(pdfBytes).toString();
      if (shouldRestorePdfPageBackgrounds(pages, sourceHash: sourceHash)) {
        final result = await _renderPdfPages(
          pdfBytes,
          pdfName ?? '${saved.title}.pdf',
        );
        if (result.pages.isEmpty) {
          throw StateError('The PDF renderer returned no pages.');
        }
        final merged = mergeSavedAnnotationsWithPdfPages(
          savedPages: pages,
          renderedPages: result.pages,
        );
        pages
          ..clear()
          ..addAll(merged.map(EditorV2DocumentCodec.normalizePage));
        totalPdfPages = result.totalPages;
        renderedPdf = true;
      }
    }

    if (pages.isEmpty && hasPdfAttachment) {
      throw StateError(
        'A PDF attachment exists but no readable PDF pages were restored. '
        'The original file is preserved; no blank page was substituted.',
      );
    }
    if (pages.isEmpty) {
      pages.add(EditorV2DocumentCodec.normalizePage(<String, Object?>{}));
    }
    for (var i = 0; i < pages.length; i++) {
      pages[i] = EditorV2DocumentCodec.normalizePage(
        pages[i],
        fallbackId: 'editor-v2-page-${i + 1}',
      );
    }

    final rawBookmarks = root['bookmarkedPages'];
    final bookmarks = rawBookmarks is List
        ? rawBookmarks.whereType<num>().map((value) => value.toInt()).where((value) => value > 0).toSet().toList()
        : <int>[];
    _title.text = saved.title;

    if (!mounted) return;
    setState(() {
      _rootContent = root;
      _pages = pages;
      _page = EditorV2DocumentCodec.clampPage(
        (root['currentPageIndex'] as num?)?.toInt() ?? 0,
        pages.length,
      );
      _textMode = root['editorMode'] == 'text';
      _bookmarkedPages = bookmarks;
      _loading = false;
      _locked = false;
      _unlocked = true;
      _loadError = null;
    });
    _initializeTextControllers();
    debugPrint(
      '[Snote][EditorV2] document ready noteId=${widget.note.id} '
      'pages=${pages.length} pdfPages=$totalPdfPages migratedPdf=$renderedPdf',
    );
    if (renderedPdf || root['pages'] == null || (root['pages'] is List && (root['pages'] as List).isEmpty)) {
      _scheduleSave();
      await _save(force: true);
    }
  }

  Future<({List<Map<String, Object?>> pages, int totalPages})> _renderPdfPages(
    Uint8List sourceBytes,
    String sourceName,
  ) async {
    if (sourceBytes.isEmpty) throw StateError('The selected PDF is empty.');
    final sourceHash = sha256.convert(sourceBytes).toString();
    final document = await PdfDocument.openData(sourceBytes);
    final totalPages = document.pagesCount;
    final importCount = math.min(totalPages, _maxPdfPagesPerImport);
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
            throw StateError('Could not render PDF page ${index}.');
          }
          imported.add(<String, Object?>{
            'id': 'pdf-${DateTime.now().microsecondsSinceEpoch}-$index',
            'template': PageTemplate.blank.name,
            'paperColor': 0xffffffff,
            'lineColor': 0xffd8dee8,
            'lineOpacity': .85,
            'spacing': 28.0,
            'lineWidth': .7,
            'pageSize': 'A4',
            'pageAspectRatio': math.min(pdfPage.width, pdfPage.height) /
                math.max(pdfPage.width, pdfPage.height),
            'cornellAssist': false,
            'orientation': pdfPage.width > pdfPage.height ? 'horizontal' : 'vertical',
            'backgroundImage': base64Encode(rendered.bytes),
            'pdfSourceName': sourceName,
            'pdfSourceHash': sourceHash,
            'pdfBackgroundHash': sha256.convert(rendered.bytes).toString(),
            'pdfSourcePage': index,
            'strokes': <Object?>[],
            'images': <Object?>[],
            'textBoxes': <Object?>[],
          });
        } finally {
          await pdfPage.close();
        }
      }
    } finally {
      await document.close();
    }
    return (pages: imported, totalPages: totalPages);
  }

  void _initializeTextControllers() {
    final currentIds = <String>{};
    for (final page in _pages) {
      final raw = page['textBoxes'];
      if (raw is! List) continue;
      for (final item in raw.whereType<Map>()) {
        final box = item.map<String, Object?>(
          (key, value) => MapEntry(key.toString(), value),
        );
        final id = box['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        currentIds.add(id);
        _textControllers.putIfAbsent(
          id,
          () => TextEditingController(text: box['text']?.toString() ?? ''),
        );
      }
    }
    final stale = _textControllers.keys.where((key) => !currentIds.contains(key)).toList();
    for (final key in stale) {
      _textControllers.remove(key)?.dispose();
    }
  }

  void _restoreToolProfiles() {
    try {
      final decoded = jsonDecode(_settings.getString('editorV2ToolProfiles'));
      if (decoded is Map) {
        _toolProfiles
          ..clear()
          ..addEntries(decoded.entries.where((entry) => entry.value is Map).map((entry) {
            final map = (entry.value as Map).map<String, Object?>(
              (key, value) => MapEntry(key.toString(), value),
            );
            return MapEntry(entry.key.toString(), map);
          }));
      }
    } catch (error) {
      debugPrint('[Snote][EditorV2] ignoring invalid per-tool profile settings: $error');
    }
  }

  Future<void> _saveToolProfiles() =>
      _settings.setString('editorV2ToolProfiles', jsonEncode(_toolProfiles));

  void _rememberCurrentToolProfile() {
    _toolProfiles[_tool.name] = <String, Object?>{
      'size': _size,
      'color': _color.toARGB32(),
      'opacity': _opacity,
      'pressureSensitivity': _pressureSensitivity,
      'velocitySensitivity': _velocitySensitivity,
      'pressureCurve': _pressureCurve.name,
    };
    unawaited(_saveToolProfiles());
  }

  void _restoreFavoritePens() {
    final raw = _settings.getString('editorV2FavoritePens');
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        _favoritePens = decoded
            .whereType<Map>()
            .map((item) => item.map<String, Object?>(
                  (key, value) => MapEntry(key.toString(), value),
                ))
            .where((item) => item['tool'] is String && item['color'] is num)
            .take(200)
            .toList();
      }
    } catch (_) {
      _favoritePens = <Map<String, Object?>>[];
    }
    if (_favoritePens.isEmpty) {
      _favoritePens = <Map<String, Object?>>[
        <String, Object?>{'tool': 'ballpoint', 'color': 0xff17202a, 'size': 3.0, 'label': 'Fine black'},
        <String, Object?>{'tool': 'fountain', 'color': 0xff1565c0, 'size': 3.2, 'label': 'Blue fountain'},
        <String, Object?>{'tool': 'pencil', 'color': 0xff37474f, 'size': 1.8, 'label': 'Pencil'},
        <String, Object?>{'tool': 'highlighter', 'color': 0xffffd54f, 'size': 8.0, 'label': 'Highlight'},
      ];
    }
  }

  Future<void> _saveFavoritePens() async {
    await _settings.setString('editorV2FavoritePens', jsonEncode(_favoritePens));
  }

  void _scheduleSave() {
    if (_loading || _pages.isEmpty || (_locked && !_unlocked)) return;
    _savePending = true;
    if (!_settings.getBool('autoSave')) {
      if (mounted) setState(() => _saving = false);
      return;
    }
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 650), () {
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
    if (mounted) setState(() => _saving = true);
    try {
      final payload = EditorV2DocumentCodec.savePayload(
        previousContent: _rootContent,
        pages: _pages,
        editorMode: _textMode ? 'text' : 'handwriting',
        bookmarkedPages: _bookmarkedPages,
        textDelta: _quill.document.toDelta().toJson(),
        currentPageIndex: _page,
      );
      await _repo.saveContent(widget.note.id, payload);
      final title = _title.text.trim();
      if (title.isNotEmpty) await _repo.rename(widget.note.id, title);
      _rootContent = payload;
      _saveError = null;
      debugPrint(
        '[Snote][EditorV2] saved noteId=${widget.note.id} '
        'pages=${_pages.length} force=$force',
      );
    } catch (error, stackTrace) {
      _saveError = error.toString();
      debugPrint(
        '[Snote][EditorV2] save failed noteId=${widget.note.id}: '
        '$error\n$stackTrace',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed; your in-memory edits remain: $error')),
        );
      }
    } finally {
      _saveInFlight = false;
      if (mounted) setState(() => _saving = false);
      if (_savePending && mounted && _settings.getBool('autoSave')) {
        _saveTimer = Timer(const Duration(milliseconds: 650), () {
          unawaited(_save());
        });
      }
    }
  }

  Future<void> _flushSave() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (_savePending && !_saveInFlight) await _save(force: true);
    while (_saveInFlight) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    if (_savePending && mounted) await _save(force: true);
  }

  void _pushUndo() {
    _undoStack.add(EditorV2DocumentCodec.clonePages(_pages));
    if (_undoStack.length > 80) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(EditorV2DocumentCodec.clonePages(_pages));
    setState(() {
      _pages = _undoStack.removeLast();
      _page = EditorV2DocumentCodec.clampPage(_page, _pages.length);
      _selectedStrokeIds.clear();
      _lassoRect = null;
    });
    _initializeTextControllers();
    _scheduleSave();
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(EditorV2DocumentCodec.clonePages(_pages));
    setState(() {
      _pages = _redoStack.removeLast();
      _page = EditorV2DocumentCodec.clampPage(_page, _pages.length);
      _selectedStrokeIds.clear();
      _lassoRect = null;
    });
    _initializeTextControllers();
    _scheduleSave();
  }

  List<Stroke> _strokesFor(Map<String, Object?> page) {
    final raw = page['strokes'];
    return StrokeCodec.documentToStrokes(<String, Object?>{
      'strokes': raw is List ? raw : <Object?>[],
    });
  }

  StrokePoint _pointFrom(PointerEvent event) {
    var pressure = 1.0;
    final range = event.pressureMax - event.pressureMin;
    if (range > 0 && event.kind == PointerDeviceKind.stylus) {
      pressure = ((event.pressure - event.pressureMin) / range)
          .clamp(.05, 1.0)
          .toDouble();
    } else if (event.pressure.isFinite && event.pressure > 0) {
      pressure = event.pressure.clamp(.1, 1.0).toDouble();
    }
    return StrokePoint(
      position: event.localPosition,
      pressure: pressure,
      timestamp: event.timeStamp.inMicroseconds.toDouble() / 1000,
      tilt: event is PointerEvent ? event.orientation : 0,
      orientation: event is PointerEvent ? event.orientation : 0,
    );
  }

  PenConfig _penConfig() => PenConfig(
        type: _tool.penType,
        color: _color,
        size: _size,
        opacity: _tool == CanvasTool.highlighter ? _opacity.clamp(.08, .55).toDouble() : _opacity,
        pressureSensitivity: _pressureSensitivity,
        velocitySensitivity: _velocitySensitivity,
        pressureCurve: _pressureCurve,
        customPressureExponent: _settings.getDouble('pressureExponent') <= 0
            ? 1
            : _settings.getDouble('pressureExponent'),
      );

  Stroke _buildLiveStroke() {
    final start = _gestureStart ?? Offset.zero;
    final shapeTool = _tool.isShape && _tool != CanvasTool.lasso;
    final points = shapeTool && _livePoints.isNotEmpty
        ? <StrokePoint>[_livePoints.first, _livePoints.last]
        : List<StrokePoint>.from(_livePoints);
    return Stroke(
      id: 'live-${_activePointer ?? 0}',
      points: points,
      pen: _penConfig(),
      shape: shapeTool ? _tool.name : null,
      dashed: _tool == CanvasTool.dashedLine || _tool == CanvasTool.dottedLine,
    );
  }

  void _onPointerDown(PointerDownEvent event) {
    _activePointers.add(event.pointer);
    if (event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus) {
      _stylusPointers.add(event.pointer);
    }
    if (_pageData['locked'] == true) {
      _ignoredPointers.add(event.pointer);
      return;
    }
    if (_activePointers.length > 1) {
      if (_activePointer != null) _ignoredPointers.add(_activePointer!);
      _ignoredPointers.add(event.pointer);
      _activePointer = null;
      _livePoints = <StrokePoint>[];
      _liveStroke = null;
      _gestureStart = null;
      if (mounted) setState(() {});
      return;
    }
    if (_ignoredPointers.contains(event.pointer) ||
        _panMode ||
        (_settings.getBool('palmRejection') && _stylusPointers.isNotEmpty && event.kind == PointerDeviceKind.touch)) {
      _ignoredPointers.add(event.pointer);
      return;
    }
    _activePointer = event.pointer;
    _gestureStart = event.localPosition;
    _holdStartPosition = event.localPosition;
    _longPressTriggered = false;
    _livePoints = <StrokePoint>[_pointFrom(event)];
    _eraserCursor = event.localPosition;
    _liveStroke = _buildLiveStroke();
    _holdTimer?.cancel();
    if ((event.kind == PointerDeviceKind.stylus || event.kind == PointerDeviceKind.invertedStylus) &&
        _settings.getBool('stylusHoldActions')) {
      _holdTimer = Timer(const Duration(milliseconds: 480), () {
        if (!mounted || _activePointer != event.pointer || _holdStartPosition == null) return;
        final position = _holdStartPosition!;
        if (_selectStrokeAt(position, radius: math.max(14, _size * 2))) {
          _longPressTriggered = true;
          _livePoints.clear();
          _liveStroke = null;
          setState(() {});
          return;
        }
        if (_settings.getBool('pressureErase')) {
          _longPressTriggered = true;
          _pressureEraseActive = true;
          _pressureEraseUsed = false;
          _toolBeforePressureErase = _tool;
          setState(() {
            _tool = CanvasTool.eraser;
            _size = 24;
            _livePoints.clear();
            _liveStroke = null;
            _eraserCursor = position;
          });
        }
      });
    }
    setState(() {});
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_ignoredPointers.contains(event.pointer)) return;
    if (_activePointer == event.pointer && _holdStartPosition != null &&
        (event.localPosition - _holdStartPosition!).distance > 11 &&
        !_pressureEraseActive && !_longPressTriggered) {
      _holdTimer?.cancel();
      _holdTimer = null;
      _holdStartPosition = null;
    }
    if (_activePointer == event.pointer && _pressureEraseActive) {
      _pressureEraseUsed = true;
      _eraserCursor = event.localPosition;
      _eraseAt(event.localPosition, math.max(18, _size * 2).toDouble());
      setState(() {});
      return;
    }
    if (_activePointer != event.pointer) {
      if (_tool == CanvasTool.eraser || _tool == CanvasTool.pixelEraser) {
        _eraserCursor = event.localPosition;
        setState(() {});
      }
      return;
    }
    final point = _pointFrom(event);
    if (_livePoints.isNotEmpty) {
      final previous = _livePoints.last.position;
      if ((point.position - previous).distance < .35) return;
    }
    _livePoints.add(point);
    _liveStroke = _buildLiveStroke();
    _eraserCursor = event.localPosition;
    setState(() {});
  }

  void _onPointerUp(PointerEvent event) {
    _activePointers.remove(event.pointer);
    _stylusPointers.remove(event.pointer);
    _holdTimer?.cancel();
    _holdTimer = null;
    _holdStartPosition = null;
    if (_ignoredPointers.remove(event.pointer)) return;
    if (_activePointer != event.pointer) return;
    if (_longPressTriggered) {
      if (_pressureEraseActive) {
        _eraseAt(event.localPosition, math.max(18, _size * 2).toDouble());
      }
      setState(() {
        _activePointer = null;
        _gestureStart = null;
        _livePoints = <StrokePoint>[];
        _liveStroke = null;
        _pressureEraseActive = false;
        if (_toolBeforePressureErase != null) {
          _tool = _toolBeforePressureErase!;
          _toolBeforePressureErase = null;
          _selectTool(_tool);
        }
        _longPressTriggered = false;
        _eraserCursor = null;
      });
      return;
    }
    final point = _pointFrom(event);
    if (_livePoints.isEmpty ||
        (_livePoints.last.position - point.position).distance > .2) {
      _livePoints.add(point);
    }
    final start = _gestureStart ?? point.position;
    final end = point.position;
    final completedPoints = _smoothPoints(_livePoints);
    _activePointer = null;
    _gestureStart = null;
    _livePoints = <StrokePoint>[];
    _liveStroke = null;

    if (_tool == CanvasTool.eraser || _tool == CanvasTool.pixelEraser) {
      _eraseAt(end, _tool == CanvasTool.pixelEraser ? 7 : math.max(18, _size * 2));
    } else if (_tool == CanvasTool.lasso) {
      _selectInRect(Rect.fromPoints(start, end));
    } else if (completedPoints.isNotEmpty) {
      _pushUndo();
      final shape = _tool.isShape;
      final stroke = Stroke(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        points: shape
            ? <StrokePoint>[
                completedPoints.first,
                completedPoints.last,
              ]
            : completedPoints,
        pen: _penConfig(),
        shape: shape ? _tool.name : null,
        dashed: _tool == CanvasTool.dashedLine || _tool == CanvasTool.dottedLine,
      );
      final strokes = _pageData['strokes'] as List<Object?>;
      strokes.add(StrokeCodec.strokeToJson(stroke));
      setState(() {
        _eraserCursor = null;
        _selectedStrokeIds.clear();
        _lassoRect = null;
      });
      _scheduleSave();
    }
    setState(() {});
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _activePointers.remove(event.pointer);
    _stylusPointers.remove(event.pointer);
    _holdTimer?.cancel();
    _holdTimer = null;
    _holdStartPosition = null;
    if (_pressureEraseActive && _toolBeforePressureErase != null) {
      _tool = _toolBeforePressureErase!;
      _toolBeforePressureErase = null;
    }
    _pressureEraseActive = false;
    _longPressTriggered = false;
    _ignoredPointers.remove(event.pointer);
    if (_activePointer == event.pointer) {
      _activePointer = null;
      _gestureStart = null;
      _livePoints = <StrokePoint>[];
      _liveStroke = null;
    }
    setState(() {});
  }

  List<StrokePoint> _smoothPoints(List<StrokePoint> points) {
    if (points.length < 3 || _tool.isShape) return List<StrokePoint>.from(points);
    final result = <StrokePoint>[points.first];
    for (var i = 1; i < points.length - 1; i++) {
      final before = points[i - 1];
      final current = points[i];
      final after = points[i + 1];
      final smoothed = Offset(
        before.position.dx * .18 + current.position.dx * .64 + after.position.dx * .18,
        before.position.dy * .18 + current.position.dy * .64 + after.position.dy * .18,
      );
      result.add(current.copyWith(position: smoothed));
    }
    result.add(points.last);
    return result;
  }

  void _eraseAt(Offset position, double radius) {
    final raw = _pageData['strokes'];
    if (raw is! List || raw.isEmpty) return;
    final decoded = StrokeCodec.documentToStrokes(<String, Object?>{'strokes': raw});
    final retained = <Stroke>[];
    var removed = false;
    for (final stroke in decoded) {
      var hit = false;
      for (var i = 0; i < stroke.points.length; i++) {
        if ((stroke.points[i].position - position).distance <= radius) {
          hit = true;
          break;
        }
        if (i > 0 &&
            _distanceToSegment(
                  position,
                  stroke.points[i - 1].position,
                  stroke.points[i].position,
                ) <=
                radius) {
          hit = true;
          break;
        }
      }
      if (hit) {
        removed = true;
      } else {
        retained.add(stroke);
      }
    }
    if (!removed) return;
    _pushUndo();
    _pageData['strokes'] = retained.map(StrokeCodec.strokeToJson).toList();
    setState(() {
      _selectedStrokeIds.clear();
      _eraserCursor = position;
    });
    _scheduleSave();
  }

  double _distanceToSegment(Offset point, Offset a, Offset b) {
    final delta = b - a;
    final lengthSquared = delta.distanceSquared;
    if (lengthSquared <= 0) return (point - a).distance;
    final t = (((point - a).dx * delta.dx + (point - a).dy * delta.dy) /
            lengthSquared)
        .clamp(0.0, 1.0);
    final projection = a + delta * t;
    return (point - projection).distance;
  }

  void _selectInRect(Rect rect) {
    final normalized = Rect.fromLTRB(
      math.min(rect.left, rect.right),
      math.min(rect.top, rect.bottom),
      math.max(rect.left, rect.right),
      math.max(rect.top, rect.bottom),
    );
    final selected = <String>{};
    for (final stroke in _strokesFor(_pageData)) {
      final points = stroke.points.map((point) => point.position);
      if (points.any(normalized.inflate(2).contains)) selected.add(stroke.id);
    }
    setState(() {
      _lassoRect = normalized;
      _selectedStrokeIds
        ..clear()
        ..addAll(selected);
    });
  }

  void _deleteSelection() {
    if (_selectedStrokeIds.isEmpty) return;
    _pushUndo();
    final raw = _pageData['strokes'] as List<Object?>;
    final strokes = StrokeCodec.documentToStrokes(<String, Object?>{'strokes': raw});
    _pageData['strokes'] = strokes
        .where((stroke) => !_selectedStrokeIds.contains(stroke.id))
        .map(StrokeCodec.strokeToJson)
        .toList();
    setState(() {
      _selectedStrokeIds.clear();
      _lassoRect = null;
    });
    _scheduleSave();
  }

  void _moveSelection(Offset delta) {
    if (_selectedStrokeIds.isEmpty) return;
    _pushUndo();
    final raw = _pageData['strokes'] as List<Object?>;
    final strokes = StrokeCodec.documentToStrokes(<String, Object?>{'strokes': raw});
    _pageData['strokes'] = strokes.map((stroke) {
      if (!_selectedStrokeIds.contains(stroke.id)) return StrokeCodec.strokeToJson(stroke);
      return StrokeCodec.strokeToJson(stroke.copyWith(
        points: stroke.points
            .map((point) => point.copyWith(position: point.position + delta))
            .toList(),
      ));
    }).toList();
    setState(() {});
    _scheduleSave();
  }

  Rect? _selectionBounds() {
    final selected = _strokesFor(_pageData).where((stroke) => _selectedStrokeIds.contains(stroke.id));
    final points = selected.expand((stroke) => stroke.points).map((point) => point.position).toList();
    if (points.isEmpty) return null;
    var left = points.first.dx, right = points.first.dx, top = points.first.dy, bottom = points.first.dy;
    for (final point in points.skip(1)) {
      left = math.min(left, point.dx);
      right = math.max(right, point.dx);
      top = math.min(top, point.dy);
      bottom = math.max(bottom, point.dy);
    }
    return Rect.fromLTRB(left, top, right, bottom).inflate(3);
  }

  void _copySelection() {
    if (_selectedStrokeIds.isEmpty) return;
    _strokeClipboard = _strokesFor(_pageData)
        .where((stroke) => _selectedStrokeIds.contains(stroke.id))
        .map((stroke) => StrokeCodec.strokeToJson(stroke).map<String, Object?>(
              (key, value) => MapEntry(key.toString(), value),
            ))
        .toList();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied ${_strokeClipboard.length} stroke(s)')),
    );
  }

  void _cutSelection() {
    _copySelection();
    _deleteSelection();
  }

  void _pasteStrokes({bool duplicate = false}) {
    final source = duplicate
        ? _strokesFor(_pageData).where((stroke) => _selectedStrokeIds.contains(stroke.id)).toList()
        : StrokeCodec.documentToStrokes(<String, Object?>{'strokes': _strokeClipboard});
    if (source.isEmpty) return;
    _pushUndo();
    final raw = _pageData['strokes'] as List<Object?>;
    final offset = duplicate ? const Offset(22, 22) : const Offset(18, 18);
    final added = source.map((stroke) => StrokeCodec.strokeToJson(stroke.copyWith(
      id: DateTime.now().microsecondsSinceEpoch.toString() + '-${math.Random().nextInt(100000)}',
      points: stroke.points.map((point) => point.copyWith(position: point.position + offset)).toList(),
    ))).toList();
    raw.addAll(added);
    final ids = added.map((item) => item['id']?.toString() ?? '').where((value) => value.isNotEmpty).toSet();
    setState(() {
      _selectedStrokeIds
        ..clear()
        ..addAll(ids);
      _lassoRect = _selectionBounds();
    });
    _scheduleSave();
  }

  void _scaleSelection(double factor) {
    if (_selectedStrokeIds.isEmpty) return;
    final bounds = _selectionBounds();
    if (bounds == null) return;
    _pushUndo();
    final center = bounds.center;
    final raw = _pageData['strokes'] as List<Object?>;
    final strokes = StrokeCodec.documentToStrokes(<String, Object?>{'strokes': raw});
    _pageData['strokes'] = strokes.map((stroke) {
      if (!_selectedStrokeIds.contains(stroke.id)) return StrokeCodec.strokeToJson(stroke);
      return StrokeCodec.strokeToJson(stroke.copyWith(
        points: stroke.points.map((point) => point.copyWith(
          position: center + (point.position - center) * factor,
        )).toList(),
      ));
    }).toList();
    setState(() {
      final updated = _selectionBounds();
      if (updated != null) _lassoRect = updated;
    });
    _scheduleSave();
  }

  bool _selectStrokeAt(Offset position, {double radius = 12}) {
    for (final stroke in _strokesFor(_pageData).reversed) {
      for (var i = 0; i < stroke.points.length; i++) {
        if ((stroke.points[i].position - position).distance <= radius ||
            (i > 0 && _distanceToSegment(position, stroke.points[i - 1].position, stroke.points[i].position) <= radius)) {
          final points = stroke.points.map((point) => point.position).toList();
          var left = points.first.dx, right = points.first.dx, top = points.first.dy, bottom = points.first.dy;
          for (final point in points.skip(1)) {
            left = math.min(left, point.dx);
            right = math.max(right, point.dx);
            top = math.min(top, point.dy);
            bottom = math.max(bottom, point.dy);
          }
          setState(() {
            _tool = CanvasTool.lasso;
            _selectedStrokeIds
              ..clear()
              ..add(stroke.id);
            _lassoRect = Rect.fromLTRB(left, top, right, bottom).inflate(5);
          });
          return true;
        }
      }
    }
    return false;
  }

  void _selectTool(CanvasTool tool) {
    final profile = _toolProfiles[tool.name];
    setState(() {
      _tool = tool;
      _size = (profile?['size'] as num?)?.toDouble() ?? switch (tool) {
        CanvasTool.eraser => 24,
        CanvasTool.pixelEraser => 8,
        CanvasTool.highlighter => 8,
        CanvasTool.pencil => 1.8,
        CanvasTool.marker || CanvasTool.brush => 5,
        _ when tool.isShape => 2.2,
        _ => 3,
      };
      _opacity = (profile?['opacity'] as num?)?.toDouble() ??
          (tool == CanvasTool.highlighter ? .35 : tool == CanvasTool.marker ? .85 : 1);
      _pressureSensitivity = (profile?['pressureSensitivity'] as num?)?.toDouble() ?? .55;
      _velocitySensitivity = (profile?['velocitySensitivity'] as num?)?.toDouble() ?? .65;
      if (profile?['color'] is num) {
        _color = Color((profile!['color'] as num).toInt());
      } else if (tool == CanvasTool.highlighter) {
        _color = const Color(0xffffd54f);
      } else if (tool == CanvasTool.marker) {
        _color = const Color(0xff1565c0);
      }
      _pressureCurve = PressureCurve.values.firstWhere(
        (curve) => curve.name == profile?['pressureCurve'],
        orElse: () => _pressureCurve,
      );
    });
    if (tool != CanvasTool.lasso) {
      _selectedStrokeIds.clear();
      _lassoRect = null;
    }
  }

  Future<void> _openToolPicker() async {
    final selected = await showModalBottomSheet<CanvasTool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EditorV2ToolPicker(selected: _tool),
    );
    if (selected != null && mounted) _selectTool(selected);
  }

  Future<void> _chooseColor() async {
    final chosen = await showModalBottomSheet<Color>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Wrap(
            spacing: 14,
            runSpacing: 14,
            children: _palette.map((color) => InkWell(
              onTap: () => Navigator.pop(sheetContext, color),
              borderRadius: BorderRadius.circular(30),
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: color == _color
                        ? Theme.of(context).colorScheme.primary
                        : Colors.black26,
                    width: color == _color ? 3 : 1,
                  ),
                ),
              ),
            )).toList(),
          ),
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    setState(() => _color = chosen);
  }

  Future<void> _strokeSettings([CanvasTool? requestedTool]) async {
    final targetTool = requestedTool ?? _tool;
    if (targetTool != _tool) _selectTool(targetTool);
    var size = _size;
    var opacity = _opacity;
    var pressure = _pressureSensitivity;
    var velocity = _velocitySensitivity;
    var curve = _pressureCurve;
    var color = _color;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(18, 8, 18, 22 + MediaQuery.viewInsetsOf(context).bottom),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${targetTool.label} settings', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: _palette.map((candidate) => InkWell(
                      onTap: () => setSheetState(() => color = candidate),
                      borderRadius: BorderRadius.circular(24),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: candidate,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: candidate == color ? Theme.of(context).colorScheme.primary : Colors.black26,
                            width: candidate == color ? 3 : 1,
                          ),
                        ),
                      ),
                    )).toList(),
                  ),
                  const SizedBox(height: 8),
                  Text('Stroke size: ${size.toStringAsFixed(1)}'),
                  Slider(
                    min: .5, max: 40, value: size.clamp(.5, 40),
                    onChanged: (value) => setSheetState(() => size = value),
                  ),
                  Text('Opacity: ${(opacity * 100).round()}%'),
                  Slider(
                    min: .05, max: 1, value: opacity.clamp(.05, 1),
                    onChanged: (value) => setSheetState(() => opacity = value),
                  ),
                  Text('Pressure sensitivity: ${pressure.toStringAsFixed(2)}'),
                  Slider(
                    min: 0, max: 1, value: pressure,
                    onChanged: (value) => setSheetState(() => pressure = value),
                  ),
                  Text('Velocity sensitivity: ${velocity.toStringAsFixed(2)}'),
                  Slider(
                    min: 0, max: 1, value: velocity,
                    onChanged: (value) => setSheetState(() => velocity = value),
                  ),
                  DropdownButtonFormField<PressureCurve>(
                    initialValue: curve,
                    decoration: const InputDecoration(labelText: 'Pressure curve'),
                    items: PressureCurve.values.map((value) => DropdownMenuItem(
                      value: value, child: Text(value.name),
                    )).toList(),
                    onChanged: (value) {
                      if (value != null) setSheetState(() => curve = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _tool = targetTool;
                            _size = size;
                            _opacity = opacity;
                            _pressureSensitivity = pressure;
                            _velocitySensitivity = velocity;
                            _pressureCurve = curve;
                            _color = color;
                          });
                          _toolProfiles[targetTool.name] = <String, Object?>{
                            'size': size,
                            'color': color.toARGB32(),
                            'opacity': opacity,
                            'pressureSensitivity': pressure,
                            'velocitySensitivity': velocity,
                            'pressureCurve': curve.name,
                          };
                          unawaited(_saveToolProfiles());
                          Navigator.pop(sheetContext);
                        },
                        child: const Text('Save to this tool'),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: () {
                          setState(() {
                            _tool = targetTool;
                            _size = size;
                            _opacity = opacity;
                            _pressureSensitivity = pressure;
                            _velocitySensitivity = velocity;
                            _pressureCurve = curve;
                            _color = color;
                          });
                          _toolProfiles[targetTool.name] = <String, Object?>{
                            'size': size,
                            'color': color.toARGB32(),
                            'opacity': opacity,
                            'pressureSensitivity': pressure,
                            'velocitySensitivity': velocity,
                            'pressureCurve': curve.name,
                          };
                          unawaited(_saveToolProfiles());
                          Navigator.pop(sheetContext);
                        },
                        child: const Text('Done'),
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
  }

  void _addTextBox() {
    _pushUndo();
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final box = <String, Object?>{
      'id': id,
      'x': .13,
      'y': .13,
      'width': .72,
      'height': .16,
      'text': '',
      'fontSize': 22.0,
      'color': _color.toARGB32(),
    };
    final boxes = _pageData['textBoxes'];
    if (boxes is List<Object?>) {
      boxes.add(box);
    } else {
      _pageData['textBoxes'] = <Object?>[box];
    }
    _textControllers[id] = TextEditingController();
    setState(() {});
    _scheduleSave();
  }

  void _removeTextBox(String id) {
    _pushUndo();
    final boxes = _pageData['textBoxes'];
    if (boxes is List) {
      boxes.removeWhere((value) => value is Map && value['id']?.toString() == id);
    }
    _textControllers.remove(id)?.dispose();
    setState(() {});
    _scheduleSave();
  }

  Future<void> _addImage() async {
    try {
      final file = await FilePicker.pickFile(type: FileType.image);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) throw StateError('The selected image is empty.');
      if (bytes.length > 25 * 1024 * 1024) {
        throw StateError('Images larger than 25 MB are not supported.');
      }
      _pushUndo();
      final image = <String, Object?>{
        'id': DateTime.now().microsecondsSinceEpoch.toString(),
        'name': file.name,
        'data': base64Encode(bytes),
        'x': .12,
        'y': .16,
        'width': .68,
        'height': .42,
      };
      final images = _pageData['images'];
      if (images is List<Object?>) {
        images.add(image);
      } else {
        _pageData['images'] = <Object?>[image];
      }
      _imageBytesCache[image['id']! as String] = bytes;
      setState(() {});
      _scheduleSave();
    } catch (error, stackTrace) {
      debugPrint('[Snote][EditorV2] image import failed: $error\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not insert image: $error')),
        );
      }
    }
  }

  Future<void> _addSticker() async {
    const stickers = <String>[
      '⭐', '✅', '❌', '💡', '📌', '📖', '🧠', '🎯', '❤️', '🔥', '⚠️', '💯',
      '🧪', '🔬', '🧬', '⚛️', '📐', '📈', '📝', '🏁', '🌱', '☀️', '🌙', '✨',
    ];
    final chosen = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: GridView.count(
            shrinkWrap: true,
            crossAxisCount: 6,
            children: stickers.map((sticker) => InkWell(
              onTap: () => Navigator.pop(sheetContext, sticker),
              child: Center(child: Text(sticker, style: const TextStyle(fontSize: 30))),
            )).toList(),
          ),
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    _pushUndo();
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final boxes = _pageData['textBoxes'] as List<Object?>;
    boxes.add(<String, Object?>{
      'id': id,
      'x': .42,
      'y': .34,
      'width': .22,
      'height': .12,
      'text': chosen,
      'fontSize': 50.0,
      'color': _color.toARGB32(),
      'sticker': true,
    });
    _textControllers[id] = TextEditingController(text: chosen);
    setState(() {});
    _scheduleSave();
  }

  Future<void> _chooseTemplate() async {
    final selected = await showModalBottomSheet<PageTemplate>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: GridView.builder(
            shrinkWrap: true,
            itemCount: PageTemplate.values.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.1,
            ),
            itemBuilder: (_, index) {
              final template = PageTemplate.values[index];
              return InkWell(
                onTap: () => Navigator.pop(sheetContext, template),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Expanded(
                        child: CustomPaint(
                          painter: PageBackground(
                            template: template,
                            paperColor: Color((_pageData['paperColor'] as num?)?.toInt() ?? 0xffffffff),
                            lineColor: Color((_pageData['lineColor'] as num?)?.toInt() ?? 0xffd8dee8),
                            spacing: ((_pageData['spacing'] as num?)?.toDouble() ?? 28).clamp(10, 80).toDouble(),
                            lineOpacity: ((_pageData['lineOpacity'] as num?)?.toDouble() ?? .85).clamp(0, 1).toDouble(),
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: Text(template.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    _pushUndo();
    _pageData['template'] = selected.name;
    setState(() {});
    _scheduleSave();
  }

  void _addPage() {
    _pushUndo();
    final previous = _pageData;
    final page = EditorV2DocumentCodec.normalizePage(<String, Object?>{
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'template': previous['template'] ?? 'dotted',
      'paperColor': previous['paperColor'] ?? 0xffffffff,
      'lineColor': previous['lineColor'] ?? 0xffd8dee8,
      'lineOpacity': previous['lineOpacity'] ?? .85,
      'spacing': previous['spacing'] ?? 28.0,
      'lineWidth': previous['lineWidth'] ?? .7,
      'pageSize': previous['pageSize'] ?? 'A4',
      'orientation': previous['orientation'] ?? 'vertical',
      'strokes': <Object?>[],
      'images': <Object?>[],
      'textBoxes': <Object?>[],
    });
    setState(() {
      final insertion = (_page + 1).clamp(0, _pages.length).toInt();
      _pages.insert(insertion, page);
      _page = insertion;
      _selectedStrokeIds.clear();
      _lassoRect = null;
    });
    _scheduleSave();
  }

  Future<void> _importPdf() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const <String>['pdf'],
      );
      if (file == null) return;
      final sourceBytes = await file.readAsBytes();
      if (sourceBytes.isEmpty) throw StateError('The selected PDF file is empty.');
      final existing = await _documents.listForNote(widget.note.id);
      final attached = existing.any((asset) =>
          asset.type.toLowerCase().contains('pdf') ||
          asset.name.toLowerCase().endsWith('.pdf'));
      if (!attached) {
        await _documents.saveBytes(
          noteId: widget.note.id,
          name: file.name,
          type: 'pdf',
          bytes: sourceBytes,
          metadata: const <String, dynamic>{'source': 'editor-v2-import'},
        );
      }
      final result = await _renderPdfPages(sourceBytes, file.name);
      if (!mounted || result.pages.isEmpty) return;
      _pushUndo();
      final insertion = (_page + 1).clamp(0, _pages.length).toInt();
      setState(() {
        _pages.insertAll(insertion, result.pages);
        _page = insertion;
      });
      _scheduleSave();
      final omitted = result.totalPages - result.pages.length;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(omitted > 0
                ? 'Imported ${result.pages.length} of ${result.totalPages} pages. The original PDF remains attached.'
                : 'Imported all ${result.totalPages} PDF pages.'),
          ),
        );
      }
    } catch (error, stackTrace) {
      debugPrint('[Snote][EditorV2] PDF import failed: $error\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF import failed; existing notes were preserved: $error')),
        );
      }
    }
  }

  void _copyPage(int index) {
    if (index < 0 || index >= _pages.length) return;
    _pageClipboard = EditorV2DocumentCodec.clonePages(<Map<String, Object?>>[_pages[index]]).single;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Page copied. Use Paste as page to insert it.')));
  }

  void _cutPage(int index) {
    if (index < 0 || index >= _pages.length) return;
    _copyPage(index);
    _deletePage(index);
  }

  void _pastePage() {
    final source = _pageClipboard;
    if (source == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copy a page first.')));
      return;
    }
    _pushUndo();
    final copy = EditorV2DocumentCodec.clonePages(<Map<String, Object?>>[source]).single;
    copy['id'] = DateTime.now().microsecondsSinceEpoch.toString();
    setState(() {
      final insertion = (_page + 1).clamp(0, _pages.length).toInt();
      _pages.insert(insertion, EditorV2DocumentCodec.normalizePage(copy));
      _page = insertion;
    });
    _scheduleSave();
  }

  void _duplicatePage(int index) {
    if (index < 0 || index >= _pages.length) return;
    _pageClipboard = EditorV2DocumentCodec.clonePages(<Map<String, Object?>>[_pages[index]]).single;
    _pastePage();
  }

  void _deletePage(int index) {
    if (index < 0 || index >= _pages.length) return;
    _pushUndo();
    setState(() {
      if (_pages.length == 1) {
        _pages[0]['strokes'] = <Object?>[];
        _pages[0]['images'] = <Object?>[];
        _pages[0]['textBoxes'] = <Object?>[];
        _pages[0].remove('backgroundImage');
      } else {
        _pages.removeAt(index);
      }
      _page = EditorV2DocumentCodec.clampPage(_page >= index ? _page - 1 : _page, _pages.length);
      _selectedStrokeIds.clear();
      _lassoRect = null;
      _initializeTextControllers();
    });
    _scheduleSave();
  }

  void _movePage(int from, int to) {
    if (from < 0 || from >= _pages.length || to < 0 || to >= _pages.length || from == to) return;
    _pushUndo();
    setState(() {
      final moved = _pages.removeAt(from);
      _pages.insert(to, moved);
      if (_page == from) {
        _page = to;
      } else if (from < _page && to >= _page) {
        _page--;
      } else if (from > _page && to <= _page) {
        _page++;
      }
    });
    _scheduleSave();
  }

  void _goToPage(int index) {
    if (index < 0 || index >= _pages.length || index == _page) return;
    setState(() {
      _page = index;
      _selectedStrokeIds.clear();
      _lassoRect = null;
    });
    _scheduleSave();
  }

  void _toggleBookmark() {
    final pageNumber = _page + 1;
    setState(() {
      if (_bookmarkedPages.contains(pageNumber)) {
        _bookmarkedPages.remove(pageNumber);
      } else {
        _bookmarkedPages.add(pageNumber);
        _bookmarkedPages.sort();
      }
    });
    _scheduleSave();
  }

  Future<void> _showBookmarks() async {
    if (_bookmarkedPages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No bookmarked pages yet.')),
      );
      return;
    }
    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => ListView(
        shrinkWrap: true,
        children: [
          const ListTile(title: Text('Bookmarked pages')),
          ..._bookmarkedPages.map((pageNumber) => ListTile(
                leading: const Icon(Icons.bookmark_rounded),
                title: Text('Page $pageNumber'),
                onTap: () => Navigator.pop(sheetContext, pageNumber - 1),
              )),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    _goToPage(EditorV2DocumentCodec.clampPage(selected, _pages.length));
  }

  Future<void> _exportPdf() async {
    if (_exporting || _pages.isEmpty) return;
    setState(() => _exporting = true);
    final originalPage = _page;
    final pdf = pw.Document();
    try {
      await _flushSave();
      for (var index = 0; index < _pages.length; index++) {
        if (!mounted) return;
        setState(() => _page = index);
        await WidgetsBinding.instance.endOfFrame;
        await Future<void>.delayed(const Duration(milliseconds: 80));
        final renderObject = _pageCaptureKey.currentContext?.findRenderObject();
        if (renderObject is! RenderRepaintBoundary) {
          throw StateError('Page ${index + 1} is not ready for capture.');
        }
        final image = await renderObject.toImage(pixelRatio: 1.5);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        if (data == null) throw StateError('Could not capture page ${index + 1}.');
        final bytes = data.buffer.asUint8List();
        pdf.addPage(pw.Page(
          pageFormat: pdfcore.PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.Center(
            child: pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.contain),
          ),
        ));
      }
      final output = await pdf.save();
      final uri = await FilePicker.saveFile(
        fileName: '${_safeFilename(_title.text)}.pdf',
        bytes: Uint8List.fromList(output),
        mimeType: 'application/pdf',
      );
      if (mounted && uri != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exported ${_pages.length} pages to PDF.')),
        );
      }
    } catch (error, stackTrace) {
      debugPrint('[Snote][EditorV2] PDF export failed: $error\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF export failed: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _page = EditorV2DocumentCodec.clampPage(originalPage, _pages.length);
          _exporting = false;
        });
      }
    }
  }

  String _safeFilename(String input) {
    final value = input.trim().replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '').trim();
    return value.isEmpty ? 'Snote' : value;
  }

  Future<void> _unlockNote() async {
    final controller = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Unlock note'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Note password'),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text), child: const Text('Unlock')),
        ],
      ),
    );
    controller.dispose();
    if (password == null || !mounted) return;
    try {
      final ok = await _lock.unlock(widget.note.id, password);
      if (!ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Incorrect password. Your saved note is unchanged.')),
          );
        }
        return;
      }
      if (mounted) {
        setState(() {
          _locked = false;
          _unlocked = true;
        });
      }
      await _loadDocument();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not unlock note: $error')),
        );
      }
    }
  }

  Future<void> _addFavoritePen() async {
    final nameController = TextEditingController(text: '${_tool.label} ${_favoritePens.length + 1}');
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Save to pen case'),
        content: TextField(controller: nameController, autofocus: true, decoration: const InputDecoration(labelText: 'Preset name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, nameController.text), child: const Text('Save preset')),
        ],
      ),
    );
    nameController.dispose();
    if (name == null || !mounted) return;
    setState(() {
      _favoritePens.add(<String, Object?>{
        'tool': _tool.name,
        'color': _color.toARGB32(),
        'size': _size,
        'opacity': _opacity,
        'pressureSensitivity': _pressureSensitivity,
        'velocitySensitivity': _velocitySensitivity,
        'pressureCurve': _pressureCurve.name,
        'label': name.trim().isEmpty ? _tool.label : name.trim(),
      });
      if (_favoritePens.length > 200) _favoritePens.removeAt(0);
    });
    await _saveFavoritePens();
    if (!_showFavoritesShowcase) {
      setState(() => _showFavoritesShowcase = true);
      await _settings.setBool('editorV2ShowFavoritesShowcase', true);
    }
  }

  void _applyFavorite(Map<String, Object?> favorite) {
    final toolName = favorite['tool']?.toString();
    final tool = CanvasTool.values.where((candidate) => candidate.name == toolName).firstOrNull;
    if (tool == null) return;
    setState(() {
      _tool = tool;
      _color = Color((favorite['color'] as num?)?.toInt() ?? 0xff17202a);
      _size = (favorite['size'] as num?)?.toDouble() ?? 3;
      _opacity = (favorite['opacity'] as num?)?.toDouble() ?? 1;
      _pressureSensitivity = (favorite['pressureSensitivity'] as num?)?.toDouble() ?? .55;
      _velocitySensitivity = (favorite['velocitySensitivity'] as num?)?.toDouble() ?? .65;
      _pressureCurve = PressureCurve.values.firstWhere(
        (candidate) => candidate.name == favorite['pressureCurve'],
        orElse: () => PressureCurve.linear,
      );
    });
    _rememberCurrentToolProfile();
  }

  Future<void> _removeFavorite(Map<String, Object?> favorite) async {
    setState(() => _favoritePens.remove(favorite));
    await _saveFavoritePens();
  }

  Future<void> _setToolbarDock(String value) async {
    setState(() {
      _toolbarDock = value;
      _floatingToolbar = false;
    });
    await _settings.setString('editorV2ToolbarDock', value);
    await _settings.setBool('editorV2FloatingToolbar', false);
  }

  Future<void> _toggleFloatingToolbar() async {
    setState(() => _floatingToolbar = !_floatingToolbar);
    await _settings.setBool('editorV2FloatingToolbar', _floatingToolbar);
  }

  Future<void> _toggleFavoritesOrientation() async {
    setState(() => _favoritesVertical = !_favoritesVertical);
    await _settings.setBool('editorV2FavoritesVertical', _favoritesVertical);
  }

  Future<void> _toggleFavoritesShowcase() async {
    setState(() => _showFavoritesShowcase = !_showFavoritesShowcase);
    await _settings.setBool('editorV2ShowFavoritesShowcase', _showFavoritesShowcase);
  }

  Future<void> _togglePageNavigation() async {
    setState(() => _showPageNavigation = !_showPageNavigation);
    await _settings.setBool('showPageNavigation', _showPageNavigation);
  }

  Future<void> _toggleFloatingPageNavigation() async {
    setState(() => _floatingPageNavigation = !_floatingPageNavigation);
    await _settings.setBool('editorV2FloatingPageNavigation', _floatingPageNavigation);
  }

  Future<void> _togglePageLock([int? requestedIndex]) async {
    final index = requestedIndex ?? _page;
    if (index < 0 || index >= _pages.length) return;
    final locked = _pages[index]['locked'] != true;
    setState(() => _pages[index]['locked'] = locked);
    _scheduleSave();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Page \${index + 1} \${locked ? 'locked' : 'unlocked'}')),
      );
    }
  }

  Future<void> _togglePalmRejection() async {
    final enabled = !_settings.getBool('palmRejection');
    await _settings.setBool('palmRejection', enabled);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Palm rejection ${enabled ? 'enabled' : 'disabled'}')),
      );
    }
  }

  Future<void> _showPageAndEditorSettings() async {
    var template = PageTemplate.values.firstWhere(
      (value) => value.name == _pageData['template']?.toString(),
      orElse: () => PageTemplate.dotted,
    );
    var spacing = ((_pageData['spacing'] as num?)?.toDouble() ?? 28).clamp(10.0, 80.0).toDouble();
    var opacity = ((_pageData['lineOpacity'] as num?)?.toDouble() ?? .85).clamp(0.0, 1.0).toDouble();
    var paper = Color((_pageData['paperColor'] as num?)?.toInt() ?? 0xffffffff);
    var line = Color((_pageData['lineColor'] as num?)?.toInt() ?? 0xffd8dee8);
    var palm = _settings.getBool('palmRejection');
    var showNavigation = _showPageNavigation;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Note page & editor settings', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                DropdownButtonFormField<PageTemplate>(
                  initialValue: template,
                  decoration: const InputDecoration(labelText: 'Page template'),
                  items: PageTemplate.values.map((value) => DropdownMenuItem(value: value, child: Text(value.name))).toList(),
                  onChanged: (value) { if (value != null) setSheetState(() => template = value); },
                ),
                const SizedBox(height: 12),
                const Text('Paper color'),
                const SizedBox(height: 6),
                Wrap(spacing: 9, runSpacing: 8, children: _palette.map((candidate) => InkWell(
                  onTap: () => setSheetState(() => paper = candidate),
                  child: Container(width: 27, height: 27, decoration: BoxDecoration(
                    color: candidate, shape: BoxShape.circle,
                    border: Border.all(color: paper == candidate ? Theme.of(context).colorScheme.primary : Colors.black26, width: paper == candidate ? 3 : 1),
                  )),
                )).toList()),
                const SizedBox(height: 12),
                const Text('Line / dot color'),
                const SizedBox(height: 6),
                Wrap(spacing: 9, children: _palette.where((candidate) => candidate != Colors.white).map((candidate) => InkWell(
                  onTap: () => setSheetState(() => line = candidate),
                  child: Container(width: 27, height: 27, decoration: BoxDecoration(
                    color: candidate, shape: BoxShape.circle,
                    border: Border.all(color: line == candidate ? Theme.of(context).colorScheme.primary : Colors.black26, width: line == candidate ? 3 : 1),
                  )),
                )).toList()),
                Text('Grid / dot spacing: ${spacing.round()}'),
                Slider(min: 10, max: 80, value: spacing, onChanged: (value) => setSheetState(() => spacing = value)),
                Text('Grid / dot opacity: ${(opacity * 100).round()}%'),
                Slider(min: 0, max: 1, value: opacity, onChanged: (value) => setSheetState(() => opacity = value)),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Palm rejection'),
                  subtitle: const Text('Ignore finger touches while the stylus is active'),
                  value: palm,
                  onChanged: (value) => setSheetState(() => palm = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show page navigation'),
                  value: showNavigation,
                  onChanged: (value) => setSheetState(() => showNavigation = value),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () async {
                      _pushUndo();
                      _pageData['template'] = template.name;
                      _pageData['spacing'] = spacing;
                      _pageData['lineOpacity'] = opacity;
                      _pageData['paperColor'] = paper.toARGB32();
                      _pageData['lineColor'] = line.toARGB32();
                      setState(() => _showPageNavigation = showNavigation);
                      await _settings.setBool('palmRejection', palm);
                      await _settings.setBool('showPageNavigation', showNavigation);
                      _scheduleSave();
                      if (sheetContext.mounted) Navigator.pop(sheetContext);
                    },
                    child: const Text('Save settings'),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  void _zoom(double factor) {
    final next = _transform.value.clone()..scale(factor);
    _transform.value = next;
  }

  Future<void> _startStudyTimer() async {
    final controller = TextEditingController(text: '25');
    final minutes = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Study timer'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Minutes', suffixText: 'min'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, int.tryParse(controller.text) ?? 25),
            child: const Text('Start'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (minutes == null || minutes <= 0 || !mounted) return;
    _studyTimer?.cancel();
    setState(() {
      _studyRemaining = minutes.clamp(1, 240).toInt() * 60;
      _studySeconds = 0;
    });
    _studyTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _studySeconds++;
        if (_studyRemaining > 0) _studyRemaining--;
      });
      if (_studyRemaining == 0) {
        timer.cancel();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Study timer complete. Take a short break.')),
        );
      }
    });
  }

  String get _clock {
    final minutes = _studyRemaining ~/ 60;
    final seconds = _studyRemaining % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void _onMenuSelected(String value) {
    switch (value) {
      case 'addPage':
        _addPage();
      case 'text':
        _addTextBox();
      case 'image':
        unawaited(_addImage());
      case 'sticker':
        unawaited(_addSticker());
      case 'pdf':
        unawaited(_importPdf());
      case 'export':
        unawaited(_exportPdf());
      case 'template':
        unawaited(_chooseTemplate());
      case 'bookmarks':
        unawaited(_showBookmarks());
      case 'timer':
        unawaited(_startStudyTimer());
      case 'favorite':
        unawaited(_addFavoritePen());
      case 'dockTop':
        unawaited(_setToolbarDock('top'));
      case 'dockBottom':
        unawaited(_setToolbarDock('bottom'));
      case 'dockLeft':
        unawaited(_setToolbarDock('left'));
      case 'dockRight':
        unawaited(_setToolbarDock('right'));
      case 'float':
        unawaited(_toggleFloatingToolbar());
      case 'favoritesOrientation':
        unawaited(_toggleFavoritesOrientation());
      case 'favoritesShowcase':
        unawaited(_toggleFavoritesShowcase());
      case 'pageNavigation':
        unawaited(_togglePageNavigation());
      case 'floatingPageNavigation':
        unawaited(_toggleFloatingPageNavigation());
      case 'palmRejection':
        unawaited(_togglePalmRejection());
      case 'pageSettings':
        unawaited(_showPageAndEditorSettings());
      case 'togglePageLock':
        unawaited(_togglePageLock());
      case 'pan':
        setState(() => _panMode = !_panMode);
      case 'zoomIn':
        _zoom(1.2);
      case 'zoomOut':
        _zoom(.83);
      case 'fit':
        final scale = (MediaQuery.sizeOf(context).width - 30).clamp(260, 816) / _pageWidth;
        _transform.value = Matrix4.identity()..scale(scale);
      case 'fullscreen':
        setState(() => _fullScreenMode = !_fullScreenMode);
      case 'save':
        unawaited(_save(force: true));
    }
  }

  IconData _toolIcon(CanvasTool tool) {
    return switch (tool) {
      CanvasTool.ballpoint => Icons.edit_rounded,
      CanvasTool.fountain => Icons.draw_rounded,
      CanvasTool.pencil => Icons.create_rounded,
      CanvasTool.highlighter => Icons.brush_rounded,
      CanvasTool.marker => Icons.border_color_rounded,
      CanvasTool.brush => Icons.format_paint_rounded,
      CanvasTool.eraser => Icons.cleaning_services_rounded,
      CanvasTool.pixelEraser => Icons.auto_fix_normal_rounded,
      CanvasTool.lasso => Icons.gesture_rounded,
      CanvasTool.line || CanvasTool.dashedLine || CanvasTool.dottedLine => Icons.horizontal_rule_rounded,
      CanvasTool.arrow || CanvasTool.vectorArrow => Icons.trending_flat_rounded,
      CanvasTool.rectangle || CanvasTool.roundedRectangle => Icons.crop_square_rounded,
      CanvasTool.ellipse || CanvasTool.circle => Icons.circle_outlined,
      CanvasTool.triangle => Icons.change_history_rounded,
      CanvasTool.diamond => Icons.diamond_outlined,
      CanvasTool.star => Icons.star_border_rounded,
      CanvasTool.ruler || CanvasTool.divider => Icons.straighten_rounded,
      CanvasTool.compass || CanvasTool.protractor => Icons.architecture_rounded,
      CanvasTool.sticker => Icons.emoji_emotions_outlined,
      _ when tool.isPen => Icons.edit_rounded,
      _ when tool.isMeasurementTool => Icons.architecture_rounded,
      _ => Icons.category_outlined,
    };
  }

  Widget _buildToolbar({required bool vertical}) {
    Widget action({required String tooltip, required IconData icon, required VoidCallback onPressed, Color? color}) =>
        IconButton(
          visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
          padding: const EdgeInsets.all(4),
          constraints: const BoxConstraints.tightFor(width: 32, height: 32),
          tooltip: tooltip,
          onPressed: onPressed,
          icon: Icon(icon, size: 19, color: color),
        );
    final actions = <Widget>[
      action(tooltip: _panMode ? 'Exit pan mode' : 'Pan / zoom', icon: _panMode ? Icons.pan_tool : Icons.pan_tool_outlined, onPressed: () => setState(() => _panMode = !_panMode)),
      action(tooltip: 'Undo', icon: Icons.undo_rounded, onPressed: _undo),
      action(tooltip: 'Redo', icon: Icons.redo_rounded, onPressed: _redo),
      action(tooltip: _textMode ? 'Handwriting mode' : 'Rich text mode', icon: _textMode ? Icons.draw_rounded : Icons.text_fields_rounded, onPressed: () => setState(() { _textMode = !_textMode; _scheduleSave(); })),
      action(tooltip: 'Color palette', icon: Icons.palette_outlined, color: _color, onPressed: _chooseColor),
      action(tooltip: 'Tool settings', icon: Icons.tune_rounded, onPressed: () => _strokeSettings()),
      action(tooltip: 'Text box', icon: Icons.text_fields_rounded, onPressed: _addTextBox),
      action(tooltip: 'Scientific calculator', icon: Icons.calculate_outlined, onPressed: _openCalculator),
      action(tooltip: 'All tools / categories', icon: Icons.apps_rounded, onPressed: _openToolPicker),
      action(tooltip: 'Save current tool to pen case', icon: Icons.add_circle_outline_rounded, onPressed: _addFavoritePen),
    ];
    final quickButtons = _quickTools.map((tool) => Padding(
      padding: const EdgeInsets.all(1),
      child: Tooltip(
        message: '${tool.label}\nDouble-tap for its own settings',
        child: GestureDetector(
          onDoubleTap: () => _strokeSettings(tool),
          child: Material(
            color: _tool == tool ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: _tool == tool ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .65)),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _selectTool(tool),
              child: SizedBox(width: 31, height: 31, child: Icon(_toolIcon(tool), size: 18, color: _tool == tool ? Theme.of(context).colorScheme.primary : null)),
            ),
          ),
        ),
      ),
    )).toList();
    final children = <Widget>[
      ...actions,
      if (!vertical) const VerticalDivider(width: 5, indent: 6, endIndent: 6),
      ...quickButtons,
      action(tooltip: 'Insert page', icon: Icons.note_add_outlined, onPressed: _addPage),
      action(tooltip: 'Page template', icon: Icons.grid_on_rounded, onPressed: _chooseTemplate),
      PopupMenuButton<String>(
        tooltip: 'Workspace options',
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
        onSelected: _onMenuSelected,
        itemBuilder: (_) => const <PopupMenuEntry<String>>[
          PopupMenuItem(value: 'text', child: Text('Insert text box')),
          PopupMenuItem(value: 'image', child: Text('Insert image')),
          PopupMenuItem(value: 'sticker', child: Text('Sticker library')),
          PopupMenuItem(value: 'pdf', child: Text('Import / annotate PDF')),
          PopupMenuItem(value: 'export', child: Text('Export pages to PDF')),
          PopupMenuItem(value: 'bookmarks', child: Text('Bookmarks')),
          PopupMenuItem(value: 'timer', child: Text('Study timer')),
          PopupMenuDivider(),
          PopupMenuItem(value: 'dockTop', child: Text('Dock toolbar to top')),
          PopupMenuItem(value: 'dockBottom', child: Text('Dock toolbar to bottom')),
          PopupMenuItem(value: 'dockLeft', child: Text('Dock toolbar to left')),
          PopupMenuItem(value: 'dockRight', child: Text('Dock toolbar to right')),
          PopupMenuItem(value: 'float', child: Text('Toggle floating toolbar')),
          PopupMenuItem(value: 'favoritesShowcase', child: Text('Show / hide favorite pen case')),
          PopupMenuItem(value: 'favoritesOrientation', child: Text('Rotate pen case')),
          PopupMenuItem(value: 'pageNavigation', child: Text('Show / hide page navigation')),
          PopupMenuItem(value: 'floatingPageNavigation', child: Text('Toggle movable vertical page bar')),
          PopupMenuItem(value: 'palmRejection', child: Text('Toggle palm rejection')),
          PopupMenuItem(value: 'pageSettings', child: Text('Note page and editor settings')),
          PopupMenuItem(value: 'zoomIn', child: Text('Zoom in')),
          PopupMenuItem(value: 'zoomOut', child: Text('Zoom out')),
          PopupMenuItem(value: 'fit', child: Text('Fit page to width')),
          PopupMenuItem(value: 'fullscreen', child: Text('Toggle full screen')),
          PopupMenuItem(value: 'save', child: Text('Save now')),
        ],
        icon: const Icon(Icons.more_horiz_rounded, size: 20),
      ),
    ];
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .97),
      elevation: 2,
      borderRadius: BorderRadius.circular(vertical ? 12 : 10),
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: vertical ? 2 : 3, vertical: vertical ? 3 : 2),
        scrollDirection: vertical ? Axis.vertical : Axis.horizontal,
        child: vertical ? Column(mainAxisSize: MainAxisSize.min, children: children) : Row(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }

  Widget _buildFavoriteShowcase() {
    final chips = _favoritePens.map((favorite) {
      final favoriteTool = CanvasTool.values.where((tool) => tool.name == favorite['tool']?.toString()).firstOrNull ?? CanvasTool.ballpoint;
      final color = Color((favorite['color'] as num?)?.toInt() ?? 0xff17202a);
      final active = _tool == favoriteTool && _color.toARGB32() == color.toARGB32() && (_size - ((favorite['size'] as num?)?.toDouble() ?? 3)).abs() < .1;
      return Tooltip(
        message: '${favorite['label'] ?? favoriteTool.label}\nTap to select • long-press to remove',
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: () => _applyFavorite(favorite),
          onLongPress: () => _removeFavorite(favorite),
          child: Container(
            width: _favoritesVertical ? 38 : 42,
            height: _favoritesVertical ? 42 : 38,
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: active ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: active ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(_toolIcon(favoriteTool), size: 17, color: color),
                Container(margin: const EdgeInsets.only(top: 3), width: 18, height: 2, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
              ],
            ),
          ),
        ),
      );
    }).toList();
    return Positioned(
      left: _favoriteOffset.dx.clamp(0, math.max(0, MediaQuery.sizeOf(context).width - 120)).toDouble(),
      top: _favoriteOffset.dy.clamp(0, math.max(0, MediaQuery.sizeOf(context).height - 120)).toDouble(),
      child: GestureDetector(
        onPanUpdate: (details) => setState(() => _favoriteOffset += details.delta),
        child: Material(
          elevation: 7,
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.drag_indicator_rounded, size: 14),
                  const SizedBox(width: 3),
                  const Text('PEN CASE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: .6)),
                  const SizedBox(width: 3),
                  InkWell(onTap: _toggleFavoritesOrientation, child: Icon(_favoritesVertical ? Icons.swap_vert_rounded : Icons.swap_horiz_rounded, size: 14)),
                ]),
                const SizedBox(height: 2),
                if (_favoritesVertical)
                  ConstrainedBox(constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .55), child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: chips)))
                else
                  ConstrainedBox(constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .72), child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(mainAxisSize: MainAxisSize.min, children: chips))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingPageNavigation() {
    return Positioned(
      left: _pageNavOffset.dx.clamp(0, math.max(0, MediaQuery.sizeOf(context).width - 52)).toDouble(),
      top: _pageNavOffset.dy.clamp(0, math.max(0, MediaQuery.sizeOf(context).height - 150)).toDouble(),
      child: GestureDetector(
        onPanUpdate: (details) => setState(() => _pageNavOffset += details.delta),
        child: Material(
          elevation: 6,
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.drag_indicator_rounded, size: 16),
              IconButton(visualDensity: VisualDensity.compact, constraints: const BoxConstraints.tightFor(width: 34, height: 30), tooltip: 'Previous page', onPressed: _page > 0 ? () => _goToPage(_page - 1) : null, icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 19)),
              InkWell(onTap: _showPagePicker, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3), child: Text('${_page + 1}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900)))),
              IconButton(visualDensity: VisualDensity.compact, constraints: const BoxConstraints.tightFor(width: 34, height: 30), tooltip: 'Next page', onPressed: _page + 1 < _pages.length ? () => _goToPage(_page + 1) : _addPage, icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 19)),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _openCalculator() async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black38,
      builder: (_) => _ScientificCalculatorDialog(
        initialWidth: _calculatorWidth,
        initialHeight: _calculatorHeight,
        onResize: (width, height) {
          _calculatorWidth = width;
          _calculatorHeight = height;
        },
      ),
    );
  }

  Widget _buildPageBackground(Map<String, Object?> page) {
    final source = page['backgroundImage'];
    if (source is String && source.isNotEmpty) {
      try {
        final id = page['id']?.toString() ?? source.hashCode.toString();
        final bytes = _backgroundBytesCache.putIfAbsent(id, () => base64Decode(source));
        return Image.memory(
          bytes,
          fit: BoxFit.fill,
          errorBuilder: (_, error, stackTrace) => ColoredBox(
            color: const Color(0xfffff8e7),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text('Page background could not be rendered.\n$error', textAlign: TextAlign.center),
              ),
            ),
          ),
        );
      } catch (error) {
        return ColoredBox(
          color: const Color(0xfffff8e7),
          child: Center(child: Text('Saved page image is unreadable: $error')),
        );
      }
    }
    final template = PageTemplate.values.firstWhere(
      (value) => value.name == page['template']?.toString(),
      orElse: () => PageTemplate.dotted,
    );
    return CustomPaint(
      painter: PageBackground(
        template: template,
        paperColor: Color((page['paperColor'] as num?)?.toInt() ?? 0xffffffff),
        lineColor: Color((page['lineColor'] as num?)?.toInt() ?? 0xffd8dee8),
        spacing: ((page['spacing'] as num?)?.toDouble() ?? 28).clamp(10, 80).toDouble(),
        lineOpacity: ((page['lineOpacity'] as num?)?.toDouble() ?? .85).clamp(0, 1).toDouble(),
        lineWidth: ((page['lineWidth'] as num?)?.toDouble() ?? .7).clamp(.25, 4).toDouble(),
        cornellAssist: page['cornellAssist'] == true,
      ),
      child: const SizedBox.expand(),
    );
  }

  Widget _buildImages(Map<String, Object?> page) {
    final raw = page['images'];
    if (raw is! List) return const SizedBox.shrink();
    final children = <Widget>[];
    for (final item in raw.whereType<Map>()) {
      final image = item.map<String, Object?>((key, value) => MapEntry(key.toString(), value));
      final id = image['id']?.toString() ?? '';
      final encoded = image['data']?.toString() ?? '';
      if (encoded.isEmpty) continue;
      try {
        final bytes = _imageBytesCache.putIfAbsent(id.isEmpty ? encoded.hashCode.toString() : id, () => base64Decode(encoded));
        final x = (image['x'] as num?)?.toDouble() ?? .1;
        final y = (image['y'] as num?)?.toDouble() ?? .1;
        final width = (image['width'] as num?)?.toDouble() ?? .4;
        final height = (image['height'] as num?)?.toDouble() ?? .3;
        children.add(Positioned(
          left: x * _pageWidth,
          top: y * _pageHeight,
          width: width * _pageWidth,
          height: height * _pageHeight,
          child: Image.memory(bytes, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined)),
        ));
      } catch (_) {}
    }
    return Stack(clipBehavior: Clip.none, children: children);
  }

  Widget _buildTextBoxes(Map<String, Object?> page) {
    final raw = page['textBoxes'];
    if (raw is! List) return const SizedBox.shrink();
    final children = <Widget>[];
    for (final item in raw.whereType<Map>()) {
      final box = item.map<String, Object?>((key, value) => MapEntry(key.toString(), value));
      final id = box['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final controller = _textControllers.putIfAbsent(
        id,
        () => TextEditingController(text: box['text']?.toString() ?? ''),
      );
      final x = (box['x'] as num?)?.toDouble() ?? .12;
      final y = (box['y'] as num?)?.toDouble() ?? .12;
      final width = (box['width'] as num?)?.toDouble() ?? .68;
      final height = (box['height'] as num?)?.toDouble() ?? .16;
      final fontSize = (box['fontSize'] as num?)?.toDouble() ?? 18;
      final color = Color((box['color'] as num?)?.toInt() ?? 0xff263238);
      children.add(Positioned(
        left: x * _pageWidth,
        top: y * _pageHeight,
        width: width * _pageWidth,
        height: height * _pageHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: (box['sticker'] == true ? Colors.transparent : Colors.white).withValues(alpha: .12),
            border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: .25)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: TextField(
                  controller: controller,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  style: TextStyle(fontSize: fontSize, color: color, height: 1.15),
                  onChanged: (value) {
                    box['text'] = value;
                    _scheduleSave();
                  },
                  decoration: InputDecoration(
                    hintText: box['sticker'] == true ? '' : 'Write text…',
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.fromLTRB(6, 4, 22, 4),
                  ),
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 22, height: 22),
                  tooltip: 'Remove text box',
                  onPressed: () => _removeTextBox(id),
                  icon: const Icon(Icons.close_rounded, size: 12),
                ),
              ),
            ],
          ),
        ),
      ));
    }
    return Stack(clipBehavior: Clip.none, children: children);
  }

  Widget _buildPageSurface() {
    final page = _pageData;
    final strokes = _strokesFor(page);
    final live = _liveStroke;
    final selected = Set<String>.from(_selectedStrokeIds);
    return RepaintBoundary(
      key: _pageCaptureKey,
      child: Container(
        width: _pageWidth,
        height: _pageHeight,
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.black.withValues(alpha: .18)),
          boxShadow: const <BoxShadow>[
            BoxShadow(color: Color(0x22000000), blurRadius: 12, offset: Offset(0, 3)),
          ],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(child: _buildPageBackground(page)),
            if (_textMode)
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(42),
                  child: QuillEditor(
                    focusNode: _quillFocus,
                    scrollController: _quillScroll,
                    controller: _quill,
                    config: const QuillEditorConfig(
                      placeholder: 'Start writing rich text…',
                    ),
                  ),
                ),
              ),
            if (!_textMode)
              Positioned.fill(
                child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _onPointerDown,
                onPointerMove: _onPointerMove,
                onPointerUp: _onPointerUp,
                onPointerCancel: _onPointerCancel,
                onPointerHover: (event) {
                  if (_tool == CanvasTool.eraser || _tool == CanvasTool.pixelEraser) {
                    _eraserCursor = event.localPosition;
                    setState(() {});
                  }
                },
                child: CustomPaint(
                  painter: EditorV2InkPainter(
                    strokes: strokes,
                    liveStroke: live,
                    selectedStrokeIds: selected,
                    eraserCursor: _tool == CanvasTool.eraser || _tool == CanvasTool.pixelEraser ? _eraserCursor : null,
                    eraserRadius: _tool == CanvasTool.pixelEraser ? 7 : math.max(18, _size * 2).toDouble(),
                  ),
                  size: const Size(_pageWidth, _pageHeight),
                ),
              ),
            ),
            Positioned.fill(child: _buildImages(page)),
            Positioned.fill(child: IgnorePointer(ignoring: page['locked'] == true, child: _buildTextBoxes(page))),
            if (_lassoRect != null)
              Positioned(
                left: math.min(_lassoRect!.left, _lassoRect!.right),
                top: math.min(_lassoRect!.top, _lassoRect!.bottom),
                width: math.max(1, _lassoRect!.width).toDouble(),
                height: math.max(1, _lassoRect!.height).toDouble(),
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xff3979e8), width: 1.2),
                      color: const Color(0x183979e8),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCanvas() {
    return LayoutBuilder(
      builder: (context, constraints) => ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: Center(
          child: InteractiveViewer(
            transformationController: _transform,
            constrained: false,
            alignment: Alignment.topLeft,
            panEnabled: _panMode,
            scaleEnabled: true,
            minScale: .25,
            maxScale: 4,
            boundaryMargin: const EdgeInsets.all(220),
            onInteractionStart: (details) {
              if (details.pointerCount > 1 && _activePointer != null) {
                _ignoredPointers.add(_activePointer!);
                _activePointer = null;
                _gestureStart = null;
                _livePoints = <StrokePoint>[];
                _liveStroke = null;
                setState(() {});
              }
            },
            child: _buildPageSurface(),
          ),
        ),
      ),
    );
  }

  Widget _buildPageFooter() {
    final isBookmarked = _bookmarkedPages.contains(_page + 1);
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -120 && _page + 1 < _pages.length) {
          _goToPage(_page + 1);
        } else if (velocity > 120 && _page > 0) {
          _goToPage(_page - 1);
        }
      },
      onVerticalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -120 && _page + 1 < _pages.length) {
          _goToPage(_page + 1);
        } else if (velocity > 120 && _page > 0) {
          _goToPage(_page - 1);
        }
      },
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        child: SizedBox(
          height: 36,
          child: Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(width: 32, height: 30),
                tooltip: 'Previous page',
                onPressed: _page > 0 ? () => _goToPage(_page - 1) : null,
                icon: const Icon(Icons.chevron_left_rounded, size: 20),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: _showPagePicker,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                  child: Text(
                    '${_page + 1}/${_pages.length}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(width: 30, height: 30),
                tooltip: isBookmarked ? 'Remove bookmark' : 'Bookmark page',
                onPressed: _toggleBookmark,
                icon: Icon(isBookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, size: 17),
              ),
              if (_selectedStrokeIds.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Text('${_selectedStrokeIds.length} selected', style: const TextStyle(fontSize: 10)),
                ),
              const Spacer(),
              if (_saving || _savePending)
                const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2))
              else
                const Icon(Icons.cloud_done_outlined, size: 15),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(width: 32, height: 30),
                tooltip: 'Next page',
                onPressed: _page + 1 < _pages.length ? () => _goToPage(_page + 1) : _addPage,
                icon: const Icon(Icons.chevron_right_rounded, size: 20),
              ),
              PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(width: 30, height: 30),
                tooltip: 'Page actions',
                onSelected: (action) {
                  switch (action) {
                    case 'add':
                      _addPage();
                    case 'copy':
                      _copyPage(_page);
                    case 'cut':
                      _cutPage(_page);
                    case 'duplicate':
                      _duplicatePage(_page);
                    case 'paste':
                      _pastePage();
                    case 'background':
                      unawaited(_chooseTemplate());
                    case 'delete':
                      _deletePage(_page);
                    case 'preview':
                      unawaited(_showPagePicker());
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'add', child: Text('Insert blank page')),
                  PopupMenuItem(value: 'copy', child: Text('Copy page')),
                  PopupMenuItem(value: 'cut', child: Text('Cut page')),
                  PopupMenuItem(value: 'paste', child: Text('Paste as page')),
                  PopupMenuItem(value: 'duplicate', child: Text('Duplicate page')),
                  PopupMenuItem(value: 'background', child: Text('Change background')),
                  PopupMenuItem(value: 'preview', child: Text('Page preview / reorder')),
                  PopupMenuDivider(),
                  PopupMenuItem(value: 'delete', child: Text('Delete page')),
                ],
                icon: const Icon(Icons.more_vert_rounded, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showPagePicker() async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * .78,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
              child: Row(children: [
                Expanded(child: Text('Pages • ${_pages.length}', style: Theme.of(context).textTheme.titleLarge)),
                IconButton(
                  tooltip: 'Paste copied page after current',
                  onPressed: _pageClipboard == null ? null : () {
                    Navigator.pop(sheetContext);
                    _pastePage();
                  },
                  icon: const Icon(Icons.content_paste_rounded),
                ),
                IconButton(
                  tooltip: 'Insert blank page',
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _addPage();
                  },
                  icon: const Icon(Icons.note_add_outlined),
                ),
              ]),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 0, 18, 8),
              child: Align(alignment: Alignment.centerLeft, child: Text('Drag a page to reorder it. Open ⋮ for page actions.', style: TextStyle(fontSize: 12))),
            ),
            Expanded(
              child: ReorderableListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                itemCount: _pages.length,
                onReorder: (oldIndex, newIndex) {
                  if (newIndex > oldIndex) newIndex--;
                  _movePage(oldIndex, newIndex);
                },
                itemBuilder: (_, index) {
                  final page = _pages[index];
                  final template = page['template']?.toString() ?? 'PDF';
                  final isPdf = page['backgroundImage'] is String && (page['backgroundImage'] as String).isNotEmpty;
                  return Card(
                    key: ValueKey(page['id']?.toString() ?? 'page-$index'),
                    color: index == _page ? Theme.of(context).colorScheme.primaryContainer : null,
                    child: ListTile(
                      leading: SizedBox(
                        width: 38,
                        height: 48,
                        child: CustomPaint(
                          painter: PageBackground(
                            template: PageTemplate.values.firstWhere((value) => value.name == template, orElse: () => PageTemplate.blank),
                            paperColor: Color((page['paperColor'] as num?)?.toInt() ?? 0xffffffff),
                            lineColor: Color((page['lineColor'] as num?)?.toInt() ?? 0xffd8dee8),
                            spacing: 8,
                            lineOpacity: ((page['lineOpacity'] as num?)?.toDouble() ?? .85).clamp(0, 1).toDouble(),
                          ),
                          child: Center(child: Text('${index + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900))),
                        ),
                      ),
                      title: Text('Page ${index + 1}'),
                      subtitle: Text(isPdf ? 'PDF background / annotations' : template),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_bookmarkedPages.contains(index + 1)) const Icon(Icons.bookmark_rounded, size: 18),
                          PopupMenuButton<String>(
                            tooltip: 'Page actions',
                            onSelected: (action) {
                              switch (action) {
                                case 'copy':
                                  _copyPage(index);
                                case 'cut':
                                  Navigator.pop(sheetContext);
                                  _cutPage(index);
                                case 'duplicate':
                                  Navigator.pop(sheetContext);
                                  _duplicatePage(index);
                                case 'paste':
                                  Navigator.pop(sheetContext);
                                  setState(() => _page = index);
                                  _pastePage();
                                case 'background':
                                  Navigator.pop(sheetContext);
                                  setState(() => _page = index);
                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                    if (mounted) unawaited(_chooseTemplate());
                                  });
                                case 'up':
                                  _movePage(index, math.max(0, index - 1));
                                case 'down':
                                  _movePage(index, math.min(_pages.length - 1, index + 1));
                                case 'lock':
                                  unawaited(_togglePageLock(index));
                                case 'delete':
                                  Navigator.pop(sheetContext);
                                  _deletePage(index);
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'copy', child: Text('Copy page')),
                              PopupMenuItem(value: 'cut', child: Text('Cut page')),
                              PopupMenuItem(value: 'paste', child: Text('Paste copied page after this')),
                              PopupMenuItem(value: 'duplicate', child: Text('Duplicate page')),
                              PopupMenuItem(value: 'background', child: Text('Change page background')),
                              PopupMenuItem(value: 'lock', child: Text('Lock / unlock this page')),
                              PopupMenuItem(value: 'up', child: Text('Move page up')),
                              PopupMenuItem(value: 'down', child: Text('Move page down')),
                              PopupMenuDivider(),
                              PopupMenuItem(value: 'delete', child: Text('Delete page')),
                            ],
                            icon: const Icon(Icons.more_vert_rounded),
                          ),
                        ],
                      ),
                      onTap: () => Navigator.pop(sheetContext, index),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _page = EditorV2DocumentCodec.clampPage(selected, _pages.length);
      _selectedStrokeIds.clear();
      _lassoRect = null;
    });
  }

  Widget _buildLockedBody() => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline_rounded, size: 48),
                  const SizedBox(height: 12),
                  const Text('This note is locked', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  const Text('Your saved content is protected. Unlock the note to edit it.', textAlign: TextAlign.center),
                  const SizedBox(height: 14),
                  FilledButton.icon(onPressed: _unlockNote, icon: const Icon(Icons.lock_open_rounded), label: const Text('Unlock note')),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _buildErrorBody() => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded, size: 46, color: Colors.deepOrange),
                  const SizedBox(height: 12),
                  const Text('Could not render this note', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Text(_loadError ?? 'Unknown document error', textAlign: TextAlign.center),
                  const SizedBox(height: 10),
                  const Text('Snote has not replaced the saved content with a blank page.', textAlign: TextAlign.center),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton.icon(onPressed: _prepare, icon: const Icon(Icons.refresh_rounded), label: const Text('Retry')),
                      OutlinedButton(onPressed: () => Navigator.maybePop(context), child: const Text('Back to notes')),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _fullScreenMode ? null : AppBar(
        leading: BackButton(
          onPressed: () async {
            await _flushSave();
            if (mounted) Navigator.maybePop(context);
          },
        ),
        titleSpacing: 0,
        title: TextField(
          controller: _title,
          maxLines: 1,
          onChanged: (_) => _scheduleSave(),
          onSubmitted: (_) => _save(force: true),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          decoration: const InputDecoration(
            hintText: 'Untitled note',
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(horizontal: 6),
          ),
        ),
        actions: [
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Undo',
            onPressed: _undoStack.isEmpty ? null : _undo,
            icon: const Icon(Icons.undo_rounded),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Redo',
            onPressed: _redoStack.isEmpty ? null : _redo,
            icon: const Icon(Icons.redo_rounded),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Page previews and reorder',
            onPressed: _showPagePicker,
            icon: const Icon(Icons.view_carousel_outlined),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Scientific calculator',
            onPressed: _openCalculator,
            icon: const Icon(Icons.calculate_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: 'Note and application controls',
            onSelected: _onMenuSelected,
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'fit', child: Text('Fit page to width')),
              const PopupMenuItem(value: 'fullscreen', child: Text('Toggle full screen')),
              const PopupMenuItem(value: 'text', child: Text('Toggle rich text / handwriting')),
              const PopupMenuItem(value: 'image', child: Text('Insert screenshot or image')),
              const PopupMenuItem(value: 'pageSettings', child: Text('Note page settings')),
              PopupMenuItem(
                value: 'togglePageLock',
                child: Text(_pageData['locked'] == true ? 'Unlock current page' : 'Lock current page'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'save', child: Text('Save note now')),
              const PopupMenuItem(value: 'export', child: Text('Export annotated document to PDF')),
            ],
            icon: const Icon(Icons.more_vert_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _locked && !_unlocked
              ? _buildLockedBody()
              : _loadError != null
                  ? _buildErrorBody()
                  : _buildEditorLayout(),
    );
  }

  Widget _buildEditorLayout() {
    final viewport = Expanded(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: _buildCanvas()),
          if (_floatingToolbar || _fullScreenMode)
            Positioned(
              left: _floatingOffset.dx.clamp(0, math.max(0, MediaQuery.sizeOf(context).width - 160)).toDouble(),
              top: _floatingOffset.dy.clamp(0, math.max(0, MediaQuery.sizeOf(context).height - 210)).toDouble(),
              child: GestureDetector(
                onPanUpdate: (details) => setState(() => _floatingOffset += details.delta),
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(12),
                  clipBehavior: Clip.antiAlias,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: math.min(360, MediaQuery.sizeOf(context).width - 16),
                      maxHeight: math.min(190, MediaQuery.sizeOf(context).height * .5),
                    ),
                    child: _buildToolbar(vertical: false),
                  ),
                ),
              ),
            ),
          if (_showFavoritesShowcase) _buildFavoriteShowcase(),
          if (_showPageNavigation && _floatingPageNavigation) _buildFloatingPageNavigation(),
          if (_fullScreenMode)
            Positioned(
              right: 8,
              top: 8,
              child: Material(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                shape: const CircleBorder(),
                elevation: 5,
                child: IconButton(
                  tooltip: 'Exit full screen',
                  onPressed: () => setState(() => _fullScreenMode = false),
                  icon: const Icon(Icons.fullscreen_exit_rounded),
                ),
              ),
            ),
        ],
      ),
    );

    final canvasWithFooter = Column(
      children: [
        viewport,
        if (!_fullScreenMode && _showPageNavigation && !_floatingPageNavigation) _buildPageFooter(),
      ],
    );

    if (_fullScreenMode) {
      return Column(children: [canvasWithFooter]);
    }

    switch (_toolbarDock) {
      case 'bottom':
        return Column(
          children: [
            Expanded(child: canvasWithFooter),
            if (!_floatingToolbar) _buildToolbar(vertical: false),
          ],
        );
      case 'left':
        return Row(
          children: [
            if (!_floatingToolbar)
              SizedBox(
                width: 40,
                child: _buildToolbar(vertical: true),
              ),
            Expanded(child: canvasWithFooter),
          ],
        );
      case 'right':
        return Row(
          children: [
            Expanded(child: canvasWithFooter),
            if (!_floatingToolbar)
              SizedBox(
                width: 40,
                child: _buildToolbar(vertical: true),
              ),
          ],
        );
      default:
        return Column(
          children: [
            if (!_floatingToolbar) _buildToolbar(vertical: false),
            Expanded(child: canvasWithFooter),
          ],
        );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    _studyTimer?.cancel();
    if (!_loading && _pages.isNotEmpty) unawaited(_flushSave());
    _title.dispose();
    _quill.removeListener(_scheduleSave);
    _quill.dispose();
    _quillFocus.dispose();
    _quillScroll.dispose();
    _transform.dispose();
    for (final controller in _textControllers.values) {
      controller.dispose();
    }
    unawaited(WakelockPlus.disable().catchError((Object error) {
      debugPrint('[Snote][EditorV2] wakelock release failed: $error');
    }));
    super.dispose();
  }
}

class _ScientificCalculatorDialog extends StatefulWidget {
  final double initialWidth;
  final double initialHeight;
  final void Function(double width, double height) onResize;

  const _ScientificCalculatorDialog({
    required this.initialWidth,
    required this.initialHeight,
    required this.onResize,
  });

  @override
  State<_ScientificCalculatorDialog> createState() => _ScientificCalculatorDialogState();
}

class _ScientificCalculatorDialogState extends State<_ScientificCalculatorDialog> {
  final TextEditingController _expression = TextEditingController();
  String _answer = '0';
  String? _error;
  bool _degrees = true;
  double _width = 330;
  double _height = 470;

  static const List<String> _keys = <String>[
    'sin', 'cos', 'tan', '√', '(', ')', '⌫',
    'C', 'ln', 'log', 'π', '^', '÷', '×',
    '7', '8', '9', 'AC', '4', '5', '6', '−',
    '1', '2', '3', '+', '0', '.', 'e', '=',
  ];

  @override
  void initState() {
    super.initState();
    _width = widget.initialWidth;
    _height = widget.initialHeight;
  }

  void _press(String key) {
    setState(() {
      _error = null;
      if (key == 'C' || key == 'AC') {
        _expression.clear();
        _answer = '0';
        return;
      }
      if (key == '⌫') {
        final text = _expression.text;
        if (text.isNotEmpty) {
          _expression.text = text.substring(0, text.length - 1);
          _expression.selection = TextSelection.collapsed(offset: _expression.text.length);
        }
        return;
      }
      if (key == '=') {
        try {
          final value = _ScientificExpressionParser(_expression.text, degrees: _degrees).parse();
          if (!value.isFinite) throw const FormatException('Result is not finite');
          _answer = value.abs() < 1e-12 ? '0' : _format(value);
        } catch (error) {
          _error = 'Invalid expression';
        }
        return;
      }
      final insert = switch (key) {
        '√' => 'sqrt(',
        'π' => 'pi',
        '÷' => '/',
        '×' => '*',
        '−' => '-',
        'sin' || 'cos' || 'tan' || 'ln' || 'log' => '$key(',
        _ => key,
      };
      _expression.text += insert;
      _expression.selection = TextSelection.collapsed(offset: _expression.text.length);
    });
  }

  String _format(double value) {
    final fixed = value.toStringAsPrecision(10);
    return fixed.contains('.') ? fixed.replaceFirst(RegExp(r'\.?0+
  final CanvasTool selected;
  const _EditorV2ToolPicker({required this.selected});

  @override
  State<_EditorV2ToolPicker> createState() => _EditorV2ToolPickerState();
}

class _EditorV2ToolPickerState extends State<_EditorV2ToolPicker> {
  final TextEditingController _search = TextEditingController();
  String _category = 'All tools';

  static const Set<String> _mathTools = <String>{
    'unitCircle', 'cubicGraph', 'exponentialGraph', 'logarithmicGraph',
    'tangentGraph', 'ellipseAxes', 'vectorField', 'polarGraph',
    'cartesianPlane', 'coordinateAxes', 'parabola', 'sineWave', 'angle',
    'vectorArrow', 'projectilePath', 'numberLine',
  };
  static const Set<String> _chartTools = <String>{
    'histogram', 'barChart', 'pieChart', 'flowchartTerminator',
    'flowchartProcess', 'flowchartDecision', 'flowchartInputOutput',
    'flowchartDocument', 'flowchartDatabase', 'flowchartConnector',
    'timeline', 'tableGrid', 'checklist',
  };
  static const Set<String> _physicsTools = <String>{
    'rayDiagram', 'convexLens', 'concaveLens', 'planeMirror',
    'forceDiagram', 'pulley', 'spring', 'lever', 'inclinedPlane',
    'gear', 'magnet', 'thermometer', 'stopwatch', 'waveform',
  };
  static const Set<String> _circuitTools = <String>{
    'circuitResistor', 'circuitBattery', 'capacitor', 'circuitSwitch', 'circuitLamp',
  };
  static const Set<String> _chemistryTools = <String>{
    'atom', 'molecule', 'benzeneRing', 'beaker', 'testTube',
    'conicalFlask', 'orbital',
  };
  static const Set<String> _biologyTools = <String>{
    'animalCell', 'plantCell', 'dnaHelix', 'neuron', 'leaf', 'microscope',
  };
  static const Set<String> _instrumentTools = <String>{
    'ruler', 'compass', 'protractor', 'divider', 'dashedLine', 'dottedLine',
  };

  String _categoryOf(CanvasTool tool) {
    if (tool.isPen) return 'Pens';
    if (const {'eraser', 'pixelEraser', 'lasso'}.contains(tool.name)) return 'Editing';
    if (_mathTools.contains(tool.name)) return 'Math & graphs';
    if (_chartTools.contains(tool.name)) return 'Charts & flowcharts';
    if (_physicsTools.contains(tool.name)) return 'Physics & mechanics';
    if (_circuitTools.contains(tool.name)) return 'Electrical circuits';
    if (_chemistryTools.contains(tool.name)) return 'Chemistry';
    if (_biologyTools.contains(tool.name)) return 'Biology';
    if (_instrumentTools.contains(tool.name)) return 'Rulers & measuring';
    return 'Shapes & diagrams';
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = <String>[
      'All tools', 'Pens', 'Editing', 'Shapes & diagrams', 'Rulers & measuring',
      'Math & graphs', 'Charts & flowcharts', 'Physics & mechanics',
      'Electrical circuits', 'Chemistry', 'Biology',
    ];
    final query = _search.text.trim().toLowerCase();
    final items = CanvasTool.values.where((tool) {
      final matchesQuery = query.isEmpty ||
          tool.label.toLowerCase().contains(query) ||
          tool.name.toLowerCase().contains(query);
      return matchesQuery &&
          (_category == 'All tools' || _categoryOf(tool) == _category);
    }).toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 4, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Search pens, shapes, graphs or science tools',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: categories.map((category) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(category, style: const TextStyle(fontSize: 11)),
                    selected: _category == category,
                    onSelected: (_) => setState(() => _category = category),
                  ),
                )).toList(),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: MediaQuery.sizeOf(context).height * .52,
              child: GridView.builder(
                itemCount: items.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 1.3,
                ),
                itemBuilder: (_, index) {
                  final tool = items[index];
                  final selected = tool == widget.selected;
                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => Navigator.pop(context, tool),
                    child: Ink(
                      decoration: BoxDecoration(
                        color: selected ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: selected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant),
                      ),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Text(tool.label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
), '') : fixed;
  }

  @override
  void dispose() {
    _expression.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final width = _width.clamp(290.0, math.max(290.0, screen.width - 24)).toDouble();
    final height = _height.clamp(380.0, math.max(380.0, screen.height - 40)).toDouble();
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      backgroundColor: scheme.surface,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: width,
        height: height,
        child: Column(
          children: [
            GestureDetector(
              onPanUpdate: (details) {
                setState(() {
                  _width = (_width + details.delta.dx).clamp(290.0, math.max(290.0, screen.width - 24)).toDouble();
                  _height = (_height + details.delta.dy).clamp(380.0, math.max(380.0, screen.height - 40)).toDouble();
                  widget.onResize(_width, _height);
                });
              },
              child: Container(
                color: scheme.primaryContainer,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.calculate_rounded, size: 19),
                    const SizedBox(width: 8),
                    const Expanded(child: Text('Scientific calculator', style: TextStyle(fontWeight: FontWeight.w800))),
                    TextButton(
                      onPressed: () => setState(() => _degrees = !_degrees),
                      child: Text(_degrees ? 'DEG' : 'RAD'),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _expression,
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w600, fontFeatures: [ui.FontFeature.tabularFigures()]),
                    decoration: const InputDecoration(
                      hintText: '0',
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    onSubmitted: (_) => _press('='),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(_error ?? _answer, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: _error == null ? scheme.primary : scheme.error, fontFeatures: const [ui.FontFeature.tabularFigures()])),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _keys.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    crossAxisSpacing: 6,
                    mainAxisSpacing: 6,
                    childAspectRatio: 1.35,
                  ),
                  itemBuilder: (_, index) {
                    final key = _keys[index];
                    final isOperator = const {'÷', '×', '−', '+', '^', '='}.contains(key);
                    final isUtility = const {'C', 'AC', '⌫'}.contains(key);
                    return FilledButton.tonal(
                      style: FilledButton.styleFrom(
                        padding: EdgeInsets.zero,
                        backgroundColor: isOperator
                            ? scheme.primaryContainer
                            : isUtility
                                ? scheme.secondaryContainer
                                : scheme.surfaceContainerHigh,
                        foregroundColor: scheme.onSurface,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () => _press(key),
                      child: Text(key, style: TextStyle(fontSize: key.length > 2 ? 14 : 19, fontWeight: FontWeight.w700)),
                    );
                  },
                ),
              ),
            ),
            GestureDetector(
              onPanUpdate: (details) {
                setState(() {
                  _width = (_width + details.delta.dx).clamp(290.0, math.max(290.0, screen.width - 24)).toDouble();
                  _height = (_height + details.delta.dy).clamp(380.0, math.max(380.0, screen.height - 40)).toDouble();
                  widget.onResize(_width, _height);
                });
              },
              child: Container(
                height: 18,
                alignment: Alignment.bottomRight,
                padding: const EdgeInsets.only(right: 4, bottom: 2),
                child: Icon(Icons.drag_handle_rounded, size: 18, color: scheme.outline),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScientificExpressionParser {
  final String source;
  final bool degrees;
  int _index = 0;

  _ScientificExpressionParser(String input, {required this.degrees})
      : source = input.replaceAll('×', '*').replaceAll('÷', '/').replaceAll('−', '-').replaceAll('π', 'pi');

  double parse() {
    final value = _expression();
    _space();
    if (_index != source.length) throw const FormatException('Unexpected token');
    return value;
  }

  void _space() {
    while (_index < source.length && source[_index].trim().isEmpty) {
      _index++;
    }
  }

  bool _eat(String token) {
    _space();
    if (source.startsWith(token, _index)) {
      _index += token.length;
      return true;
    }
    return false;
  }

  double _expression() {
    var value = _term();
    while (true) {
      if (_eat('+')) {
        value += _term();
      } else if (_eat('-')) {
        value -= _term();
      } else {
        return value;
      }
    }
  }

  double _term() {
    var value = _power();
    while (true) {
      if (_eat('*')) {
        value *= _power();
      } else if (_eat('/')) {
        final divisor = _power();
        if (divisor == 0) throw const FormatException('Division by zero');
        value /= divisor;
      } else {
        return value;
      }
    }
  }

  double _power() {
    final base = _unary();
    if (_eat('^')) return math.pow(base, _power()).toDouble();
    return base;
  }

  double _unary() {
    if (_eat('+')) return _unary();
    if (_eat('-')) return -_unary();
    return _primary();
  }

  double _primary() {
    _space();
    if (_eat('(')) {
      final value = _expression();
      if (!_eat(')')) throw const FormatException('Missing closing parenthesis');
      return value;
    }
    if (_index >= source.length) throw const FormatException('Missing value');
    final char = source[_index];
    if (RegExp(r'[a-zA-Z]').hasMatch(char)) {
      final start = _index;
      while (_index < source.length && RegExp(r'[a-zA-Z]').hasMatch(source[_index])) {
        _index++;
      }
      final name = source.substring(start, _index).toLowerCase();
      if (name == 'pi') return math.pi;
      if (name == 'e') return math.e;
      if (!_eat('(')) throw const FormatException('Function needs parentheses');
      final argument = _expression();
      if (!_eat(')')) throw const FormatException('Missing function parenthesis');
      final angle = degrees ? argument * math.pi / 180 : argument;
      return switch (name) {
        'sin' => math.sin(angle),
        'cos' => math.cos(angle),
        'tan' => math.tan(angle),
        'sqrt' => argument < 0 ? throw const FormatException('Negative square root') : math.sqrt(argument),
        'ln' => argument <= 0 ? throw const FormatException('Invalid logarithm') : math.log(argument),
        'log' => argument <= 0 ? throw const FormatException('Invalid logarithm') : math.log(argument) / math.ln10,
        'abs' => argument.abs(),
        _ => throw FormatException('Unknown function: $name'),
      };
    }
    final rest = source.substring(_index);
    final match = RegExp(r'^(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?').firstMatch(rest);
    if (match == null) throw const FormatException('Expected a number');
    _index += match.group(0)!.length;
    return double.parse(match.group(0)!);
  }
}

class _EditorV2ToolPicker extends StatefulWidget {
  final CanvasTool selected;
  const _EditorV2ToolPicker({required this.selected});

  @override
  State<_EditorV2ToolPicker> createState() => _EditorV2ToolPickerState();
}

class _EditorV2ToolPickerState extends State<_EditorV2ToolPicker> {
  final TextEditingController _search = TextEditingController();
  String _category = 'All tools';

  static const Set<String> _mathTools = <String>{
    'unitCircle', 'cubicGraph', 'exponentialGraph', 'logarithmicGraph',
    'tangentGraph', 'ellipseAxes', 'vectorField', 'polarGraph',
    'cartesianPlane', 'coordinateAxes', 'parabola', 'sineWave', 'angle',
    'vectorArrow', 'projectilePath', 'numberLine',
  };
  static const Set<String> _chartTools = <String>{
    'histogram', 'barChart', 'pieChart', 'flowchartTerminator',
    'flowchartProcess', 'flowchartDecision', 'flowchartInputOutput',
    'flowchartDocument', 'flowchartDatabase', 'flowchartConnector',
    'timeline', 'tableGrid', 'checklist',
  };
  static const Set<String> _physicsTools = <String>{
    'rayDiagram', 'convexLens', 'concaveLens', 'planeMirror',
    'forceDiagram', 'pulley', 'spring', 'lever', 'inclinedPlane',
    'gear', 'magnet', 'thermometer', 'stopwatch', 'waveform',
  };
  static const Set<String> _circuitTools = <String>{
    'circuitResistor', 'circuitBattery', 'capacitor', 'circuitSwitch', 'circuitLamp',
  };
  static const Set<String> _chemistryTools = <String>{
    'atom', 'molecule', 'benzeneRing', 'beaker', 'testTube',
    'conicalFlask', 'orbital',
  };
  static const Set<String> _biologyTools = <String>{
    'animalCell', 'plantCell', 'dnaHelix', 'neuron', 'leaf', 'microscope',
  };
  static const Set<String> _instrumentTools = <String>{
    'ruler', 'compass', 'protractor', 'divider', 'dashedLine', 'dottedLine',
  };

  String _categoryOf(CanvasTool tool) {
    if (tool.isPen) return 'Pens';
    if (const {'eraser', 'pixelEraser', 'lasso'}.contains(tool.name)) return 'Editing';
    if (_mathTools.contains(tool.name)) return 'Math & graphs';
    if (_chartTools.contains(tool.name)) return 'Charts & flowcharts';
    if (_physicsTools.contains(tool.name)) return 'Physics & mechanics';
    if (_circuitTools.contains(tool.name)) return 'Electrical circuits';
    if (_chemistryTools.contains(tool.name)) return 'Chemistry';
    if (_biologyTools.contains(tool.name)) return 'Biology';
    if (_instrumentTools.contains(tool.name)) return 'Rulers & measuring';
    return 'Shapes & diagrams';
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = <String>[
      'All tools', 'Pens', 'Editing', 'Shapes & diagrams', 'Rulers & measuring',
      'Math & graphs', 'Charts & flowcharts', 'Physics & mechanics',
      'Electrical circuits', 'Chemistry', 'Biology',
    ];
    final query = _search.text.trim().toLowerCase();
    final items = CanvasTool.values.where((tool) {
      final matchesQuery = query.isEmpty ||
          tool.label.toLowerCase().contains(query) ||
          tool.name.toLowerCase().contains(query);
      return matchesQuery &&
          (_category == 'All tools' || _categoryOf(tool) == _category);
    }).toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 4, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Search pens, shapes, graphs or science tools',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: categories.map((category) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(category, style: const TextStyle(fontSize: 11)),
                    selected: _category == category,
                    onSelected: (_) => setState(() => _category = category),
                  ),
                )).toList(),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: MediaQuery.sizeOf(context).height * .52,
              child: GridView.builder(
                itemCount: items.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 1.3,
                ),
                itemBuilder: (_, index) {
                  final tool = items[index];
                  final selected = tool == widget.selected;
                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => Navigator.pop(context, tool),
                    child: Ink(
                      decoration: BoxDecoration(
                        color: selected ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: selected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant),
                      ),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Text(tool.label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
