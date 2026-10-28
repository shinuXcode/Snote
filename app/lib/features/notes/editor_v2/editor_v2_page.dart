import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart' as zip;
import 'package:crypto/crypto.dart';
import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute, defaultTargetPlatform, kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_svg/flutter_svg.dart' as vg;
import 'package:pdf/pdf.dart' as pdfcore;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfx/pdfx.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../canvas_engine/models/pen_config.dart';
import '../../../canvas_engine/models/stroke.dart';
import '../../../canvas_engine/models/stroke_codec.dart';
import '../../../canvas_engine/widgets/page_background.dart';
import '../../../ui/snote_floating_toolbar.dart';
import '../../../core/security/note_lock_service.dart';
import '../../../core/settings/app_settings.dart';
import '../../settings/settings_page.dart';
import '../../../data/local/file_document_repository.dart';
import '../../../data/local/note_repository.dart';
import '../note_content_compatibility.dart';
import 'editor_v2_document.dart';
import 'multi_split_workspace.dart';
import 'smart_pages_catalog.dart';

import 'editor_v2_ink_painter.dart';
import 'selection_text_recognizer.dart';
import '../../tools/screen_capture.dart';
import '../../tools/floating_timer_panel.dart';
import '../../tools/web_search_panel.dart';

/// Decode large note envelopes away from the UI isolate so returning to a
/// notebook does not block the first interactive frame on JSON parsing.
Map<String, Object?> _decodeEditorDocumentPayload(String? content) {
  final root = EditorV2DocumentCodec.decodeRoot(content ?? '');
  return <String, Object?>{
    'root': root,
    'pages': EditorV2DocumentCodec.decodePages(root),
  };
}


/// Replacement note editor surface. It shares only Snote's persistence and
/// stroke-format contracts; pointer handling, selection, drawing, and painting
/// are implemented here rather than delegated to the legacy SnoteCanvas.
/// Shared regression-tested surface style for sticker/text overlays.
const BoxDecoration snoteTransparentTextBoxDecoration = BoxDecoration(
  color: Colors.transparent,
  border: Border.fromBorderSide(BorderSide(color: Colors.transparent, width: 0)),
  borderRadius: BorderRadius.all(Radius.circular(4)),
);

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
  static const double _defaultPageHeight = 1152;

  double get _pageHeight {
    final stored = (_pageData['pageHeight'] as num?)?.toDouble();
    if (stored != null && stored.isFinite && stored > 0) {
      return stored.clamp(360.0, 5000.0).toDouble();
    }
    return _defaultPageHeight;
  }

  double get _pageWidth {
    final stored = (_pageData['pageWidth'] as num?)?.toDouble();
    if (stored != null && stored.isFinite && stored > 0) {
      return stored.clamp(360.0, 5000.0).toDouble();
    }
    final ratio = ((_pageData['pageAspectRatio'] as num?)?.toDouble() ?? (816 / 1152))
        .clamp(.2, 1.0).toDouble();
    final landscape = _pageData['orientation']?.toString() == 'horizontal';
    return (landscape ? _pageHeight / ratio : _pageHeight * ratio)
        .clamp(360.0, 5000.0).toDouble();
  }

  double _pageAspectRatioFor(Map<String, Object?> page) {
    final width = (page['pageWidth'] as num?)?.toDouble();
    final height = (page['pageHeight'] as num?)?.toDouble();
    if (width != null && height != null && width > 0 && height > 0) {
      return (width / height).clamp(.2, 5.0).toDouble();
    }
    final shortToLong = ((page['pageAspectRatio'] as num?)?.toDouble() ?? (816 / 1152))
        .clamp(.2, 1.0).toDouble();
    return page['orientation']?.toString() == 'horizontal'
        ? 1 / shortToLong
        : shortToLong;
  }
  static const int _maxPdfPagesPerImport = 40;
  static const int _maxPdfRasterCacheBytes = 48 * 1024 * 1024;
  static const List<Color> _palette = <Color>[
    Color(0xff111827), Color(0xff263238), Color(0xff546e7a), Color(0xff90a4ae),
    Color(0xff000000), Color(0xffffffff), Color(0xff37474f), Color(0xff78909c),
    Color(0xff0d47a1), Color(0xff1565c0), Color(0xff42a5f5), Color(0xff80d8ff),
    Color(0xff004d40), Color(0xff00897b), Color(0xff4db6ac), Color(0xffa7ffeb),
    Color(0xff1b5e20), Color(0xff2e7d32), Color(0xff81c784), Color(0xffc5e1a5),
    Color(0xff4a148c), Color(0xff7b1fa2), Color(0xffba68c8), Color(0xffe1bee7),
    Color(0xff880e4f), Color(0xffec407a), Color(0xfff48fb1), Color(0xffffcdd2),
    Color(0xffb71c1c), Color(0xffc62828), Color(0xffef5350), Color(0xffff8a80),
    Color(0xffe65100), Color(0xffef6c00), Color(0xffffb74d), Color(0xffffe0b2),
    Color(0xfff57f17), Color(0xffd4a900), Color(0xffffff00), Color(0xfffff59d),
    Color(0xff3e2723), Color(0xff795548), Color(0xffbcaaa4), Color(0xffd7ccc8),
    Color(0xff283593), Color(0xff3949ab), Color(0xff7986cb), Color(0xffc5cae9),
  ];
  static const List<CanvasTool> _quickTools = <CanvasTool>[
    CanvasTool.ballpoint,
    CanvasTool.fountain,
    CanvasTool.pencil,
    CanvasTool.highlighter,
    CanvasTool.marker,
    CanvasTool.brush,
    CanvasTool.eraser,
    CanvasTool.lasso,
    CanvasTool.fill,
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
  final Map<String, DocumentAsset> _pdfSourceAssets = <String, DocumentAsset>{};
  final Map<String, Uint8List> _pdfSourceBytesCache = <String, Uint8List>{};
  final Map<String, Future<Uint8List>> _pdfSourceBytesFutures = <String, Future<Uint8List>>{};
  final Map<String, Future<PdfDocument>> _pdfDocumentFutures = <String, Future<PdfDocument>>{};
  final Map<String, Future<Uint8List?>> _pdfRasterPending = <String, Future<Uint8List?>>{};
  final LinkedHashMap<String, Uint8List> _pdfRasterCache = LinkedHashMap<String, Uint8List>();
  final LinkedHashMap<String, Future<Uint8List?>> _pdfRasterFutureCache =
      LinkedHashMap<String, Future<Uint8List?>>();
  final Set<int> _activePointers = <int>{};
  final Set<int> _ignoredPointers = <int>{};
  final Set<int> _stylusPointers = <int>{};
  final Set<int> _navigationOnlyPointers = <int>{};
  Duration? _lastEraseTimestamp;
  Offset? _lastErasePosition;
  bool _eraseUndoCaptured = false;
  List<Stroke>? _eraseWorkingStrokes;
  Timer? _holdTimer;
  Offset? _holdStartPosition;
  Offset? _pageSwipeStart;
  bool _pageSwipeTriggered = false;
  bool _longPressTriggered = false;
  final List<List<Map<String, Object?>>> _undoStack =
      <List<Map<String, Object?>>>[];
  final List<List<Map<String, Object?>>> _redoStack =
      <List<Map<String, Object?>>>[];

  Map<String, Object?> _rootContent = <String, Object?>{};
  List<Map<String, Object?>> _pages = <Map<String, Object?>>[];
  List<Map<String, Object?>> _favoritePens = <Map<String, Object?>>[];
  List<String> _favoriteStickers = <String>[];
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
  bool _compactFloatingToolbar = false;
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
  double _eraserCursorRadius = 18;
  Offset _floatingOffset = const Offset(12, 12);
  List<StrokePoint> _livePoints = <StrokePoint>[];
  Stroke? _liveStroke;
  Rect? _lassoRect;
  final Set<String> _selectedStrokeIds = <String>{};
  final Set<String> _selectedImageIds = <String>{};
  final Set<String> _selectedTextBoxIds = <String>{};
  final Map<String, Map<String, Object?>> _toolProfiles = <String, Map<String, Object?>>{};
  Map<String, Object?>? _pageClipboard;
  Map<String, Object?>? _selectionClipboard;
  final List<Map<String, Object?>> _selectionClipboardHistory = <Map<String, Object?>>[];
  final Map<String, Set<String>> _toolPlacements = <String, Set<String>>{};
  List<String> _toolbarOrder = <String>[];
  bool _showNoteSwitcherInTitleBar = true;
  bool _showTabsBar = false;
  Future<List<LocalNote>>? _noteTabsFuture;
  List<Map<String, Object?>>? _selectionTransformImageSnapshot;
  List<Map<String, Object?>>? _selectionTransformTextSnapshot;
  bool _showFavoritesShowcase = true;
  bool _showPageNavigation = true;
  bool _showPagePreview = true;
  bool _floatingPageNavigation = false;
  bool _fullScreenMode = false;
  bool _readingMode = false;
  CanvasTool? _toolBeforeReading;
  bool _showFloatingTimer = false;
  bool _toolbarCollapsedToEdge = false;
  bool _calculatorCollapsed = false;
  bool _showViewportHud = false;
  bool _viewportLocked = false;
  bool _watermarkCoverMode = false;
  CanvasTool? _toolBeforeWatermarkCover;
  Color? _colorBeforeWatermarkCover;
  double? _sizeBeforeWatermarkCover;
  double? _opacityBeforeWatermarkCover;
  Timer? _viewportHudTimer;
  bool _pdfBackgroundVisible = true;
  bool _pressureEraseActive = false;
  CanvasTool? _toolBeforePressureErase;
  Offset _favoriteOffset = const Offset(16, 220);
  bool _favoriteCollapsed = false;
  Offset _toolSettingsAnchor = const Offset(20, 120);
  Offset _pageNavOffset = const Offset(8, 280);
  double _calculatorWidth = 330;
  double _calculatorHeight = 465;
  bool _calculatorVisible = false;
  Offset _calculatorOffset = const Offset(24, 125);
  List<Stroke>? _selectionTransformSnapshot;
  Rect? _selectionTransformBounds;
  Offset _selectionTransformDelta = Offset.zero;
  bool _selectionTransformIsResize = false;
  Offset _selectionResizeDirection = const Offset(1, 1);
  double _toolbarLength = 360;
  double _toolbarThickness = 34;
  double _toolbarMarginLeft = 0, _toolbarMarginTop = 0;
  double _toolbarMarginRight = 0, _toolbarMarginBottom = 0;
  double _toolbarPaddingLeft = 2, _toolbarPaddingTop = 1;
  double _toolbarPaddingRight = 2, _toolbarPaddingBottom = 1;
  bool _toolbarDimensionsLocked = false;

  bool get _hasPdfBackgroundPages => _pages.any((page) {
        if (page['pdfLazyRender'] == true) return true;
        final source = page['backgroundImage'];
        return source is String && source.isNotEmpty;
      });

  void _setPdfBackgroundVisible(bool visible) {
    if (visible && !_hasPdfBackgroundPages) return;
    setState(() => _pdfBackgroundVisible = visible);
  }

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
    _toolbarDock = const <String>{'top', 'left', 'right'}
            .contains(_settings.getString('editorV2ToolbarDock'))
        ? _settings.getString('editorV2ToolbarDock')
        : 'top';
    _floatingToolbar = _settings.getBool('editorV2FloatingToolbar');
    _compactFloatingToolbar = _settings.getBool('editorV2CompactFloatingToolbar');
    _showTabsBar = _settings.getBool('editorV2ShowTabs');
    _noteTabsFuture = _repo.listAllVisible(limit: 12);
    _toolbarCollapsedToEdge = _settings.getBool('editorV2ToolbarCollapsed');
    _toolbarLength = _settings.getDouble('editorV2ToolbarLength').clamp(180.0, 900.0).toDouble();
    _toolbarThickness = _settings.getDouble('editorV2ToolbarThickness').clamp(28.0, 96.0).toDouble();
    _toolbarMarginLeft = _settings.getDouble('editorV2ToolbarMarginLeft').clamp(0.0, 24.0).toDouble();
    _toolbarMarginTop = _settings.getDouble('editorV2ToolbarMarginTop').clamp(0.0, 24.0).toDouble();
    _toolbarMarginRight = _settings.getDouble('editorV2ToolbarMarginRight').clamp(0.0, 24.0).toDouble();
    _toolbarMarginBottom = _settings.getDouble('editorV2ToolbarMarginBottom').clamp(0.0, 24.0).toDouble();
    _toolbarPaddingLeft = _settings.getDouble('editorV2ToolbarPaddingLeft').clamp(0.0, 20.0).toDouble();
    _toolbarPaddingTop = _settings.getDouble('editorV2ToolbarPaddingTop').clamp(0.0, 20.0).toDouble();
    _toolbarPaddingRight = _settings.getDouble('editorV2ToolbarPaddingRight').clamp(0.0, 20.0).toDouble();
    _toolbarPaddingBottom = _settings.getDouble('editorV2ToolbarPaddingBottom').clamp(0.0, 20.0).toDouble();
    _toolbarDimensionsLocked = _settings.getBool('editorV2ToolbarDimensionsLocked');
    _favoriteCollapsed = _settings.getBool('editorV2FavoriteCollapsed');
    _calculatorCollapsed = _settings.getBool('editorV2CalculatorCollapsed');
    _favoritesVertical = _settings.getBool('editorV2FavoritesVertical');
    _showPageNavigation = _settings.getBool('showPageNavigation');
    _showPagePreview = _settings.getBool('showPagePreview');
    _floatingPageNavigation = _settings.getBool('editorV2FloatingPageNavigation');
    _showFavoritesShowcase = _settings.getBool('editorV2ShowFavoritesShowcase');
    try {
      final favoriteOffset = jsonDecode(_settings.getString('editorV2FavoriteOffset'));
      if (favoriteOffset is Map) {
        _favoriteOffset = Offset(
          (favoriteOffset['dx'] as num?)?.toDouble() ?? _favoriteOffset.dx,
          (favoriteOffset['dy'] as num?)?.toDouble() ?? _favoriteOffset.dy,
        );
      }
    } catch (_) {
      // Invalid or absent position preferences simply use the safe default.
    }
    _restoreToolProfiles();
    _restoreToolPlacements();
    _showNoteSwitcherInTitleBar = _settings.getBool('editorV2ShowNoteSwitcher');
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
    final decoded = await compute(_decodeEditorDocumentPayload, saved.contentJson);
    final root = Map<String, Object?>.from(decoded['root'] as Map);
    final pages = (decoded['pages'] as List)
        .map((page) => Map<String, Object?>.from(page as Map))
        .toList();
    final delta = root['text_delta'];
    if (delta is List) {
      try {
        _quill.document = Document.fromJson(delta);
      } catch (error, stackTrace) {
        debugPrint('[Snote][EditorV2] rich-text delta restore failed: $error\n$stackTrace');
      }
    }
    Uint8List? pdfBytes = widget.initialPdfBytes;
    String? pdfName = widget.initialPdfName;
    DocumentAsset? sourcePdf;
    final assets = await _documents.listForNote(widget.note.id);
    for (final asset in assets) {
      final type = asset.type.toLowerCase();
      final name = asset.name.toLowerCase();
      if (type == 'pdf' || type == 'application/pdf' || name.endsWith('.pdf')) {
        _pdfSourceAssets[asset.id] = asset;
      }
    }
    for (final asset in assets.reversed) {
      final type = asset.type.toLowerCase();
      final name = asset.name.toLowerCase();
      if (type == 'pdf' || type == 'application/pdf' || name.endsWith('.pdf')) {
        sourcePdf = asset;
        break;
      }
    }
    if (pdfBytes != null && pdfBytes.isNotEmpty && sourcePdf == null) {
      sourcePdf = await _documents.saveBytes(
        noteId: widget.note.id,
        name: pdfName ?? '${saved.title}.pdf',
        type: 'pdf',
        bytes: pdfBytes,
        metadata: const <String, dynamic>{'source': 'editor-v2-pdf-background'},
      );
      _pdfSourceAssets[sourcePdf.id] = sourcePdf;
    }
    if (sourcePdf != null) {
      _pdfSourceAssets[sourcePdf.id] = sourcePdf;
      if (pdfBytes != null && pdfBytes.isNotEmpty) {
        _pdfSourceBytesCache[sourcePdf.id] = pdfBytes;
      }
    }
    final hasPdfAttachment = sourcePdf != null;
    if ((pdfBytes == null || pdfBytes.isEmpty) && sourcePdf != null) {
      pdfBytes = await _pdfBytesForSource(sourcePdf.id);
      pdfName = sourcePdf.name;
      if (pdfBytes.isEmpty) {
        throw StateError('The original PDF attachment is empty. It has been preserved.');
      }
    }

    var renderedPdf = false;
    var totalPdfPages = 0;
    if (pdfBytes != null && pdfBytes.isNotEmpty) {
      final sourceHash = sha256.convert(pdfBytes).toString();
      var restorePdfPages = shouldRestorePdfPageBackgrounds(pages, sourceHash: sourceHash);
      if (!restorePdfPages && sourcePdf != null) {
        final recordedPdfPages = pages
            .where((page) =>
                page['pdfSourceHash'] == sourceHash &&
                page['pdfSourcePage'] is num)
            .map((page) => (page['pdfSourcePage'] as num).toInt())
            .toList();
        if (recordedPdfPages.isNotEmpty) {
          final sourceDocument = await _pdfDocumentForSource(sourcePdf.id);
          final highestRecordedPage = recordedPdfPages.reduce(
            (left, right) => left > right ? left : right,
          );
          // Older beta builds persisted only the first 40 rendered pages. On
          // restore, migrate those notes to lazy page records for the full PDF.
          if (highestRecordedPage < sourceDocument.pagesCount) {
            restorePdfPages = true;
          }
        }
      }
      if (restorePdfPages) {
        final result = await _renderPdfPages(
          pdfBytes,
          pdfName ?? '${saved.title}.pdf',
          sourceAssetId: sourcePdf?.id,
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
    final rawFavoriteStickers = root['favoriteStickers'];
    final favoriteStickers = rawFavoriteStickers is List
        ? rawFavoriteStickers.whereType<String>().where((value) => value.isNotEmpty).toSet().toList()
        : <String>[];
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
      _favoriteStickers = favoriteStickers;
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

  Future<Uint8List> _pdfBytesForSource(String assetId) {
    final cached = _pdfSourceBytesCache[assetId];
    if (cached != null) return Future<Uint8List>.value(cached);
    return _pdfSourceBytesFutures.putIfAbsent(assetId, () async {
      final asset = _pdfSourceAssets[assetId];
      if (asset == null) throw StateError('The original PDF attachment for this page is missing.');
      final bytes = await _documents.readBytes(asset);
      if (bytes.isEmpty) throw StateError('The original PDF attachment is empty.');
      _pdfSourceBytesCache[assetId] = bytes;
      return bytes;
    });
  }

  Future<PdfDocument> _pdfDocumentForSource(String assetId) =>
      _pdfDocumentFutures.putIfAbsent(assetId, () async {
        final bytes = await _pdfBytesForSource(assetId);
        return PdfDocument.openData(bytes);
      });

  Future<Uint8List?> _renderPdfPageRaster(String assetId, int pageNumber, {required bool thumbnail}) async {
    final document = await _pdfDocumentForSource(assetId);
    if (pageNumber < 1 || pageNumber > document.pagesCount) {
      throw RangeError('PDF page $pageNumber is outside 1..${document.pagesCount}.');
    }
    final page = await document.getPage(pageNumber);
    try {
      final lazyIndex = _pages.indexWhere((record) =>
          record['pdfLazyRender'] == true &&
          record['pdfSourceAssetId']?.toString() == assetId &&
          (record['pdfSourcePage'] as num?)?.toInt() == pageNumber &&
          record['pageWidth'] == null &&
          record['pageHeight'] == null);
      if (lazyIndex >= 0) {
        final record = _pages[lazyIndex];
        final shortSide = math.min(page.width, page.height);
        final longSide = math.max(page.width, page.height);
        final ratio = shortSide / longSide;
        final orientation = page.width > page.height ? 'horizontal' : 'vertical';
        if (((record['pageAspectRatio'] as num?)?.toDouble() ?? 0) != ratio ||
            record['orientation']?.toString() != orientation) {
          record['pageAspectRatio'] = ratio;
          record['orientation'] = orientation;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && lazyIndex < _pages.length && identical(_pages[lazyIndex], record)) {
              setState(() {});
              _scheduleSave();
            }
          });
        }
      }
      final maxDimension = thumbnail ? 320.0 : 2800.0;
      final scale = math.min(maxDimension / page.width, maxDimension / page.height);
      final rendered = await page.render(
        width: (page.width * scale).clamp(1.0, maxDimension).toDouble(),
        height: (page.height * scale).clamp(1.0, maxDimension).toDouble(),
        format: PdfPageImageFormat.png,
        backgroundColor: '#ffffff',
      );
      if (rendered == null || rendered.bytes.isEmpty) return null;
      return rendered.bytes;
    } finally {
      await page.close();
    }
  }

  void _rememberPdfRasterFuture(String key, Future<Uint8List?> future) {
    _pdfRasterFutureCache.remove(key);
    _pdfRasterFutureCache[key] = future;
    while (_pdfRasterFutureCache.length > 12) {
      _pdfRasterFutureCache.remove(_pdfRasterFutureCache.keys.first);
    }
  }

  Future<Uint8List?> _lazyPdfPageRaster(
    String assetId,
    int pageNumber, {
    bool thumbnail = false,
  }) {
    final key = '$assetId:$pageNumber:${thumbnail ? 'thumb' : 'full'}';

    final cachedFuture = _pdfRasterFutureCache.remove(key);
    if (cachedFuture != null) {
      _pdfRasterFutureCache[key] = cachedFuture;
      return cachedFuture;
    }

    final cachedBytes = _pdfRasterCache.remove(key);
    if (cachedBytes != null) {
      _pdfRasterCache[key] = cachedBytes;
      final ready = Future<Uint8List?>.value(cachedBytes);
      _rememberPdfRasterFuture(key, ready);
      return ready;
    }

    final pending = _pdfRasterPending[key];
    if (pending != null) {
      _rememberPdfRasterFuture(key, pending);
      return pending;
    }

    final future = _renderPdfPageRaster(
      assetId,
      pageNumber,
      thumbnail: thumbnail,
    );
    _pdfRasterPending[key] = future;
    _rememberPdfRasterFuture(key, future);
    unawaited(future.then<void>((bytes) {
      if (bytes == null || bytes.isEmpty) return;
      _pdfRasterCache.remove(key);
      _pdfRasterCache[key] = bytes;
      while (_pdfRasterCache.length > 12 ||
          _pdfRasterCache.values.fold<int>(0, (total, bytes) => total + bytes.length) >
              _maxPdfRasterCacheBytes) {
        if (_pdfRasterCache.isEmpty) break;
        _pdfRasterCache.remove(_pdfRasterCache.keys.first);
      }
    }).catchError((Object error) {
      debugPrint('[Snote][EditorV2] lazy PDF page render failed ($pageNumber): $error');
    }).whenComplete(() {
      _pdfRasterPending.remove(key);
    }));
    return future;
  }

  Future<({List<Map<String, Object?>> pages, int totalPages})> _renderPdfPages(
    Uint8List sourceBytes,
    String sourceName, {
    String? sourceAssetId,
  }) async {
    if (sourceBytes.isEmpty) throw StateError('The selected PDF is empty.');
    final sourceHash = sha256.convert(sourceBytes).toString();
    final document = await PdfDocument.openData(sourceBytes);
    final totalPages = document.pagesCount;
    final imported = <Map<String, Object?>>[];
    final pageIdPrefix = 'pdf-${DateTime.now().microsecondsSinceEpoch}';
    try {
      // Every imported PDF with a saved source attachment becomes lightweight
      // page records. Only requested thumbnails and visible pages are rasterized,
      // avoiding an upfront render pass for large textbooks.
      if (sourceAssetId != null && sourceAssetId.isNotEmpty) {
        for (var index = 1; index <= totalPages; index++) {
          imported.add(<String, Object?>{
            'id': '$pageIdPrefix-$index',
            'template': PageTemplate.blank.name,
            'paperColor': 0xffffffff,
            'lineColor': 0xffd8dee8,
            'lineOpacity': .85,
            'spacing': 28.0,
            'lineWidth': .7,
            'pageSize': 'A4',
            'pageAspectRatio': .707,
            'cornellAssist': false,
            'orientation': 'vertical',
            'pdfLazyRender': true,
            'pdfSourceAssetId': sourceAssetId,
            'pdfSourceName': sourceName,
            'pdfSourceHash': sourceHash,
            'pdfSourcePage': index,
            'strokes': <Object?>[],
            'images': <Object?>[],
            'textBoxes': <Object?>[],
          });
        }
        return (pages: imported, totalPages: totalPages);
      }
      if (totalPages > _maxPdfPagesPerImport) {
        throw StateError('Large PDF imports require a saved source attachment.');
      }
      for (var index = 1; index <= totalPages; index++) {
        final pdfPage = await document.getPage(index);
        try {
          const maxDimension = 2800.0;
          final scale = math.min(maxDimension / pdfPage.width, maxDimension / pdfPage.height);
          final rendered = await pdfPage.render(
            width: (pdfPage.width * scale).roundToDouble(),
            height: (pdfPage.height * scale).roundToDouble(),
            format: PdfPageImageFormat.png,
            backgroundColor: '#ffffff',
          );
          if (rendered == null || rendered.bytes.isEmpty) {
            throw StateError('Could not render PDF page $index.');
          }
          imported.add(<String, Object?>{
            'id': '$pageIdPrefix-$index',
            'template': PageTemplate.blank.name,
            'paperColor': 0xffffffff,
            'lineColor': 0xffd8dee8,
            'lineOpacity': .85,
            'spacing': 28.0,
            'lineWidth': .7,
            'pageSize': 'A4',
            'pageAspectRatio': math.min(pdfPage.width, pdfPage.height) / math.max(pdfPage.width, pdfPage.height),
            'cornellAssist': false,
            'orientation': pdfPage.width > pdfPage.height ? 'horizontal' : 'vertical',
            'backgroundImage': base64Encode(rendered.bytes),
            'pdfSourceAssetId': sourceAssetId,
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

  void _restoreToolPlacements() {
    try {
      final decoded = jsonDecode(_settings.getString('editorV2ToolPlacements'));
      if (decoded is Map) {
        _toolPlacements
          ..clear()
          ..addEntries(decoded.entries.where((entry) => entry.value is List).map((entry) {
            final locations = (entry.value as List)
                .whereType<String>()
                .where((value) => const {'titleBar', 'toolbar', 'pencase'}.contains(value))
                .toSet();
            return MapEntry(entry.key.toString(), locations);
          }));
      }
    } catch (error) {
      debugPrint('[Snote][EditorV2] ignoring invalid tool layout settings: $error');
    }
    try {
      final decoded = jsonDecode(_settings.getString('editorV2ToolbarOrder'));
      if (decoded is List) {
        _toolbarOrder = decoded.whereType<String>().where((name) {
          return CanvasTool.values.any((tool) => tool.name == name) ||
              _isSpecialToolKey(name);
        }).toList();
      }
    } catch (error) {
      debugPrint('[Snote][EditorV2] ignoring invalid toolbar order: $error');
    }
    // Persist a stable order for every tool, not only the small quick-tools
    // subset; otherwise drop targets for custom science tools cannot reorder.
    for (final tool in CanvasTool.values) {
      if (!_toolbarOrder.contains(tool.name)) _toolbarOrder.add(tool.name);
    }
    for (final key in const <String>['calculator', 'screenshot', 'timer', 'webSearch']) {
      if (!_toolbarOrder.contains(key)) _toolbarOrder.add(key);
    }
  }

  Future<void> _saveToolPlacements() => _settings.setString(
        'editorV2ToolPlacements',
        jsonEncode(_toolPlacements.map((key, value) => MapEntry(key, value.toList()))),
      );

  Set<String> _placementsFor(CanvasTool tool) {
    final saved = _toolPlacements[tool.name];
    if (saved != null) return saved;
    return _quickTools.contains(tool) ? <String>{'toolbar'} : <String>{};
  }

  bool _toolInLocation(CanvasTool tool, String location) =>
      _placementsFor(tool).contains(location);

  bool _isSpecialToolKey(String key) =>
      const <String>{'calculator', 'screenshot', 'timer', 'webSearch'}.contains(key);

  Set<String> _locationsForToolKey(String key) {
    final tool = CanvasTool.values.where((candidate) => candidate.name == key).firstOrNull;
    if (tool != null) return Set<String>.from(_placementsFor(tool));
    if (_isSpecialToolKey(key)) return _specialToolLocations(key);
    return <String>{};
  }

  List<String> _toolKeysForLocation(String location) {
    final ordered = <String>[];
    final seen = <String>{};
    for (final key in _toolbarOrder) {
      if (seen.add(key) && _locationsForToolKey(key).contains(location)) {
        ordered.add(key);
      }
    }
    for (final tool in CanvasTool.values) {
      if (seen.add(tool.name) && _toolInLocation(tool, location)) {
        ordered.add(tool.name);
      }
    }
    for (final key in const <String>['calculator', 'screenshot']) {
      if (seen.add(key) && _specialToolLocations(key).contains(location)) {
        ordered.add(key);
      }
    }
    return ordered;
  }

  Widget _buildPlacedToolButton(String key, String location) {
    if (_isSpecialToolKey(key)) return _specialToolButton(key, location);
    final tool = CanvasTool.values.where((candidate) => candidate.name == key).firstOrNull;
    if (tool == null) return const SizedBox.shrink();
    switch (location) {
      case 'titleBar':
        return _buildTitleBarToolButton(tool);
      case 'pencase':
        return _buildPencaseToolButton(tool);
      default:
        return _buildToolbarToolButton(tool);
    }
  }

  List<CanvasTool> get _toolbarTools => _toolKeysForLocation('toolbar')
      .map((key) => CanvasTool.values.where((tool) => tool.name == key).firstOrNull)
      .whereType<CanvasTool>()
      .where((tool) => tool != CanvasTool.pixelEraser)
      .toList();

  List<CanvasTool> get _titleBarTools => _toolKeysForLocation('titleBar')
      .map((key) => CanvasTool.values.where((tool) => tool.name == key).firstOrNull)
      .whereType<CanvasTool>()
      .toList();

  List<CanvasTool> get _pencaseTools => _toolKeysForLocation('pencase')
      .map((key) => CanvasTool.values.where((tool) => tool.name == key).firstOrNull)
      .whereType<CanvasTool>()
      .toList();

  void _reorderToolbarTool(CanvasTool source, CanvasTool target) {
    unawaited(_moveDroppedTool(source, 'toolbar', target: target));
  }

  Future<void> _moveDroppedTool(
    Object dragged,
    String targetLocation, {
    Object? target,
  }) async {
    final sourceKey = dragged is CanvasTool
        ? dragged.name
        : dragged is String && _isSpecialToolKey(dragged)
            ? dragged
            : null;
    if (sourceKey == null) return;

    final targetKey = target is CanvasTool
        ? target.name
        : target is String && _isSpecialToolKey(target)
            ? target
            : null;
    if (sourceKey == targetKey) return;

    final sourceLocations = _locationsForToolKey(sourceKey);
    final targetLocations =
        targetKey == null ? <String>{} : _locationsForToolKey(targetKey);
    final sourceAlreadyThere = sourceLocations.contains(targetLocation);
    final targetAlreadyThere = targetLocations.contains(targetLocation);

    // One stable order is used by toolbar, title bar and dock. Moving onto a
    // tool inserts before that tool; dropping on empty space appends.
    final order = List<String>.from(_toolbarOrder)..remove(sourceKey);
    final targetIndex = targetKey == null ? -1 : order.indexOf(targetKey);
    order.insert(targetIndex < 0 ? order.length : targetIndex, sourceKey);

    setState(() {
      // Dropping among tools already sharing the same location only reorders.
      // Dropping into a different location moves the tool there.
      if (!(sourceAlreadyThere &&
          (targetKey == null || targetAlreadyThere))) {
        _toolPlacements[sourceKey] = <String>{targetLocation};
      }
      _toolbarOrder = order;
    });
    await _saveToolPlacements();
    await _settings.setString('editorV2ToolbarOrder', jsonEncode(order));
  }

  Set<String> _specialToolLocations(String key) =>
      Set<String>.from(_toolPlacements[key] ?? <String>{'toolbar'});

  Future<void> _specialToolSettingsSheet(String key) async {
    final selected = _specialToolLocations(key);
    const locations = <({String key, String label, IconData icon})>[
      (key: 'titleBar', label: 'Title Bar', icon: Icons.title_rounded),
      (key: 'toolbar', label: 'Toolbar', icon: Icons.widgets_outlined),
      (key: 'pencase', label: 'Pencase', icon: Icons.inventory_2_outlined),
    ];
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(key == 'calculator'
                        ? Icons.calculate_outlined
                        : Icons.screenshot_monitor_rounded),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        key == 'calculator'
                            ? 'Calculator settings'
                            : 'Screenshot tool settings',
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  const Text(
                    'Choose where this tool appears. Long-press its icon to move it.',
                  ),
                  ...locations.map((location) => CheckboxListTile(
                    secondary: Icon(location.icon),
                    title: Text(location.label),
                    value: selected.contains(location.key),
                    onChanged: (value) => setSheetState(() {
                      if (value == true) {
                        selected.add(location.key);
                      } else {
                        selected.remove(location.key);
                      }
                    }),
                  )),
                  CheckboxListTile(
                    secondary: const Icon(Icons.visibility_off_outlined),
                    title: const Text('Hidden'),
                    value: selected.isEmpty,
                    onChanged: (value) => setSheetState(() {
                      if (value == true) {
                        selected.clear();
                      } else {
                        selected.add('toolbar');
                      }
                    }),
                  ),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        setState(() {
                          _toolPlacements[key] = <String>{'pencase'};
                        });
                        await _saveToolPlacements();
                        if (sheetContext.mounted) Navigator.pop(sheetContext);
                      },
                      icon: const Icon(Icons.inventory_2_outlined),
                      label: const Text('Collect to Pencase'),
                    ),
                    FilledButton.icon(
                      onPressed: () async {
                        setState(() {
                          _toolPlacements[key] = Set<String>.from(selected);
                        });
                        await _saveToolPlacements();
                        if (sheetContext.mounted) Navigator.pop(sheetContext);
                      },
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Save locations'),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _activateSpecialTool(String key) {
    if (key == 'calculator') {
      _openCalculator();
    } else if (key == 'screenshot') {
      unawaited(_captureScreenToCanvas());
    } else if (key == 'timer') {
      setState(() => _showFloatingTimer = true);
    } else if (key == 'webSearch') {
      unawaited(SnoteWebSearchPanel.show(context));
    }
  }

  Widget _specialToolButton(String key, String location) {
    final calculator = key == 'calculator';
    final timer = key == 'timer';
    final webSearch = key == 'webSearch';
    final icon = calculator
        ? Icons.calculate_outlined
        : timer
            ? Icons.timer_outlined
            : webSearch
                ? Icons.travel_explore_rounded
                : Icons.screenshot_monitor_rounded;
    final title = calculator
        ? 'Calculator'
        : timer
            ? 'Timer, alarm and stopwatch'
            : webSearch
                ? 'Google/web search'
                : 'Capture screen to canvas';
    return DragTarget<Object>(
      onAcceptWithDetails: (details) => unawaited(
        _moveDroppedTool(details.data, location, target: key),
      ),
      builder: (context, candidates, rejected) => LongPressDraggable<Object>(
        data: key,
        maxSimultaneousDrags: 1,
        feedback: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(icon, color: Theme.of(context).colorScheme.primary),
          ),
        ),
        child: GestureDetector(
          onDoubleTap: () => unawaited(_specialToolSettingsSheet(key)),
          child: Tooltip(
            message: '${title} • double-tap for settings',
            child: IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
              onPressed: () => _activateSpecialTool(key),
              icon: Icon(icon, size: 17),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTitleBarToolButton(CanvasTool tool) => DragTarget<Object>(
        onAcceptWithDetails: (details) => unawaited(
          _moveDroppedTool(details.data, 'titleBar', target: tool),
        ),
        builder: (context, candidates, rejected) => LongPressDraggable<Object>(
          data: tool,
          maxSimultaneousDrags: 1,
          feedback: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 34,
              height: 34,
              child: Icon(_toolIcon(tool), color: Theme.of(context).colorScheme.primary),
            ),
          ),
          child: GestureDetector(
            onDoubleTap: () => _strokeSettings(tool),
            child: IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: '${tool.label} • double-tap for settings',
              onPressed: () => _selectTool(tool),
              icon: Icon(_toolIcon(tool), size: 19),
            ),
          ),
        ),
      );

  Widget _buildPencaseToolButton(CanvasTool tool) {
    final active = _tool == tool;
    return DragTarget<Object>(
      onAcceptWithDetails: (details) => unawaited(
        _moveDroppedTool(details.data, 'pencase', target: tool),
      ),
      builder: (context, candidates, rejected) => LongPressDraggable<Object>(
        data: tool,
        maxSimultaneousDrags: 1,
        feedback: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(_toolIcon(tool), color: Theme.of(context).colorScheme.primary),
          ),
        ),
        child: Tooltip(
          message: '${tool.label} • tap to choose, double-tap for settings',
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _selectTool(tool),
            onDoubleTap: () => _strokeSettings(tool),
            child: Container(
              width: _favoritesVertical ? 34 : 38,
              height: _favoritesVertical ? 38 : 34,
              margin: const EdgeInsets.all(2),
              decoration: const BoxDecoration(shape: BoxShape.circle),
              child: _settings.getBool('showPenCaseStrokeSize') && active
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(_toolIcon(tool), size: 14),
                        Text(_size.toStringAsFixed(1), style: const TextStyle(fontSize: 7, height: 1)),
                      ],
                    )
                  : Icon(_toolIcon(tool), size: 16),
            ),
          ),
        ),
      ),
    );
  }

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
      payload['favoriteStickers'] = List<String>.from(_favoriteStickers);
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
      _clearSelectionIds();
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
      _clearSelectionIds();
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
    if (_tool == CanvasTool.fill) {
      return Stroke(id: 'live-${_activePointer ?? 0}', points: const <StrokePoint>[], pen: _penConfig());
    }
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

  List<Offset> _simplifyLassoOutline(List<Offset> points) {
    if (points.length <= 3) return points;
    final simplified = <Offset>[points.first];
    for (var i = 1; i < points.length - 1; i++) {
      if ((points[i] - simplified.last).distance >= 2.5 &&
          simplified.length < 255) {
        simplified.add(points[i]);
      }
    }
    if (simplified.last != points.last) simplified.add(points.last);
    return simplified;
  }

  bool _strokeMostlyInsidePolygon(
    List<Offset> points,
    List<Offset> polygon, {
    double minimumInsideFraction = .5,
  }) {
    if (points.isEmpty || polygon.length < 3) return false;
    if (points.length == 1) return _pointInPolygon(points.first, polygon);

    var totalLength = 0.0;
    for (var i = 1; i < points.length; i++) {
      totalLength += (points[i] - points[i - 1]).distance;
    }
    if (totalLength <= 1e-6) return _pointInPolygon(points.first, polygon);

    var insideLength = 0.0;
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1];
      final b = points[i];
      final length = (b - a).distance;
      if (length <= 1e-8) continue;
      final samples = math.max(1, math.min(1024, (length / 1.5).ceil()));
      final sampleLength = length / samples;
      for (var sample = 0; sample < samples; sample++) {
        final point = Offset.lerp(a, b, (sample + .5) / samples)!;
        if (_pointInPolygon(point, polygon)) insideLength += sampleLength;
      }
    }
    return insideLength / totalLength >=
        minimumInsideFraction.clamp(0.0, 1.0).toDouble();
  }

  bool _pointInPolygon(Offset point, List<Offset> polygon) {
    if (polygon.length < 3) return false;
    var inside = false;
    var previous = polygon.length - 1;
    for (var current = 0; current < polygon.length; current++) {
      final a = polygon[current];
      final b = polygon[previous];
      if ((a.dy > point.dy) != (b.dy > point.dy)) {
        final denominator = b.dy - a.dy;
        final intersectionX = denominator.abs() < 1e-9
            ? a.dx
            : (b.dx - a.dx) * (point.dy - a.dy) / denominator + a.dx;
        if (point.dx < intersectionX) inside = !inside;
      }
      previous = current;
    }
    return inside;
  }

  bool _pointInsideFillTarget(Stroke stroke, Offset point) {
    if (stroke.points.length < 2) return false;
    final points = stroke.points.map((sample) => sample.position).toList();
    var left = points.first.dx;
    var right = left;
    var top = points.first.dy;
    var bottom = top;
    for (final sample in points.skip(1)) {
      left = math.min(left, sample.dx);
      right = math.max(right, sample.dx);
      top = math.min(top, sample.dy);
      bottom = math.max(bottom, sample.dy);
    }
    final bounds = Rect.fromLTRB(left, top, right, bottom);
    if (!bounds.inflate(2).contains(point)) return false;

    final shape = stroke.shape;
    if (shape == null || shape.isEmpty) {
      final closeTolerance = math.max(18.0, stroke.pen.size * 2.5).toDouble();
      if (points.length < 4 || (points.first - points.last).distance > closeTolerance) {
        return false;
      }
      return _pointInPolygon(point, points);
    }

    const openShapes = <String>{
      'line', 'arrow', 'vectorArrow', 'dashedLine', 'dottedLine',
      'divider', 'dimensionLine', 'numberLine', 'ruler', 'compass',
      'protractor', 'rayDiagram', 'waveform', 'projectilePath',
    };
    if (openShapes.contains(shape) ||
        shape.toLowerCase().contains('arrow') ||
        shape.toLowerCase().contains('line')) {
      return false;
    }
    if (const {'ellipse', 'circle', 'sphere', 'flowchartConnector', 'animalCell'}.contains(shape)) {
      if (bounds.width <= 0 || bounds.height <= 0) return false;
      final nx = (point.dx - bounds.center.dx) / (bounds.width / 2);
      final ny = (point.dy - bounds.center.dy) / (bounds.height / 2);
      return nx * nx + ny * ny <= 1;
    }
    if (const {'triangle', 'pyramid'}.contains(shape)) {
      return _pointInPolygon(point, <Offset>[
        Offset(bounds.center.dx, bounds.top),
        bounds.bottomRight,
        Offset(bounds.left, bounds.bottom),
      ]);
    }
    if (shape == 'diamond') {
      return _pointInPolygon(point, <Offset>[
        Offset(bounds.center.dx, bounds.top),
        bounds.centerRight,
        Offset(bounds.center.dx, bounds.bottom),
        bounds.centerLeft,
      ]);
    }
    if (shape == 'parallelogram') {
      return _pointInPolygon(point, <Offset>[
        Offset(bounds.left + bounds.width * .22, bounds.top),
        Offset(bounds.right, bounds.top),
        Offset(bounds.right - bounds.width * .22, bounds.bottom),
        Offset(bounds.left, bounds.bottom),
      ]);
    }
    if (shape == 'trapezoid') {
      return _pointInPolygon(point, <Offset>[
        Offset(bounds.left + bounds.width * .2, bounds.top),
        Offset(bounds.right - bounds.width * .2, bounds.top),
        bounds.bottomRight,
        Offset(bounds.left, bounds.bottom),
      ]);
    }
    final sides = <String, int>{
      'pentagon': 5, 'hexagon': 6, 'heptagon': 7,
      'octagon': 8, 'nonagon': 9, 'decagon': 10,
    }[shape];
    if (sides != null) {
      final polygon = List<Offset>.generate(sides, (index) {
        final angle = -math.pi / 2 + index * math.pi * 2 / sides;
        return Offset(
          bounds.center.dx + math.cos(angle) * bounds.width * .48,
          bounds.center.dy + math.sin(angle) * bounds.height * .48,
        );
      });
      return _pointInPolygon(point, polygon);
    }
    return bounds.contains(point);
  }

  void _fillShapeAt(Offset position) {
    if (_pageData['locked'] == true) return;
    for (final stroke in _strokesFor(_pageData).reversed) {
      if (!_pointInsideFillTarget(stroke, position)) continue;
      final raw = _pageData['strokes'];
      if (raw is! List) return;
      _pushUndo();
      _pageData['strokes'] = raw.map((item) {
        if (item is! Map || item['id']?.toString() != stroke.id) return item;
        final updated = item.map<String, Object?>(
          (key, value) => MapEntry(key.toString(), value),
        );
        updated['fill'] = true;
        updated['fillColor'] = _color.toARGB32();
        updated['fillOpacity'] = _opacity.clamp(.05, 1).toDouble();
        return updated;
      }).toList();
      setState(() {});
      _scheduleSave();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Tap inside a closed shape or loop to fill it.')),
    );
  }

  bool _pressureEraseAllowed(PointerEvent event) {
    if (!_settings.getBool('pressureErase')) return true;
    final pressure = _pointFrom(event).pressure;
    final threshold = _settings.getDouble('pressureEraseThreshold').clamp(0.0, 1.0).toDouble();
    return pressure >= threshold;
  }

  double _pressureEraseRadius(
    PointerEvent event, {
    double? baseRadius,
  }) {
    final radius = baseRadius ?? math.max(18, _size * 2).toDouble();
    if (!_settings.getBool('pressureErase')) return radius;
    final pressure = _pointFrom(event).pressure.clamp(0.0, 1.0).toDouble();
    final threshold = _settings.getDouble('pressureEraseThreshold').clamp(0.0, 1.0).toDouble();
    final effectivePressure = threshold >= 1
        ? (pressure >= 1 ? 1.0 : 0.0)
        : ((pressure - threshold) / (1 - threshold)).clamp(0.0, 1.0).toDouble();
    return radius * (0.08 + effectivePressure * 1.42);
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_readingMode) {
      _navigationOnlyPointers.add(event.pointer);
      return;
    }
    _lastEraseTimestamp = null;
    _lastErasePosition = event.localPosition;
    _eraseUndoCaptured = false;
    _eraseWorkingStrokes = null;
    _activePointers.add(event.pointer);
    if (event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus) {
      _stylusPointers.add(event.pointer);
    }
    if (_pageData['locked'] == true) {
      final position = event.localPosition;
      final atPageEdge = position.dx < 30 ||
          position.dx > _pageWidth - 30 ||
          position.dy < 30 ||
          position.dy > _pageHeight - 30;
      if (event.kind == PointerDeviceKind.touch &&
          _settings.getBool('pageSwipe') &&
          atPageEdge) {
        // Keep page navigation available while the page content is locked.
        _activePointer = event.pointer;
        _gestureStart = position;
        _holdStartPosition = null;
        _pageSwipeStart = position;
        _pageSwipeTriggered = false;
        _livePoints = <StrokePoint>[];
        _liveStroke = null;
        return;
      }
      _ignoredPointers.add(event.pointer);
      return;
    }
    if (_activePointers.length > 1) {
      if (_activePointer != null) {
        _ignoredPointers.add(_activePointer!);
        _navigationOnlyPointers.remove(_activePointer!);
      }
      _ignoredPointers.add(event.pointer);
      _activePointer = null;
      _livePoints = <StrokePoint>[];
      _liveStroke = null;
      _gestureStart = null;
      if (mounted) setState(() {});
      return;
    }
    if (event.kind == PointerDeviceKind.touch && _settings.getBool('fingerWritingProtection')) {
      _navigationOnlyPointers.add(event.pointer);
      _activePointer = event.pointer;
      _gestureStart = event.localPosition;
      _holdStartPosition = null;
      _pageSwipeStart = _settings.getBool('pageSwipe') ? event.localPosition : null;
      _pageSwipeTriggered = false;
      _longPressTriggered = false;
      _livePoints = <StrokePoint>[];
      _liveStroke = null;
      setState(() {});
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
    final touchPosition = event.localPosition;
    final atPageEdge = touchPosition.dx < 30 ||
        touchPosition.dx > _pageWidth - 30 ||
        touchPosition.dy < 30 ||
        touchPosition.dy > _pageHeight - 30;
    _pageSwipeStart = event.kind == PointerDeviceKind.touch &&
            _settings.getBool('pageSwipe') &&
            atPageEdge
        ? touchPosition
        : null;
    _pageSwipeTriggered = false;
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
          _toolBeforePressureErase = _tool;
          _rememberCurrentToolProfile();
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

  bool _shouldProcessErase(PointerEvent event, double radius) {
    final previousTime = _lastEraseTimestamp;
    final previousPosition = _lastErasePosition;
    if (previousTime != null &&
        event.timeStamp - previousTime < const Duration(milliseconds: 16)) {
      return false;
    }
    if (previousPosition != null &&
        (event.localPosition - previousPosition).distance < math.max(1.5, radius * .12)) {
      return false;
    }
    _lastEraseTimestamp = event.timeStamp;
    _lastErasePosition = event.localPosition;
    return true;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_ignoredPointers.contains(event.pointer)) return;
    if (_activePointer == event.pointer &&
        _pageSwipeStart != null &&
        !_pageSwipeTriggered &&
        !_pressureEraseActive &&
        !_longPressTriggered) {
      final swipe = event.localPosition - _pageSwipeStart!;
      final horizontalSwipe = swipe.dx.abs() > swipe.dy.abs() * 1.25;
      final verticalSwipe = swipe.dy.abs() > swipe.dx.abs() * 1.25;
      if (swipe.distance >= 56 && (horizontalSwipe || verticalSwipe)) {
        _pageSwipeTriggered = true;
        _holdTimer?.cancel();
        _holdTimer = null;
        _holdStartPosition = null;
        _livePoints.clear();
        _liveStroke = null;
        _eraserCursor = null;
        setState(() {});
        return;
      }
    }
    if (_activePointer == event.pointer && _pageSwipeTriggered) return;
    if (_navigationOnlyPointers.contains(event.pointer)) return;
    // A locked page may participate in edge swipes, but must never render a
    // transient ink preview from an unfinished navigation gesture.
    if (_pageData['locked'] == true) return;
    if (_activePointer == event.pointer && _holdStartPosition != null &&
        (event.localPosition - _holdStartPosition!).distance > 11 &&
        !_pressureEraseActive && !_longPressTriggered) {
      _holdTimer?.cancel();
      _holdTimer = null;
      _holdStartPosition = null;
    }
    if (_activePointer == event.pointer && _pressureEraseActive) {
      _eraserCursor = event.localPosition;
      final radius = _pressureEraseRadius(event);
      _eraserCursorRadius = radius;
      final previousPosition = _lastErasePosition ?? event.localPosition;
      if (_pressureEraseAllowed(event) && _shouldProcessErase(event, radius)) {
        _eraseAlongSegment(previousPosition, event.localPosition, radius);
      }
      setState(() {});
      return;
    }
    if (_activePointer == event.pointer &&
        (_tool == CanvasTool.eraser || _tool == CanvasTool.pixelEraser)) {
      _eraserCursor = event.localPosition;
      final precisionRadius = _tool == CanvasTool.pixelEraser ||
          _settings.getString('eraserMode') == 'pixel';
      final baseRadius = precisionRadius ? 7.0 : math.max(18, _size * 2).toDouble();
      final radius = _pressureEraseRadius(event, baseRadius: baseRadius);
      _eraserCursorRadius = radius;
      final previousPosition = _lastErasePosition ?? event.localPosition;
      if (_pressureEraseAllowed(event) && _shouldProcessErase(event, radius)) {
        _eraseAlongSegment(previousPosition, event.localPosition, radius);
      }
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
    if (_ignoredPointers.remove(event.pointer)) {
      _navigationOnlyPointers.remove(event.pointer);
      return;
    }
    if (_navigationOnlyPointers.contains(event.pointer) && !_pageSwipeTriggered) {
      _navigationOnlyPointers.remove(event.pointer);
      if (_activePointer == event.pointer) {
        setState(() {
          _activePointer = null;
          _gestureStart = null;
          _pageSwipeStart = null;
          _livePoints.clear();
          _liveStroke = null;
          _eraserCursor = null;
        });
      }
      return;
    }
    if (_activePointer != event.pointer) {
      _navigationOnlyPointers.remove(event.pointer);
      return;
    }
    if (_pageSwipeTriggered && _pageSwipeStart != null) {
      _navigationOnlyPointers.remove(event.pointer);
      final swipe = event.localPosition - _pageSwipeStart!;
      final horizontalSwipe = swipe.dx.abs() > swipe.dy.abs() * 1.25;
      final forward = horizontalSwipe ? swipe.dx < 0 : swipe.dy > 0;
      setState(() {
        _activePointer = null;
        _gestureStart = null;
        _pageSwipeStart = null;
        _pageSwipeTriggered = false;
        _livePoints.clear();
        _liveStroke = null;
        _eraserCursor = null;
      });
      if (forward) {
        if (_page + 1 < _pages.length) {
          _goToPage(_page + 1);
        } else if (_settings.getBool('autoAddPage')) {
          _addPage();
        }
      } else if (_page > 0) {
        _goToPage(_page - 1);
      }
      return;
    }
    _pageSwipeStart = null;
    _pageSwipeTriggered = false;
    if (_pageData['locked'] == true) {
      setState(() {
        _activePointer = null;
        _gestureStart = null;
        _livePoints = <StrokePoint>[];
        _liveStroke = null;
        _eraserCursor = null;
      });
      return;
    }
    if (_longPressTriggered) {
      final wasPressureErase = _pressureEraseActive;
      final restoreTool = _toolBeforePressureErase;
      if (wasPressureErase && _pressureEraseAllowed(event)) {
        _eraseAt(event.localPosition, _pressureEraseRadius(event));
      }
      setState(() {
        _activePointer = null;
        _gestureStart = null;
        _livePoints = <StrokePoint>[];
        _liveStroke = null;
        _pressureEraseActive = false;
        _toolBeforePressureErase = null;
        _longPressTriggered = false;
        _eraserCursor = null;
      });
      if (restoreTool != null) _selectTool(restoreTool);
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
      final precisionRadius = _tool == CanvasTool.pixelEraser ||
          _settings.getString('eraserMode') == 'pixel';
      final baseRadius = precisionRadius ? 7.0 : math.max(18, _size * 2).toDouble();
      if (_pressureEraseAllowed(event)) {
        _eraseAt(
          end,
          _pressureEraseRadius(event, baseRadius: baseRadius),
        );
      }
    } else if (_tool == CanvasTool.lasso) {
      final lassoPath = completedPoints.map((sample) => sample.position).toList();
      final pathLength = lassoPath.length < 2
          ? 0.0
          : List.generate(lassoPath.length - 1, (i) => (lassoPath[i + 1] - lassoPath[i]).distance)
              .fold<double>(0, (sum, distance) => sum + distance);
      if (pathLength < 10) {
        _selectStrokeAt(end, radius: math.max(14, _size * 2));
      } else {
        _selectInPolygon(lassoPath);
      }
    } else if (_tool == CanvasTool.fill) {
      _fillShapeAt(end);
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
        _clearSelectionIds();
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
    _pageSwipeStart = null;
    _pageSwipeTriggered = false;
    final restoreTool = _pressureEraseActive ? _toolBeforePressureErase : null;
    _toolBeforePressureErase = null;
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
    if (restoreTool != null) _selectTool(restoreTool);
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

  void _eraseAlongSegment(Offset from, Offset to, double radius) {
    final distance = (to - from).distance;
    final spacing = math.max(2.0, radius * .45);
    final steps = math.max(1, (distance / spacing).ceil());
    for (var step = 0; step <= steps; step++) {
      _eraseAt(Offset.lerp(from, to, step / steps)!, radius);
    }
  }

  void _eraseAt(Offset position, double radius) {
    final raw = _pageData['strokes'];
    if (raw is! List || raw.isEmpty) {
      _eraseWorkingStrokes = null;
      return;
    }

    // Decode once for the entire drag. Mutate the cached working vector set
    // until the pointer is released instead of reparsing every saved sample.
    final decoded = _eraseWorkingStrokes ??
        StrokeCodec.documentToStrokes(<String, Object?>{'strokes': raw});
    _eraseWorkingStrokes = decoded;
    final retained = <Stroke>[];
    var changed = false;
    final partialErase = _pressureEraseActive
        ? _settings.getString('pressureEraserMode') == 'pixel'
        : (_tool == CanvasTool.pixelEraser || _settings.getString('eraserMode') == 'pixel');

    for (final stroke in decoded) {
      if (stroke.points.isEmpty) {
        retained.add(stroke);
        continue;
      }
      final footprint = Rect.fromCenter(
        center: position,
        width: radius * 2,
        height: radius * 1.4,
      ).inflate(stroke.pen.size / 2);
      var hit = footprint.contains(stroke.points.first.position);
      for (var i = 1; !hit && i < stroke.points.length; i++) {
        hit = footprint.contains(stroke.points[i].position) ||
            _segmentIntersectsRect(
              stroke.points[i - 1].position,
              stroke.points[i].position,
              footprint,
            );
      }

      if (!hit) {
        retained.add(stroke);
        continue;
      }

      changed = true;
      // Freehand ink can be clipped into two or more surviving pieces in
      // pixel mode. Shape primitives and text-like strokes remain atomic.
      if (!partialErase || stroke.shape != null || stroke.stickerText != null) {
        continue;
      }
      final fragments = _splitStrokeOutsideRect(stroke.points, footprint);
      var fragmentNumber = 0;
      for (final fragment in fragments) {
        if (fragment.length < 2) continue;
        final fragmentId =
            '${stroke.id}-px-${DateTime.now().microsecondsSinceEpoch}-${fragmentNumber++}';
        retained.add(stroke.copyWith(id: fragmentId, points: fragment));
      }
    }

    if (!changed) return;
    _eraseWorkingStrokes = retained;
    // One undo checkpoint covers an entire eraser gesture, not each pointer
    // sample. This avoids repeated deep snapshots on long documents.
    if (!_eraseUndoCaptured) {
      _pushUndo();
      _eraseUndoCaptured = true;
    }
    _pageData['strokes'] = retained.map(StrokeCodec.strokeToJson).toList();
    setState(() {
      _clearSelectionIds();
      _eraserCursor = position;
    });
    _scheduleSave();
  }

  List<List<StrokePoint>> _splitStrokeOutsideRect(
    List<StrokePoint> points,
    Rect eraseRect,
  ) {
    if (points.isEmpty) return const <List<StrokePoint>>[];
    if (points.length == 1) {
      return eraseRect.contains(points.single.position)
          ? const <List<StrokePoint>>[]
          : <List<StrokePoint>>[points];
    }

    final fragments = <List<StrokePoint>>[];
    var current = <StrokePoint>[];
    final sampleSpacing = math.max(
      1.5,
      math.min(eraseRect.width, eraseRect.height) * .12,
    );

    void flush() {
      // Two or more samples are required for a surviving line fragment.
      if (current.length >= 2) fragments.add(current);
      current = <StrokePoint>[];
    }

    void addOutside(StrokePoint point) {
      if (eraseRect.contains(point.position)) {
        flush();
        return;
      }
      if (current.isEmpty ||
          (current.last.position - point.position).distance > .15) {
        current.add(point);
      }
    }

    for (var i = 1; i < points.length; i++) {
      final start = points[i - 1];
      final end = points[i];
      final distance = (end.position - start.position).distance;
      final steps = math.max(1, (distance / sampleSpacing).ceil());
      for (var step = i == 1 ? 0 : 1; step <= steps; step++) {
        final t = step / steps;
        addOutside(StrokePoint(
          position: Offset.lerp(start.position, end.position, t)!,
          pressure: start.pressure + (end.pressure - start.pressure) * t,
          timestamp: start.timestamp + (end.timestamp - start.timestamp) * t,
          tilt: start.tilt + (end.tilt - start.tilt) * t,
          orientation: start.orientation +
              (end.orientation - start.orientation) * t,
        ));
      }
    }
    flush();
    return fragments;
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

  bool _segmentIntersectsRect(Offset start, Offset end, Rect rect) {
    if (rect.contains(start) || rect.contains(end)) return true;
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    var tMin = 0.0;
    var tMax = 1.0;
    final p = <double>[-dx, dx, -dy, dy];
    final q = <double>[
      start.dx - rect.left,
      rect.right - start.dx,
      start.dy - rect.top,
      rect.bottom - start.dy,
    ];
    for (var i = 0; i < 4; i++) {
      if (p[i].abs() < 1e-9) {
        if (q[i] < 0) return false;
        continue;
      }
      final ratio = q[i] / p[i];
      if (p[i] < 0) {
        if (ratio > tMax) return false;
        if (ratio > tMin) tMin = ratio;
      } else {
        if (ratio < tMin) return false;
        if (ratio < tMax) tMax = ratio;
      }
    }
    return tMin <= tMax;
  }

  void _clearSelectionIds() {
    _selectedStrokeIds.clear();
    _selectedImageIds.clear();
    _selectedTextBoxIds.clear();
  }

  int get _selectionCount =>
      _selectedStrokeIds.length + _selectedImageIds.length + _selectedTextBoxIds.length;

  double _orientation(Offset a, Offset b, Offset c) =>
      (b.dx - a.dx) * (c.dy - a.dy) - (b.dy - a.dy) * (c.dx - a.dx);

  bool _pointOnSegment(Offset point, Offset a, Offset b) {
    const epsilon = 1e-7;
    if (_orientation(a, b, point).abs() > epsilon) return false;
    return point.dx >= math.min(a.dx, b.dx) - epsilon &&
        point.dx <= math.max(a.dx, b.dx) + epsilon &&
        point.dy >= math.min(a.dy, b.dy) - epsilon &&
        point.dy <= math.max(a.dy, b.dy) + epsilon;
  }

  bool _segmentsIntersect(Offset a, Offset b, Offset c, Offset d) {
    final o1 = _orientation(a, b, c);
    final o2 = _orientation(a, b, d);
    final o3 = _orientation(c, d, a);
    final o4 = _orientation(c, d, b);
    const epsilon = 1e-7;
    if (((o1 > epsilon && o2 < -epsilon) || (o1 < -epsilon && o2 > epsilon)) &&
        ((o3 > epsilon && o4 < -epsilon) || (o3 < -epsilon && o4 > epsilon))) {
      return true;
    }
    return (o1.abs() <= epsilon && _pointOnSegment(c, a, b)) ||
        (o2.abs() <= epsilon && _pointOnSegment(d, a, b)) ||
        (o3.abs() <= epsilon && _pointOnSegment(a, c, d)) ||
        (o4.abs() <= epsilon && _pointOnSegment(b, c, d));
  }

  bool _polygonIntersectsRect(List<Offset> polygon, Rect rect) {
    if (polygon.any(rect.contains)) return true;
    final corners = <Offset>[rect.topLeft, rect.topRight, rect.bottomRight, rect.bottomLeft];
    if (corners.any((corner) => _pointInPolygon(corner, polygon))) return true;
    for (var i = 0; i < polygon.length; i++) {
      final a = polygon[i];
      final b = polygon[(i + 1) % polygon.length];
      for (var j = 0; j < corners.length; j++) {
        if (_segmentsIntersect(a, b, corners[j], corners[(j + 1) % corners.length])) {
          return true;
        }
      }
    }
    return false;
  }

  void _selectInRect(Rect rect) {
    final normalized = Rect.fromLTRB(
      math.min(rect.left, rect.right),
      math.min(rect.top, rect.bottom),
      math.max(rect.left, rect.right),
      math.max(rect.top, rect.bottom),
    );
    _selectInPolygon(<Offset>[
      normalized.topLeft,
      normalized.topRight,
      normalized.bottomRight,
      normalized.bottomLeft,
    ]);
  }

  void _selectInPolygon(List<Offset> sourcePolygon) {
    if (sourcePolygon.length < 3) {
      if (sourcePolygon.isNotEmpty) _selectInRect(Rect.fromPoints(sourcePolygon.first, sourcePolygon.last));
      return;
    }
    final polygon = List<Offset>.unmodifiable(_simplifyLassoOutline(sourcePolygon));
    final xs = polygon.map((point) => point.dx);
    final ys = polygon.map((point) => point.dy);
    final left = xs.reduce((a, b) => math.min(a, b).toDouble());
    final right = xs.reduce((a, b) => math.max(a, b).toDouble());
    final top = ys.reduce((a, b) => math.min(a, b).toDouble());
    final bottom = ys.reduce((a, b) => math.max(a, b).toDouble());
    final polygonBounds = Rect.fromLTRB(left, top, right, bottom);
    final selectedStrokes = <String>{};
    // Keep the freeform lasso responsive on dense pages: reject strokes outside
    // the lasso bounds before checking their geometry, then select visible ink
    // that touches the outline as well as ink fully inside it.
    for (final stroke in _strokesFor(_pageData)) {
      if (stroke.points.isEmpty) continue;
      final strokeRadius = math.max(1.5, stroke.pen.size / 2);
      var strokeBounds = Rect.fromPoints(
        stroke.points.first.position,
        stroke.points.first.position,
      );
      for (final sample in stroke.points.skip(1)) {
        strokeBounds = strokeBounds.expandToInclude(
          Rect.fromPoints(sample.position, sample.position),
        );
      }
      if (!strokeBounds.inflate(strokeRadius).overlaps(polygonBounds)) continue;

      var selected = false;
      for (final sample in stroke.points) {
        final point = sample.position;
        if (_pointInPolygon(point, polygon)) {
          selected = true;
          break;
        }
        for (var i = 0; i < polygon.length; i++) {
          if (_distanceToSegment(point, polygon[i], polygon[(i + 1) % polygon.length]) <= strokeRadius) {
            selected = true;
            break;
          }
        }
        if (selected) break;
      }
      // Catch a lasso boundary that crosses between widely spaced ink samples.
      for (var i = 1; !selected && i < stroke.points.length; i++) {
        final a = stroke.points[i - 1].position;
        final b = stroke.points[i].position;
        for (var j = 0; j < polygon.length; j++) {
          if (_segmentsIntersect(a, b, polygon[j], polygon[(j + 1) % polygon.length])) {
            selected = true;
            break;
          }
        }
      }
      if (selected) selectedStrokes.add(stroke.id);
    }

    final selectedImages = <String>{};
    final images = _pageData['images'];
    if (images is List) {
      for (final raw in images.whereType<Map>()) {
        final image = raw.map<String, Object?>((key, value) => MapEntry(key.toString(), value));
        final id = image['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        final x = (image['x'] as num?)?.toDouble() ?? .1;
        final y = (image['y'] as num?)?.toDouble() ?? .1;
        final width = (image['width'] as num?)?.toDouble() ?? .4;
        final height = (image['height'] as num?)?.toDouble() ?? .3;
        final bounds = Rect.fromLTWH(x * _pageWidth, y * _pageHeight, width * _pageWidth, height * _pageHeight);
        if (_polygonIntersectsRect(polygon, bounds)) selectedImages.add(id);
      }
    }

    final selectedTextBoxes = <String>{};
    final textBoxes = _pageData['textBoxes'];
    if (textBoxes is List) {
      for (final raw in textBoxes.whereType<Map>()) {
        final box = raw.map<String, Object?>((key, value) => MapEntry(key.toString(), value));
        final id = box['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        final x = (box['x'] as num?)?.toDouble() ?? .12;
        final y = (box['y'] as num?)?.toDouble() ?? .12;
        final width = (box['width'] as num?)?.toDouble() ?? .68;
        final height = (box['height'] as num?)?.toDouble() ?? .16;
        final bounds = Rect.fromLTWH(x * _pageWidth, y * _pageHeight, width * _pageWidth, height * _pageHeight);
        if (_polygonIntersectsRect(polygon, bounds)) selectedTextBoxes.add(id);
      }
    }

    setState(() {
      _selectedStrokeIds
        ..clear()
        ..addAll(selectedStrokes);
      _selectedImageIds
        ..clear()
        ..addAll(selectedImages);
      _selectedTextBoxIds
        ..clear()
        ..addAll(selectedTextBoxes);
      _lassoRect = polygonBounds;
    });
    final contentBounds = _selectionBounds();
    setState(() => _lassoRect = contentBounds);
  }

  void _deleteSelection() {
    if (_pageData['locked'] == true || _selectionCount == 0) return;
    _pushUndo();
    final rawStrokes = _pageData['strokes'];
    if (rawStrokes is List) {
      final strokes = StrokeCodec.documentToStrokes(<String, Object?>{'strokes': rawStrokes});
      _pageData['strokes'] = strokes
          .where((stroke) => !_selectedStrokeIds.contains(stroke.id))
          .map(StrokeCodec.strokeToJson)
          .toList();
    }
    final rawImages = _pageData['images'];
    if (rawImages is List) {
      _pageData['images'] = rawImages.where((raw) {
        if (raw is! Map) return true;
        return !_selectedImageIds.contains(raw['id']?.toString());
      }).toList();
    }
    final rawBoxes = _pageData['textBoxes'];
    if (rawBoxes is List) {
      for (final id in _selectedTextBoxIds) {
        _textControllers.remove(id)?.dispose();
      }
      _pageData['textBoxes'] = rawBoxes.where((raw) {
        if (raw is! Map) return true;
        return !_selectedTextBoxIds.contains(raw['id']?.toString());
      }).toList();
    }
    setState(() {
      _clearSelectionIds();
      _lassoRect = null;
    });
    _scheduleSave();
  }

  void _moveSelection(Offset delta) {
    if (_pageData['locked'] == true || _selectionCount == 0) return;
    _pushUndo();
    final rawStrokes = _pageData['strokes'];
    if (rawStrokes is List) {
      final strokes = StrokeCodec.documentToStrokes(<String, Object?>{'strokes': rawStrokes});
      _pageData['strokes'] = strokes.map((stroke) {
        if (!_selectedStrokeIds.contains(stroke.id)) return StrokeCodec.strokeToJson(stroke);
        return StrokeCodec.strokeToJson(stroke.copyWith(
          points: stroke.points.map((point) => point.copyWith(position: point.position + delta)).toList(),
        ));
      }).toList();
    }
    for (final key in const ['images', 'textBoxes']) {
      final raw = _pageData[key];
      if (raw is! List) continue;
      final selectedIds = key == 'images' ? _selectedImageIds : _selectedTextBoxIds;
      _pageData[key] = raw.whereType<Map>().map((item) {
        final object = item.map<String, Object?>((k, v) => MapEntry(k.toString(), v));
        if (!selectedIds.contains(object['id']?.toString())) return object;
        final x = (object['x'] as num?)?.toDouble() ?? .1;
        final y = (object['y'] as num?)?.toDouble() ?? .1;
        final width = (object['width'] as num?)?.toDouble() ?? .4;
        final height = (object['height'] as num?)?.toDouble() ?? .2;
        object['x'] = (x + delta.dx / _pageWidth).clamp(0.0, math.max(0.0, 1 - width)).toDouble();
        object['y'] = (y + delta.dy / _pageHeight).clamp(0.0, math.max(0.0, 1 - height)).toDouble();
        return object;
      }).toList();
    }
    setState(() => _lassoRect = _selectionBounds());
    _scheduleSave();
  }

  Rect? _selectionBounds() {
    final bounds = <Rect>[];
    final selectedStrokes = _strokesFor(_pageData).where((stroke) => _selectedStrokeIds.contains(stroke.id));
    for (final stroke in selectedStrokes) {
      if (stroke.points.isEmpty) continue;
      var left = stroke.points.first.position.dx;
      var right = left;
      var top = stroke.points.first.position.dy;
      var bottom = top;
      for (final point in stroke.points.skip(1)) {
        left = math.min(left, point.position.dx);
        right = math.max(right, point.position.dx);
        top = math.min(top, point.position.dy);
        bottom = math.max(bottom, point.position.dy);
      }
      bounds.add(Rect.fromLTRB(left, top, right, bottom));
    }
    for (final spec in <({String key, Set<String> ids, double width, double height})>[
      (key: 'images', ids: _selectedImageIds, width: .4, height: .3),
      (key: 'textBoxes', ids: _selectedTextBoxIds, width: .68, height: .16),
    ]) {
      final raw = _pageData[spec.key];
      if (raw is! List) continue;
      for (final item in raw.whereType<Map>()) {
        if (!spec.ids.contains(item['id']?.toString())) continue;
        final x = (item['x'] as num?)?.toDouble() ?? .1;
        final y = (item['y'] as num?)?.toDouble() ?? .1;
        final width = (item['width'] as num?)?.toDouble() ?? spec.width;
        final height = (item['height'] as num?)?.toDouble() ?? spec.height;
        bounds.add(Rect.fromLTWH(x * _pageWidth, y * _pageHeight, width * _pageWidth, height * _pageHeight));
      }
    }
    if (bounds.isEmpty) return null;
    var result = bounds.first;
    for (final item in bounds.skip(1)) {
      result = result.expandToInclude(item);
    }
    return result.inflate(3);
  }

  Rect _transformObjectRect(Map<String, Object?> object, Offset center, double factor, Offset offset, {double defaultWidth = .4, double defaultHeight = .2}) {
    final x = (object['x'] as num?)?.toDouble() ?? .1;
    final y = (object['y'] as num?)?.toDouble() ?? .1;
    final width = (object['width'] as num?)?.toDouble() ?? defaultWidth;
    final height = (object['height'] as num?)?.toDouble() ?? defaultHeight;
    final original = Rect.fromLTWH(x * _pageWidth, y * _pageHeight, width * _pageWidth, height * _pageHeight);
    return Rect.fromLTWH(
      center.dx + (original.left - center.dx) * factor + offset.dx,
      center.dy + (original.top - center.dy) * factor + offset.dy,
      math.max(8.0, original.width * factor).toDouble(),
      math.max(8.0, original.height * factor).toDouble(),
    );
  }

  void _writeObjectRect(Map<String, Object?> object, Rect rect) {
    final width = (rect.width / _pageWidth).clamp(.01, 1.0).toDouble();
    final height = (rect.height / _pageHeight).clamp(.01, 1.0).toDouble();
    object['width'] = width;
    object['height'] = height;
    object['x'] = (rect.left / _pageWidth).clamp(0.0, math.max(0.0, 1 - width)).toDouble();
    object['y'] = (rect.top / _pageHeight).clamp(0.0, math.max(0.0, 1 - height)).toDouble();
  }

  void _startSelectionTransform({required bool resize, Offset resizeDirection = const Offset(1, 1)}) {
    final bounds = _selectionBounds();
    if (bounds == null || _selectionCount == 0) return;
    _pushUndo();
    _selectionTransformSnapshot = _strokesFor(_pageData)
        .where((stroke) => _selectedStrokeIds.contains(stroke.id))
        .toList();
    List<Map<String, Object?>> captureObjects(String key, Set<String> ids) {
      final raw = _pageData[key];
      if (raw is! List) return <Map<String, Object?>>[];
      return raw.whereType<Map>()
          .where((item) => ids.contains(item['id']?.toString()))
          .map((item) => item.map<String, Object?>((k, v) => MapEntry(k.toString(), v)))
          .toList();
    }
    _selectionTransformImageSnapshot = captureObjects('images', _selectedImageIds);
    _selectionTransformTextSnapshot = captureObjects('textBoxes', _selectedTextBoxIds);
    _selectionTransformBounds = bounds;
    _selectionTransformDelta = Offset.zero;
    _selectionTransformIsResize = resize;
    _selectionResizeDirection = resizeDirection;
  }

  void _updateSelectionTransform(Offset delta) {
    final strokeSnapshot = _selectionTransformSnapshot;
    final imageSnapshot = _selectionTransformImageSnapshot ?? <Map<String, Object?>>[];
    final textSnapshot = _selectionTransformTextSnapshot ?? <Map<String, Object?>>[];
    final bounds = _selectionTransformBounds;
    if (bounds == null || (strokeSnapshot == null && imageSnapshot.isEmpty && textSnapshot.isEmpty)) return;
    final scale = _transform.value.getMaxScaleOnAxis().clamp(.25, 4).toDouble();
    _selectionTransformDelta += delta / scale;
    final factor = _selectionTransformIsResize
        ? (1 + ((_selectionTransformDelta.dx * _selectionResizeDirection.dx) + (_selectionTransformDelta.dy * _selectionResizeDirection.dy)) / math.max(40, bounds.longestSide)).clamp(.35, 3.0).toDouble()
        : 1.0;
    final offset = _selectionTransformIsResize ? Offset.zero : _selectionTransformDelta;
    final center = bounds.center;

    if (strokeSnapshot != null) {
      final byId = <String, Stroke>{for (final stroke in strokeSnapshot) stroke.id: stroke};
      final current = _strokesFor(_pageData);
      _pageData['strokes'] = current.map((stroke) {
        final original = byId[stroke.id];
        if (original == null) return StrokeCodec.strokeToJson(stroke);
        return StrokeCodec.strokeToJson(original.copyWith(
          points: original.points.map((point) => point.copyWith(
            position: center + (point.position - center) * factor + offset,
          )).toList(),
        ));
      }).toList();
    }

    void applyObjects(String key, List<Map<String, Object?>> snapshot, Set<String> ids, {double defaultWidth = .4, double defaultHeight = .2}) {
      if (snapshot.isEmpty) return;
      final source = <String, Map<String, Object?>>{for (final item in snapshot) item['id']?.toString() ?? '': item};
      final raw = _pageData[key];
      if (raw is! List) return;
      _pageData[key] = raw.whereType<Map>().map((item) {
        final object = item.map<String, Object?>((k, v) => MapEntry(k.toString(), v));
        final id = object['id']?.toString() ?? '';
        final original = source[id];
        if (!ids.contains(id) || original == null) return object;
        final originalRect = _transformObjectRect(original, center, factor, offset, defaultWidth: defaultWidth, defaultHeight: defaultHeight);
        _writeObjectRect(object, originalRect);
        if (_selectionTransformIsResize && key == 'textBoxes') {
          final fontSize = (original['fontSize'] as num?)?.toDouble() ?? 18;
          object['fontSize'] = (fontSize * factor).clamp(6.0, 240.0).toDouble();
        }
        return object;
      }).toList();
    }

    applyObjects('images', imageSnapshot, _selectedImageIds, defaultWidth: .4, defaultHeight: .3);
    applyObjects('textBoxes', textSnapshot, _selectedTextBoxIds, defaultWidth: .68, defaultHeight: .16);
    setState(() => _lassoRect = _selectionBounds());
    _scheduleSave();
  }

  void _finishSelectionTransform() {
    _selectionTransformSnapshot = null;
    _selectionTransformImageSnapshot = null;
    _selectionTransformTextSnapshot = null;
    _selectionTransformBounds = null;
    _selectionTransformDelta = Offset.zero;
    _selectionTransformIsResize = false;
  }

  Map<String, Object?> _currentSelectionPayload() {
    final strokeItems = _strokesFor(_pageData)
        .where((stroke) => _selectedStrokeIds.contains(stroke.id))
        .map((stroke) => StrokeCodec.strokeToJson(stroke).map<String, Object?>(
              (key, value) => MapEntry(key.toString(), value),
            ))
        .toList();
    List<Map<String, Object?>> objects(String key, Set<String> ids) {
      final raw = _pageData[key];
      if (raw is! List) return <Map<String, Object?>>[];
      return raw.whereType<Map>()
          .where((item) => ids.contains(item['id']?.toString()))
          .map((item) => item.map<String, Object?>((k, v) => MapEntry(k.toString(), v)))
          .toList();
    }
    return <String, Object?>{
      'strokes': strokeItems,
      'images': objects('images', _selectedImageIds),
      'textBoxes': objects('textBoxes', _selectedTextBoxIds),
    };
  }

  Map<String, Object?> _cloneSelectionPayload(Map<String, Object?> payload) {
    final decoded = jsonDecode(jsonEncode(payload)) as Map;
    return decoded.map<String, Object?>((key, value) => MapEntry(key.toString(), value));
  }

  void _copySelection() {
    if (_selectionCount == 0) return;
    final payload = _cloneSelectionPayload(_currentSelectionPayload());
    _selectionClipboard = payload;
    _selectionClipboardHistory.insert(0, _cloneSelectionPayload(payload));
    if (_selectionClipboardHistory.length > 4) {
      _selectionClipboardHistory.removeRange(4, _selectionClipboardHistory.length);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied selection ($_selectionCount item(s)); clipboard keeps the last 4 actions.')),
    );
  }

  Future<void> _openMultiSplitWorkspace() async {
    try {
      final notes = await _repo.listAllVisible(limit: 300);
      if (!mounted) return;
      final candidates = notes.where((note) => note.id != widget.note.id).toList(growable: false);
      if (candidates.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Create or import another note before opening split view.')),
        );
        return;
      }
      final selected = await showModalBottomSheet<LocalNote>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) => SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .7,
          child: Column(
            children: [
              const ListTile(
                leading: Icon(Icons.view_column_outlined),
                title: Text('Choose the second note'),
                subtitle: Text('The current note stays on the left.'),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: candidates.length,
                  itemBuilder: (_, index) {
                    final note = candidates[index];
                    return ListTile(
                      leading: const Icon(Icons.description_outlined),
                      title: Text(note.title.isEmpty ? 'Untitled note' : note.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(note.updatedAt.toString(), maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.pop(sheetContext, note),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
      if (selected == null || !mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => MultiSplitNoteWorkspace(
            firstNote: widget.note,
            secondNote: selected,
          ),
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('[Snote][EditorV2] split workspace failed: $error\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open split workspace: $error')),
        );
      }
    }
  }

  Future<void> _showClipboardHistory() async {
    if (_selectionClipboardHistory.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Copy or cut a selection first.')),
      );
      return;
    }
    final selected = await showModalBottomSheet<Map<String, Object?>>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          children: [
            const ListTile(
              leading: Icon(Icons.content_paste_rounded),
              title: Text('Selection clipboard'),
              subtitle: Text('Choose one of the last four copied or cut actions'),
            ),
            for (var index = 0; index < _selectionClipboardHistory.length; index++)
              Builder(builder: (context) {
                final payload = _selectionClipboardHistory[index];
                final count = (payload['strokes'] as List? ?? const []).length +
                    (payload['images'] as List? ?? const []).length +
                    (payload['textBoxes'] as List? ?? const []).length;
                return ListTile(
                  leading: CircleAvatar(child: Text('${index + 1}')),
                  title: Text(index == 0 ? 'Most recent selection' : 'Clipboard item ${index + 1}'),
                  subtitle: Text('$count object(s)'),
                  onTap: () => Navigator.pop(sheetContext, _cloneSelectionPayload(payload)),
                );
              }),
          ],
        ),
      ),
    );
    if (selected != null && mounted) _pasteStrokes(payloadOverride: selected);
  }

  void _cutSelection() {
    _copySelection();
    _deleteSelection();
  }

  void _pasteStrokes({bool duplicate = false, Map<String, Object?>? payloadOverride}) {
    if (_pageData['locked'] == true) return;
    final payload = payloadOverride ?? (duplicate ? _currentSelectionPayload() : _selectionClipboard);
    if (payload == null) return;
    final sourceStrokes = StrokeCodec.documentToStrokes(
      <String, Object?>{'strokes': payload['strokes'] is List ? payload['strokes'] : <Object?>[]},
    );
    final sourceImages = (payload['images'] is List ? payload['images'] as List : const <Object?>[])
        .whereType<Map>()
        .map((item) => item.map<String, Object?>((k, v) => MapEntry(k.toString(), v)))
        .toList();
    final sourceTextBoxes = (payload['textBoxes'] is List ? payload['textBoxes'] as List : const <Object?>[])
        .whereType<Map>()
        .map((item) => item.map<String, Object?>((k, v) => MapEntry(k.toString(), v)))
        .toList();
    if (sourceStrokes.isEmpty && sourceImages.isEmpty && sourceTextBoxes.isEmpty) return;
    _pushUndo();
    final offset = duplicate ? const Offset(22, 22) : const Offset(18, 18);
    final addedStrokes = sourceStrokes.map((stroke) => StrokeCodec.strokeToJson(stroke.copyWith(
      id: DateTime.now().microsecondsSinceEpoch.toString() + '-${math.Random().nextInt(100000)}',
      points: stroke.points.map((point) => point.copyWith(position: point.position + offset)).toList(),
    ))).toList();
    final rawStrokes = _pageData['strokes'];
    if (rawStrokes is List) rawStrokes.addAll(addedStrokes);

    final addedImageIds = <String>{};
    final rawImages = _pageData['images'];
    final addedImages = sourceImages.map((source) {
      final image = Map<String, Object?>.from(source);
      final id = DateTime.now().microsecondsSinceEpoch.toString() + '-image-${math.Random().nextInt(100000)}';
      image['id'] = id;
      final width = (image['width'] as num?)?.toDouble() ?? .4;
      final height = (image['height'] as num?)?.toDouble() ?? .3;
      image['x'] = (((image['x'] as num?)?.toDouble() ?? .1) + offset.dx / _pageWidth).clamp(0.0, math.max(0.0, 1 - width)).toDouble();
      image['y'] = (((image['y'] as num?)?.toDouble() ?? .1) + offset.dy / _pageHeight).clamp(0.0, math.max(0.0, 1 - height)).toDouble();
      addedImageIds.add(id);
      return image;
    }).toList();
    if (rawImages is List) rawImages.addAll(addedImages);

    final addedTextIds = <String>{};
    final rawText = _pageData['textBoxes'];
    final addedTextBoxes = sourceTextBoxes.map((source) {
      final box = Map<String, Object?>.from(source);
      final id = DateTime.now().microsecondsSinceEpoch.toString() + '-text-${math.Random().nextInt(100000)}';
      box['id'] = id;
      final width = (box['width'] as num?)?.toDouble() ?? .68;
      final height = (box['height'] as num?)?.toDouble() ?? .16;
      box['x'] = (((box['x'] as num?)?.toDouble() ?? .12) + offset.dx / _pageWidth).clamp(0.0, math.max(0.0, 1 - width)).toDouble();
      box['y'] = (((box['y'] as num?)?.toDouble() ?? .12) + offset.dy / _pageHeight).clamp(0.0, math.max(0.0, 1 - height)).toDouble();
      _textControllers[id] = TextEditingController(text: box['text']?.toString() ?? '');
      addedTextIds.add(id);
      return box;
    }).toList();
    if (rawText is List) rawText.addAll(addedTextBoxes);

    final addedStrokeIds = addedStrokes.map((item) => item['id']?.toString() ?? '').where((value) => value.isNotEmpty).toSet();
    setState(() {
      _selectedStrokeIds
        ..clear()
        ..addAll(addedStrokeIds);
      _selectedImageIds
        ..clear()
        ..addAll(addedImageIds);
      _selectedTextBoxIds
        ..clear()
        ..addAll(addedTextIds);
      _lassoRect = _selectionBounds();
    });
    _scheduleSave();
  }

  void _scaleSelection(double factor) {
    if (_pageData['locked'] == true || _selectionCount == 0) return;
    final bounds = _selectionBounds();
    if (bounds == null) return;
    _pushUndo();
    final center = bounds.center;
    final rawStrokes = _pageData['strokes'];
    if (rawStrokes is List) {
      final strokes = StrokeCodec.documentToStrokes(<String, Object?>{'strokes': rawStrokes});
      _pageData['strokes'] = strokes.map((stroke) {
        if (!_selectedStrokeIds.contains(stroke.id)) return StrokeCodec.strokeToJson(stroke);
        return StrokeCodec.strokeToJson(stroke.copyWith(
          points: stroke.points.map((point) => point.copyWith(
            position: center + (point.position - center) * factor,
          )).toList(),
        ));
      }).toList();
    }
    for (final key in const ['images', 'textBoxes']) {
      final raw = _pageData[key];
      if (raw is! List) continue;
      final ids = key == 'images' ? _selectedImageIds : _selectedTextBoxIds;
      _pageData[key] = raw.whereType<Map>().map((item) {
        final object = item.map<String, Object?>((k, v) => MapEntry(k.toString(), v));
        if (!ids.contains(object['id']?.toString())) return object;
        final rect = _transformObjectRect(object, center, factor, Offset.zero, defaultWidth: key == 'images' ? .4 : .68, defaultHeight: key == 'images' ? .3 : .16);
        _writeObjectRect(object, rect);
        if (key == 'textBoxes') {
          object['fontSize'] = (((object['fontSize'] as num?)?.toDouble() ?? 18) * factor).clamp(6.0, 240.0).toDouble();
        }
        return object;
      }).toList();
    }
    setState(() => _lassoRect = _selectionBounds());
    _scheduleSave();
  }

  void _changeSelectionLayer({required bool bringToFront}) {
    if (_pageData['locked'] == true || _selectionCount == 0) return;
    _pushUndo();
    if (_selectedStrokeIds.isNotEmpty) {
      final raw = _pageData['strokes'];
      if (raw is List) {
        final strokes = StrokeCodec.documentToStrokes(<String, Object?>{'strokes': raw});
        final selected = strokes.where((stroke) => _selectedStrokeIds.contains(stroke.id)).toList();
        final unselected = strokes.where((stroke) => !_selectedStrokeIds.contains(stroke.id)).toList();
        final reordered = bringToFront
            ? <Stroke>[...unselected, ...selected]
            : <Stroke>[...selected, ...unselected];
        _pageData['strokes'] = reordered.map(StrokeCodec.strokeToJson).toList();
      }
    }
    void reorderObjects(String key, Set<String> ids) {
      if (ids.isEmpty) return;
      final raw = _pageData[key];
      if (raw is! List) return;
      final selected = raw.whereType<Map>()
          .where((item) => ids.contains(item['id']?.toString()))
          .map((item) => item.map<String, Object?>((k, v) => MapEntry(k.toString(), v)))
          .toList();
      final unselected = raw.whereType<Map>()
          .where((item) => !ids.contains(item['id']?.toString()))
          .map((item) => item.map<String, Object?>((k, v) => MapEntry(k.toString(), v)))
          .toList();
      _pageData[key] = bringToFront
          ? <Map<String, Object?>>[...unselected, ...selected]
          : <Map<String, Object?>>[...selected, ...unselected];
    }
    reorderObjects('images', _selectedImageIds);
    reorderObjects('textBoxes', _selectedTextBoxIds);
    setState(() {});
    _scheduleSave();
  }

  bool _selectStrokeAt(Offset position, {double radius = 12}) {
    bool selectObjects(String key, Set<String> destination, {double defaultWidth = .4, double defaultHeight = .2}) {
      final raw = _pageData[key];
      if (raw is! List) return false;
      for (final item in raw.whereType<Map>().toList().reversed) {
        final object = item.map<String, Object?>((k, v) => MapEntry(k.toString(), v));
        final id = object['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        final x = (object['x'] as num?)?.toDouble() ?? .1;
        final y = (object['y'] as num?)?.toDouble() ?? .1;
        final width = (object['width'] as num?)?.toDouble() ?? defaultWidth;
        final height = (object['height'] as num?)?.toDouble() ?? defaultHeight;
        final bounds = Rect.fromLTWH(x * _pageWidth, y * _pageHeight, width * _pageWidth, height * _pageHeight).inflate(radius);
        if (!bounds.contains(position)) continue;
        setState(() {
          _tool = CanvasTool.lasso;
          _clearSelectionIds();
          destination.add(id);
          _lassoRect = bounds;
        });
        return true;
      }
      return false;
    }

    if (selectObjects('textBoxes', _selectedTextBoxIds, defaultWidth: .68, defaultHeight: .16)) return true;
    if (selectObjects('images', _selectedImageIds, defaultWidth: .4, defaultHeight: .3)) return true;

    for (final stroke in _strokesFor(_pageData).reversed) {
      if (stroke.points.isEmpty) continue;
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
            _clearSelectionIds();
            _selectedStrokeIds.add(stroke.id);
            _lassoRect = Rect.fromLTRB(left, top, right, bottom).inflate(5);
          });
          return true;
        }
      }
    }
    return false;
  }

  Future<void> _toggleNoteSwitcher() async {
    setState(() => _showNoteSwitcherInTitleBar = !_showNoteSwitcherInTitleBar);
    await _settings.setBool('editorV2ShowNoteSwitcher', _showNoteSwitcherInTitleBar);
  }

  Future<void> _toggleTabsBar() async {
    final next = !_showTabsBar;
    setState(() {
      _showTabsBar = next;
      _noteTabsFuture ??= _repo.listAllVisible(limit: 12);
    });
    await _settings.setBool('editorV2ShowTabs', next);
  }

  Future<void> _openNoteTab(LocalNote note) async {
    if (note.id == widget.note.id) return;
    await _flushSave();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => EditorV2Page(note: note),
    ));
  }

  Widget _buildNoteTabs() {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: SizedBox(
        height: 44,
        child: FutureBuilder<List<LocalNote>>(
          future: _noteTabsFuture ??= _repo.listAllVisible(limit: 12),
          builder: (context, snapshot) {
            final notes = snapshot.data ?? const <LocalNote>[];
            if (snapshot.hasError) {
              return Align(
                alignment: Alignment.centerLeft,
                child: Text('Could not load note tabs', style: TextStyle(color: Theme.of(context).colorScheme.error)),
              );
            }
            if (notes.isEmpty) return const SizedBox.shrink();
            return ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              itemCount: notes.length,
              separatorBuilder: (_, __) => const SizedBox(width: 5),
              itemBuilder: (context, index) {
                final note = notes[index];
                final active = note.id == widget.note.id;
                return ChoiceChip(
                  visualDensity: VisualDensity.compact,
                  selected: active,
                  avatar: Icon(active ? Icons.edit_note_rounded : Icons.note_outlined, size: 16),
                  label: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 170),
                    child: Text(
                      note.title.trim().isEmpty ? 'Untitled note' : note.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  onSelected: (_) => unawaited(_openNoteTab(note)),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _openNoteSwitcher() async {
    final notes = await _repo.listAllVisible(limit: 100);
    if (!mounted) return;
    final selected = await showModalBottomSheet<LocalNote>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .72,
          child: Column(children: [
            const ListTile(
              leading: Icon(Icons.tab_rounded),
              title: Text('Switch note'),
              subtitle: Text('Open a recent local note without returning to the shelf'),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: notes.length,
                itemBuilder: (_, index) {
                  final note = notes[index];
                  final active = note.id == widget.note.id;
                  return ListTile(
                    leading: Icon(active ? Icons.edit_note_rounded : Icons.note_outlined),
                    title: Text(note.title.isEmpty ? 'Untitled note' : note.title),
                    subtitle: Text(note.noteType),
                    trailing: active ? const Icon(Icons.check_circle_rounded) : null,
                    onTap: () => Navigator.pop(sheetContext, note),
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
    if (selected == null || selected.id == widget.note.id || !mounted) return;
    await _flushSave();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => EditorV2Page(note: selected)),
    );
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
      _clearSelectionIds();
      _lassoRect = null;
    }
  }

  Future<void> _openToolPicker({String? initialCategory}) async {
    Set<String> favoriteShapes = <String>{};
    try {
      final stored = jsonDecode(_settings.getString('editorV2FavoriteShapes'));
      if (stored is List) {
        favoriteShapes = stored.whereType<String>().toSet();
      }
    } catch (_) {
      // Empty favorites are used if a previous beta saved malformed settings.
    }
    final choice = await showModalBottomSheet<_ToolPickerChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EditorV2ToolPicker(
        selected: _tool,
        initialCategory: initialCategory,
        favoriteShapes: favoriteShapes,
        onFavoriteShapesChanged: (items) => unawaited(
          _settings.setString('editorV2FavoriteShapes', jsonEncode(items.toList())),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice.configure) {
      await _strokeSettings(choice.tool, choice.anchor ?? _toolSettingsAnchor);
    } else {
      _selectTool(choice.tool);
    }
  }

  Future<void> _chooseColor() async {
    var selectedColor = _color;
    var selectedOpacity = _opacity;
    var spectrumHue = HSVColor.fromColor(_color).hue;
    final hexController = TextEditingController(
      text: _color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase(),
    );
    final chosen = await showModalBottomSheet<({Color color, double opacity})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ink palette & opacity', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                DefaultTabController(
                  length: 2,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const TabBar(
                        tabs: [
                          Tab(text: 'Grid'),
                          Tab(text: 'Spectrum'),
                        ],
                      ),
                      SizedBox(
                        height: 236,
                        child: TabBarView(
                          children: [
                            GridView.builder(
                              padding: const EdgeInsets.symmetric(vertical: 5),
                              itemCount: 120,
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 12,
                                crossAxisSpacing: 2,
                                mainAxisSpacing: 2,
                              ),
                              itemBuilder: (context, index) {
                                final column = index % 12;
                                final row = index ~/ 12;
                                final color = column == 0
                                    ? HSVColor.fromAHSV(1, 0, 0, (1 - row / 9).clamp(0.0, 1.0)).toColor()
                                    : HSVColor.fromAHSV(
                                        1,
                                        (column - 1) * 360 / 11,
                                        (.22 + row * .085).clamp(0.0, 1.0),
                                        (1 - row * .065).clamp(.35, 1.0),
                                      ).toColor();
                                final selected = color.toARGB32() == selectedColor.toARGB32();
                                return InkWell(
                                  borderRadius: BorderRadius.circular(3),
                                  onTap: () => setSheetState(() {
                                    selectedColor = color;
                                    spectrumHue = HSVColor.fromColor(color).hue;
                                    hexController.text = color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();
                                  }),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: color,
                                      borderRadius: BorderRadius.circular(3),
                                      border: Border.all(
                                        color: selected ? Theme.of(context).colorScheme.primary : Colors.black12,
                                        width: selected ? 2 : 0.5,
                                      ),
                                    ),
                                    child: selected
                                        ? const Icon(Icons.check_rounded, size: 12, color: Colors.white)
                                        : null,
                                  ),
                                );
                              },
                            ),
                            Column(
                              children: [
                                Row(
                                  children: [
                                    const Text('Hue', style: TextStyle(fontSize: 12)),
                                    Expanded(
                                      child: Slider(
                                        min: 0,
                                        max: 360,
                                        value: spectrumHue.clamp(0.0, 360.0).toDouble(),
                                        onChanged: (value) => setSheetState(() {
                                          spectrumHue = value;
                                          selectedColor = HSVColor.fromColor(selectedColor)
                                              .withHue(value.clamp(0.0, 360.0).toDouble())
                                              .toColor();
                                          hexController.text = selectedColor.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();
                                        }),
                                      ),
                                    ),
                                  ],
                                ),
                                Expanded(
                                  child: GridView.builder(
                                    padding: const EdgeInsets.symmetric(vertical: 3),
                                    itemCount: 80,
                                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 10,
                                      crossAxisSpacing: 2,
                                      mainAxisSpacing: 2,
                                    ),
                                    itemBuilder: (context, index) {
                                      final column = index % 10;
                                      final row = index ~/ 10;
                                      final color = HSVColor.fromAHSV(
                                        1,
                                        spectrumHue,
                                        column / 9,
                                        (1 - row * .105).clamp(.05, 1.0),
                                      ).toColor();
                                      final selected = color.toARGB32() == selectedColor.toARGB32();
                                      return InkWell(
                                        borderRadius: BorderRadius.circular(3),
                                        onTap: () => setSheetState(() {
                                          selectedColor = color;
                                          spectrumHue = HSVColor.fromColor(color).hue;
                                          hexController.text = color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();
                                        }),
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: color,
                                            borderRadius: BorderRadius.circular(3),
                                            border: Border.all(
                                              color: selected ? Theme.of(context).colorScheme.primary : Colors.black12,
                                              width: selected ? 2 : .5,
                                            ),
                                          ),
                                          child: selected
                                              ? const Icon(Icons.check_rounded, size: 12, color: Colors.white)
                                              : null,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: hexController,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 8,
                  decoration: const InputDecoration(
                    labelText: 'Custom HEX color',
                    hintText: 'RRGGBB or AARRGGBB',
                    prefixText: '#',
                    counterText: '',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (raw) {
                    final value = raw.trim().replaceAll('#', '');
                    if (value.length != 6 && value.length != 8) return;
                    final parsed = int.tryParse(value, radix: 16);
                    if (parsed == null) return;
                    setSheetState(() {
                      selectedColor = Color(value.length == 6 ? 0xff000000 | parsed : parsed);
                      spectrumHue = HSVColor.fromColor(selectedColor).hue;
                    });
                  },
                ),
                const SizedBox(height: 12),
                Row(children: [
                  const Expanded(child: Text('Opacity')),
                  Text('${(selectedOpacity * 100).round()}%'),
                ]),
                Slider(
                  min: .05,
                  max: 1,
                  value: selectedOpacity.clamp(.05, 1).toDouble(),
                  onChanged: (value) => setSheetState(() => selectedOpacity = value),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(sheetContext, (color: selectedColor, opacity: selectedOpacity)),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Use color'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    hexController.dispose();
    if (chosen == null || !mounted) return;
    setState(() {
      _color = chosen.color;
      _opacity = chosen.opacity;
    });
    _rememberCurrentToolProfile();
  }

  Future<void> _strokeSettings([
    CanvasTool? requestedTool,
    Offset? globalAnchor,
  ]) async {
    final targetTool = requestedTool ?? _tool;
    if (targetTool != _tool) _selectTool(targetTool);
    var size = _size;
    var opacity = _opacity;
    var pressure = _pressureSensitivity;
    var velocity = _velocitySensitivity;
    var curve = _pressureCurve;
    var color = _color;
    var places = Set<String>.from(_placementsFor(targetTool));
    var precisionErase = _settings.getString('eraserMode') == 'pixel';
    var pressurePixelErase = _settings.getString('pressureEraserMode') == 'pixel';

    void saveProfile({bool persist = true}) {
      setState(() {
        _tool = targetTool;
        _size = size;
        _opacity = opacity;
        _pressureSensitivity = pressure;
        _velocitySensitivity = velocity;
        _pressureCurve = curve;
        _color = color;
      });
      _toolPlacements[targetTool.name] = Set<String>.from(places);
      if (persist) unawaited(_saveToolPlacements());
      if (persist && (targetTool == CanvasTool.eraser || targetTool == CanvasTool.pixelEraser)) {
        unawaited(_settings.setString('eraserMode', precisionErase ? 'pixel' : 'stroke'));
        unawaited(_settings.setString('pressureEraserMode', pressurePixelErase ? 'pixel' : 'stroke'));
      }
      _toolProfiles[targetTool.name] = <String, Object?>{
        'size': size,
        'color': color.toARGB32(),
        'opacity': opacity,
        'pressureSensitivity': pressure,
        'velocitySensitivity': velocity,
        'pressureCurve': curve.name,
      };
      if (persist) unawaited(_saveToolProfiles());
    }

    Widget panel(
      BuildContext panelContext,
      StateSetter setPanelState,
      VoidCallback close,
    ) {
      final isPopover = globalAnchor != null;
      final controls = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${targetTool.label} settings',
                  style: Theme.of(panelContext).textTheme.titleMedium,
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Close tool settings',
                onPressed: close,
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _palette.map((candidate) => InkWell(
              onTap: () { setPanelState(() => color = candidate); saveProfile(); },
              borderRadius: BorderRadius.circular(24),
              child: Container(
                width: isPopover ? 25 : 30,
                height: isPopover ? 25 : 30,
                decoration: BoxDecoration(
                  color: candidate,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: candidate == color
                        ? Theme.of(panelContext).colorScheme.primary
                        : Colors.black26,
                    width: candidate == color ? 3 : 1,
                  ),
                ),
              ),
            )).toList(),
          ),
          const SizedBox(height: 8),
          Row(children: [const Icon(Icons.line_weight_rounded, size: 17), const SizedBox(width: 7), Text('Stroke size: ${size.toStringAsFixed(1)}')]),
          Slider(
            min: .5,
            max: 40,
            value: size.clamp(.5, 40),
            onChanged: (value) { setPanelState(() => size = value); saveProfile(persist: false); },
            onChangeEnd: (_) => saveProfile(),
          ),
          Row(children: [const Icon(Icons.opacity_rounded, size: 17), const SizedBox(width: 7), Text('Opacity: ${(opacity * 100).round()}%')]),
          Slider(
            min: .05,
            max: 1,
            value: opacity.clamp(.05, 1),
            onChanged: (value) { setPanelState(() => opacity = value); saveProfile(persist: false); },
            onChangeEnd: (_) => saveProfile(),
          ),
          Row(children: [const Icon(Icons.touch_app_rounded, size: 17), const SizedBox(width: 7), Text('Pressure sensitivity: ${pressure.toStringAsFixed(2)}')]),
          Slider(
            min: 0,
            max: 1,
            value: pressure,
            onChanged: (value) { setPanelState(() => pressure = value); saveProfile(persist: false); },
            onChangeEnd: (_) => saveProfile(),
          ),
          Row(children: [const Icon(Icons.speed_rounded, size: 17), const SizedBox(width: 7), Text('Velocity sensitivity: ${velocity.toStringAsFixed(2)}')]),
          Slider(
            min: 0,
            max: 1,
            value: velocity,
            onChanged: (value) { setPanelState(() => velocity = value); saveProfile(persist: false); },
            onChangeEnd: (_) => saveProfile(),
          ),
          DropdownButtonFormField<PressureCurve>(
            initialValue: curve,
            decoration: const InputDecoration(labelText: 'Pressure curve', prefixIcon: Icon(Icons.show_chart_rounded)),
            items: PressureCurve.values.map((value) => DropdownMenuItem(
              value: value,
              child: Text(value.name),
            )).toList(),
            onChanged: (value) {
              if (value != null) { setPanelState(() => curve = value); saveProfile(); }
            },
          ),
          if (targetTool == CanvasTool.eraser || targetTool == CanvasTool.pixelEraser) ...[
            const Text('Normal eraser'),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, icon: Icon(Icons.gesture_rounded), label: Text('Stroke')),
                ButtonSegment(value: true, icon: Icon(Icons.auto_fix_normal_rounded), label: Text('Pixel')),
              ],
              selected: <bool>{precisionErase},
              onSelectionChanged: (value) {
                setPanelState(() => precisionErase = value.first);
                saveProfile();
              },
            ),
            const SizedBox(height: 8),
            const Text('Pressure eraser'),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, icon: Icon(Icons.gesture_rounded), label: Text('Stroke')),
                ButtonSegment(value: true, icon: Icon(Icons.auto_fix_normal_rounded), label: Text('Pixel')),
              ],
              selected: <bool>{pressurePixelErase},
              onSelectionChanged: (value) {
                setPanelState(() => pressurePixelErase = value.first);
                saveProfile();
              },
            ),
          ],
          if (targetTool == CanvasTool.lasso) ...[
            OutlinedButton.icon(
              icon: const Icon(Icons.text_fields_rounded),
              label: const Text('Convert selected ink to text'),
              onPressed: () {
                saveProfile();
                close();
                unawaited(_convertSelectedInkToText());
              },
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 8),
          const Divider(),
          const Text('Tool placement', style: TextStyle(fontWeight: FontWeight.w800)),
          SegmentedButton<String>(
            showSelectedIcon: false,
            multiSelectionEnabled: true,
            emptySelectionAllowed: true,
            segments: const [
              ButtonSegment(value: 'titleBar', tooltip: 'Title bar', icon: Icon(Icons.title_rounded)),
              ButtonSegment(value: 'toolbar', tooltip: 'Toolbar', icon: Icon(Icons.widgets_outlined)),
              ButtonSegment(value: 'pencase', tooltip: 'Pencase', icon: Icon(Icons.inventory_2_outlined)),
            ],
            selected: places,
            onSelectionChanged: (selection) {
              setPanelState(() {
                places
                  ..clear()
                  ..addAll(selection);
              });
              saveProfile();
            },
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.visibility_off_outlined),
            title: const Text('Hidden / nowhere'),
            subtitle: const Text('Hide this tool from all three locations'),
            value: places.isEmpty,
            onChanged: (value) {
              setPanelState(() {
                if (value) {
                  places.clear();
                } else {
                  places.add('toolbar');
                }
              });
              saveProfile();
            },
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.add_circle_outline_rounded),
              label: const Text('Collect to Pencase'),
              onPressed: () async {
                saveProfile();
                await _collectToolToPencase(
                  tool: targetTool,
                  color: color,
                  size: size,
                  opacity: opacity,
                  pressure: pressure,
                  velocity: velocity,
                  curve: curve,
                );
                setState(() {
                  _toolPlacements[targetTool.name] = <String>{
                    ...places,
                    'pencase',
                  };
                });
                await _saveToolPlacements();
                close();
              },
            ),
          ),
          const SizedBox(height: 4),
          Text('Changes apply immediately.', style: Theme.of(panelContext).textTheme.bodySmall),
        ],
      );
      return Padding(
        padding: EdgeInsets.fromLTRB(
          isPopover ? 12 : 18,
          4,
          isPopover ? 12 : 18,
          isPopover ? 10 : 22 + MediaQuery.viewInsetsOf(panelContext).bottom,
        ),
        child: SingleChildScrollView(child: controls),
      );
    }

    if (globalAnchor == null) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) => StatefulBuilder(
          builder: (panelContext, setPanelState) => SafeArea(
            child: panel(
              panelContext,
              setPanelState,
              () => Navigator.pop(sheetContext),
            ),
          ),
        ),
      );
      return;
    }

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close ${targetTool.label} settings',
      barrierColor: Colors.black12,
      transitionDuration: Duration.zero,
      pageBuilder: (dialogContext, _, __) {
        final screen = MediaQuery.sizeOf(dialogContext);
        final width = math.min(350.0, screen.width - 16);
        final anchor = globalAnchor;
        final left = (anchor.dx > screen.width * .56
                ? anchor.dx - width - 12
                : anchor.dx + 12)
            .clamp(8.0, math.max(8.0, screen.width - width - 8))
            .toDouble();
        final desiredTop = anchor.dy > screen.height * .68
            ? anchor.dy - 350
            : anchor.dy - 36;
        final top = desiredTop
            .clamp(8.0, math.max(8.0, screen.height - 420))
            .toDouble();
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.pop(dialogContext),
              ),
            ),
            Positioned(
              left: left,
              top: top,
              width: width,
              child: Material(
                color: Theme.of(dialogContext).colorScheme.surfaceContainerHigh,
                elevation: 12,
                borderRadius: BorderRadius.circular(14),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: math.min(440.0, screen.height - 24),
                  ),
                  child: StatefulBuilder(
                    builder: (panelContext, setPanelState) => SafeArea(
                      child: panel(
                        panelContext,
                        setPanelState,
                        () => Navigator.pop(dialogContext),
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

  Future<void> _convertSelectedInkToText() async {
    if (_pageData['locked'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unlock this page before converting handwriting.')),
      );
      return;
    }
    final selectedStrokes = _strokesFor(_pageData)
        .where((stroke) => _selectedStrokeIds.contains(stroke.id))
        .where((stroke) => stroke.points.isNotEmpty)
        .toList();
    if (selectedStrokes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Use Lasso to select handwriting strokes first.')),
      );
      return;
    }

    var left = double.infinity;
    var top = double.infinity;
    var right = double.negativeInfinity;
    var bottom = double.negativeInfinity;
    for (final stroke in selectedStrokes) {
      for (final point in stroke.points) {
        left = math.min(left, point.position.dx);
        top = math.min(top, point.position.dy);
        right = math.max(right, point.position.dx);
        bottom = math.max(bottom, point.position.dy);
      }
    }
    final bounds = Rect.fromLTRB(left, top, right, bottom).inflate(14);
    const maxRasterDimension = 2400.0;
    final scale = math.min(
      3.0,
      maxRasterDimension / math.max(bounds.width, bounds.height).clamp(1.0, maxRasterDimension),
    );
    final rasterWidth = math.max(1, (bounds.width * scale).ceil());
    final rasterHeight = math.max(1, (bounds.height * scale).ceil());
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.white, BlendMode.src);
    canvas.save();
    canvas.scale(scale);
    canvas.translate(-bounds.left, -bounds.top);
    for (final stroke in selectedStrokes) {
      final points = stroke.points;
      final ink = Paint()
        ..color = stroke.pen.color.withValues(alpha: stroke.pen.opacity.clamp(.2, 1).toDouble())
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke.pen.size.clamp(.8, 40).toDouble()
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true;
      if (points.length == 1) {
        canvas.drawCircle(points.first.position, math.max(.7, ink.strokeWidth / 2), ink);
      } else {
        final path = Path()..moveTo(points.first.position.dx, points.first.position.dy);
        for (var i = 1; i < points.length - 1; i++) {
          final current = points[i].position;
          final next = points[i + 1].position;
          final midpoint = Offset((current.dx + next.dx) / 2, (current.dy + next.dy) / 2);
          path.quadraticBezierTo(current.dx, current.dy, midpoint.dx, midpoint.dy);
        }
        path.lineTo(points.last.position.dx, points.last.position.dy);
        canvas.drawPath(path, ink);
      }
    }
    canvas.restore();
    final picture = recorder.endRecording();
    final image = await picture.toImage(rasterWidth, rasterHeight);
    final pngData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (pngData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not prepare the selected ink for recognition.')),
      );
      return;
    }

    try {
      final recognizedText = await recognizeSelectionText(
        pngData.buffer.asUint8List(pngData.offsetInBytes, pngData.lengthInBytes),
      );
      if (!mounted) return;
      if (recognizedText.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No text was recognized. Try selecting clearer handwriting.')),
        );
        return;
      }
      _pushUndo();
      final selectedIds = _selectedStrokeIds.toSet();
      final rawStrokes = _pageData['strokes'];
      if (rawStrokes is List) {
        final allStrokes = StrokeCodec.documentToStrokes(<String, Object?>{'strokes': rawStrokes});
        _pageData['strokes'] = allStrokes
            .where((stroke) => !selectedIds.contains(stroke.id))
            .map(StrokeCodec.strokeToJson)
            .toList();
      }
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      final boxX = (bounds.left / _pageWidth).clamp(0.0, .95).toDouble();
      final boxY = (bounds.top / _pageHeight).clamp(0.0, .95).toDouble();
      final boxWidth = (bounds.width / _pageWidth).clamp(.04, math.max(.04, 1 - boxX)).toDouble();
      final boxHeight = (math.max(bounds.height * 1.8, 48) / _pageHeight)
          .clamp(.045, 1 - boxY)
          .toDouble();
      final box = <String, Object?>{
        'id': id,
        'x': boxX,
        'y': boxY,
        'width': boxWidth,
        'height': boxHeight,
        'text': recognizedText.trim(),
        'fontSize': 22.0,
        'color': _color.toARGB32(),
      };
      final rawBoxes = _pageData['textBoxes'];
      if (rawBoxes is List<Object?>) {
        rawBoxes.add(box);
      } else {
        _pageData['textBoxes'] = <Object?>[box];
      }
      _textControllers[id] = TextEditingController(text: recognizedText.trim());
      setState(() {
        _clearSelectionIds();
        _lassoRect = null;
      });
      _scheduleSave();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Handwriting converted to editable text.')),
      );
    } catch (error, stackTrace) {
      debugPrint('[Snote][EditorV2] selection OCR failed: $error\\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Text recognition unavailable: $error')),
        );
      }
    }
  }

  void _addTextBox() {
    if (_pageData['locked'] == true) return;
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
    if (_pageData['locked'] == true) return;
    try {
      final file = await FilePicker.pickFile(type: FileType.image);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      await _insertImageBytes(bytes, name: file.name);
    } catch (error, stackTrace) {
      debugPrint('[Snote][EditorV2] image import failed: $error\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not insert image: $error')),
        );
      }
    }
  }

  Future<Rect?> _chooseCaptureRegion() => showGeneralDialog<Rect>(
        context: context,
        barrierDismissible: false,
        barrierLabel: 'Select screenshot region',
        barrierColor: Colors.transparent,
        transitionDuration: Duration.zero,
        pageBuilder: (dialogContext, animation, secondaryAnimation) =>
            const _CaptureRegionSelector(),
      );

  Future<Uint8List> _cropScreenshotToRegion(
    Uint8List bytes,
    Rect region,
    Size logicalScreenSize,
  ) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final source = frame.image;
    try {
      final scaleX = source.width / math.max(1.0, logicalScreenSize.width);
      final scaleY = source.height / math.max(1.0, logicalScreenSize.height);
      final left = (region.left * scaleX).round().clamp(0, source.width - 1).toInt();
      final top = (region.top * scaleY).round().clamp(0, source.height - 1).toInt();
      final right = (region.right * scaleX).round().clamp(left + 1, source.width).toInt();
      final bottom = (region.bottom * scaleY).round().clamp(top + 1, source.height).toInt();
      final sourceRect = Rect.fromLTRB(
        left.toDouble(), top.toDouble(), right.toDouble(), bottom.toDouble(),
      );
      final width = math.max(1, right - left);
      final height = math.max(1, bottom - top);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        source,
        sourceRect,
        Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        Paint()..filterQuality = FilterQuality.high,
      );
      final picture = recorder.endRecording();
      final cropped = await picture.toImage(width, height);
      picture.dispose();
      try {
        final data = await cropped.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) throw StateError('Could not encode the selected screenshot region.');
        return data.buffer.asUint8List();
      } finally {
        cropped.dispose();
      }
    } finally {
      source.dispose();
      codec.dispose();
    }
  }

  Future<void> _captureScreenToCanvas() async {
    if (_pageData['locked'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unlock this page before inserting a screenshot.')),
      );
      return;
    }
    try {
      Uint8List? bytes;
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        // Select the area first. Android's public MediaProjection API returns
        // a display frame, so Snote crops the chosen region in memory without
        // showing a second post-capture crop screen or writing to the gallery.
        final logicalScreenSize = MediaQuery.sizeOf(context);
        final selectedRegion = await _chooseCaptureRegion();
        if (!mounted || selectedRegion == null) return;
        final fullFrame = await SnoteScreenCapture.captureDisplay();
        if (!mounted || fullFrame == null) return;
        bytes = await _cropScreenshotToRegion(
          fullFrame,
          selectedRegion,
          logicalScreenSize,
        );
        if (!mounted) return;
      } else {
        // iOS/desktop captures the active Snote canvas. iOS does not allow
        // third-party apps to capture another app's screen.
        await WidgetsBinding.instance.endOfFrame;
        final object = _pageCaptureKey.currentContext?.findRenderObject();
        if (object is! RenderRepaintBoundary) {
          throw StateError('The note canvas is not ready for capture.');
        }
        final image = await object.toImage(pixelRatio: 1.25);
        try {
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          bytes = data?.buffer.asUint8List();
        } finally {
          image.dispose();
        }
        if (defaultTargetPlatform == TargetPlatform.iOS && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Captured the Snote canvas. iOS cannot capture another app from inside Snote.')),
          );
        }
      }
      if (bytes == null || bytes.isEmpty) throw StateError('No screenshot image was returned.');
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final sourceAspect = frame.image.width / math.max(1, frame.image.height);
      frame.image.dispose();
      codec.dispose();
      final pageAspect = _pageWidth / math.max(1.0, _pageHeight);
      var widthRatio = .82;
      var heightRatio = widthRatio * pageAspect / math.max(.01, sourceAspect);
      if (heightRatio > .78) {
        heightRatio = .78;
        widthRatio = heightRatio * sourceAspect / math.max(.01, pageAspect);
      }
      await _insertImageBytes(
        bytes,
        name: 'Snote screen capture ${DateTime.now().toIso8601String().replaceAll(':', '-')}.png',
        x: (1 - widthRatio) / 2,
        y: (1 - heightRatio) / 2,
        width: widthRatio,
        height: heightRatio,
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Screenshot inserted into the current page.')),
      );
    } on MissingPluginException {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Screen capture is not available in this build yet.')),
      );
    } on PlatformException catch (error) {
      debugPrint('[Snote][EditorV2] screenshot capture failed: ${error.code} ${error.message}');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not capture the screen: ${error.message ?? error.code}')),
      );
    } catch (error, stackTrace) {
      debugPrint('[Snote][EditorV2] screenshot capture failed: $error\n$stackTrace');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not capture the screen: $error')),
      );
    }
  }

  Future<void> _pasteClipboardImage() async {
    if (_pageData['locked'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unlock this page before inserting an image.')),
      );
      return;
    }
    try {
      final bytes = await Pasteboard.image;
      if (!mounted) return;
      if (bytes == null || bytes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No image found in clipboard. Take a screenshot with your system tool, copy it, then paste here.'),
          ),
        );
        return;
      }
      await _insertImageBytes(
        bytes,
        name: 'Clipboard screenshot ${DateTime.now().toIso8601String().replaceAll(':', '-')}.png',
      );
    } catch (error, stackTrace) {
      debugPrint('[Snote][EditorV2] clipboard screenshot import failed: $error\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not paste clipboard image: $error')),
        );
      }
    }
  }

  Future<void> _insertImageBytes(Uint8List bytes, {required String name, double x = .12, double y = .16, double width = .68, double height = .42}) async {
    if (_pageData['locked'] == true) return;
    if (bytes.isEmpty) throw StateError('The selected image is empty.');
    if (bytes.length > 25 * 1024 * 1024) {
      throw StateError('Images larger than 25 MB are not supported.');
    }
    _pushUndo();
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final image = <String, Object?>{
      'id': id,
      'name': name,
      'data': base64Encode(bytes),
      'x': x,
      'y': y,
      'width': width,
      'height': height,
    };
    final images = _pageData['images'];
    if (images is List<Object?>) {
      images.add(image);
    } else {
      _pageData['images'] = <Object?>[image];
    }
    _imageBytesCache[id] = bytes;
    setState(() {
      // Newly inserted screenshots and photos immediately expose the same
      // lasso move/resize handles as any existing image on the note.
      _selectedStrokeIds.clear();
      _selectedTextBoxIds.clear();
      _selectedImageIds
        ..clear()
        ..add(id);
      _lassoRect = Rect.fromLTWH(
        x * _pageWidth,
        y * _pageHeight,
        width * _pageWidth,
        height * _pageHeight,
      );
    });
    _scheduleSave();
  }

  Future<void> _addSticker() async {
    if (_pageData['locked'] == true) return;
    const stickerCategories = <String, List<String>>{
      'Study': ['✅','❌','⭐','📌','📖','🧠','🎯','💯','📝','✍️','📚','🔖','📎','🖊️','🗒️','📄','🗃️','🏆','💡','📍'],
      'Math': ['➕','➖','✖️','➗','＝','≠','≈','∞','√','∑','∫','π','Δ','θ','α','β','γ','λ','μ','Ω'],
      'Science': ['⚛️','🧪','🔬','🧫','🧬','🧯','🧲','🌡️','🔭','🛰️','🪐','🌌','☄️','🌍','🌑','🌕','🌞','⭐','🌟','💫'],
      'Biology': ['🧬','🦠','🧫','🌱','🌿','🍀','🍃','🌵','🌳','🌲','🌷','🌻','🌼','🌾','🍄','🪴','🧠','🫀','🫁','🦴'],
      'Chemistry': ['⚗️','🧪','🧫','🧬','💧','🔥','🧯','🔬','🧴','🧂','🫧','🧼','🧱','💥','🧲','🪨','🧿','🧊','☢️','☣️'],
      'Physics': ['🧲','🔋','🔌','💡','⚡','🌩️','🪫','🔧','⚙️','🛠️','📐','📏','🧭','🪛','🪜','🛞','🪝','🪂','🎢','🚀'],
      'Planner': ['📅','🗓️','⏰','🕒','⌛','⏳','⏱️','🔔','🔕','📣','📢','📥','📤','📂','📁','🗂️','🗄️','📊','📈','📉'],
      'Nature': ['🌈','☀️','🌤️','⛅','🌦️','🌧️','⛈️','❄️','☃️','🌨️','💨','🌬️','🌪️','🌫️','🌊','💧','🔥','🌋','🏔️','🌅'],
      'Emotions': ['😀','😃','😄','😁','😆','😅','😂','🙂','🙃','😉','😊','😎','🤓','🤔','🧐','😴','🤯','🥳','😭','👍'],
      'Symbols': ['⚠️','⛔','🚫','🚩','❗','❓','⁉️','💢','🔱','☑️','☒','✔️','✖️','➰','➿','🔄','🔁','🔀','⬆️','⬇️'],
      'Celebration': ['🎉','🎊','🎈','🎁','🥇','🥈','🥉','🏅','🏆','🎖️','✨','🌟','💫','🎵','🎶','❤️','🧡','💛','💚','💙'],
      'Food': ['🍎','🍐','🍊','🍋','🍌','🍉','🍇','🍓','🫐','🍒','🍑','🥭','🍍','🥥','🥝','🍅','🥑','🥦','🥕','🌽','🥔','🍠','🥐','🥨','🥯','🍞','🧀','🥚','🍳','🥞','🧇','🥓','🥩','🍗','🍖','🌭','🍔','🍟','🍕','🥪','🌮','🌯','🥗','🍜','🍝','🍣','🍱','🍦','🍰','🍪'],
      'Vehicles': ['🚗','🚕','🚙','🚌','🚎','🏎️','🚓','🚑','🚒','🚐','🛻','🚚','🚛','🚜','🛵','🏍️','🚲','🛴','🚂','🚆','🚄','🚅','🚇','🚈','🚉','✈️','🛫','🛬','🚁','🚀','🛸','🚤','⛵','🛳️','🚢','🛶','🚠','🚡','🚟','🚃'],
      'Travel': ['🗺️','🧳','🎒','🏕️','⛺','🏖️','🏝️','🏜️','🏞️','🗻','🏰','🏯','🏟️','🏛️','🏗️','🗼','🗽','⛲','🌉','🌁','🌃','🌆','🌇','🌄','🌠','🛤️','🛣️','🛑','🧭','📍','🏠','🏡','🏢','🏥','🏫','🏭','🏬','🏪','🏦','🏨'],
      'Objects': ['🔒','🔓','🔑','🗝️','🔨','🪓','⛏️','⚒️','🛠️','🗡️','⚔️','🛡️','🔧','🪛','🔩','⚙️','🗜️','⚖️','🦯','🔗','⛓️','🧰','🧲','🪜','🪚','🪝','🧱','🪵','🪨','🪣','🧹','🧺','🧻','🪒','🧴','🛒','🪞','🪟','🛏️','🪑'],
      'Arrows': ['⬅️','➡️','⬆️','⬇️','↖️','↗️','↘️','↙️','↔️','↕️','↩️','↪️','⤴️','⤵️','🔃','🔄','🔙','🔚','🔛','🔜','🔝','⏫','⏬','◀️','▶️','🔼','🔽','⏪','⏩','⏮️','⏭️','⏯️','⏏️','🔀','🔁','🔂','🔼','🔽','➕','➖'],
      'Music': ['🎼','🎹','🥁','🪘','🎷','🎺','🪗','🎸','🪕','🎻','🪈','🪇','🎤','🎧','🎚️','🎛️','📻','📯','🪩','🎵','🎶','🔊','🔉','🔈','🔇','🔔','🔕','🎙️','💿','📀','📼','🪕','🎸','🎷','🎺','🥁','🎹','🎻','🪘','🎼'],
    };
    var category = 'All';
    var query = '';
    final allCategories = <String>['All', 'Favorites', ...stickerCategories.keys];
    final chosen = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final groups = stickerCategories.entries
              .where((entry) => category == 'All' ||
                  (category != 'Favorites' && entry.key == category))
              .toList();
          final stickers = category == 'Favorites'
              ? _favoriteStickers.where((symbol) =>
                  query.isEmpty || symbol.contains(query)).toList()
              : groups
                  .where((entry) =>
                      query.isEmpty || entry.key.toLowerCase().contains(query))
                  .expand((entry) => entry.value.where(
                        (symbol) =>
                            query.isEmpty ||
                            entry.key.toLowerCase().contains(query) ||
                            symbol.contains(query),
                      ))
                  .toList();
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(14, 2, 14, 14 + MediaQuery.viewInsetsOf(context).bottom),
              child: SizedBox(
                height: MediaQuery.sizeOf(context).height * .68,
                child: Column(
                  children: [
                    Row(children: [
                      Expanded(child: Text(
                        'Sticker library • 200+ stickers • ${_favoriteStickers.length} favorites',
                        style: Theme.of(context).textTheme.titleLarge,
                      )),
                      IconButton(tooltip: 'Close stickers', onPressed: () => Navigator.pop(sheetContext), icon: const Icon(Icons.close_rounded)),
                    ]),
                    TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search_rounded),
                        hintText: 'Search stickers or categories',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) => setSheetState(() => query = value.trim()),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 42,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: allCategories.map((value) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(value, style: const TextStyle(fontSize: 11)),
                            selected: category == value,
                            onSelected: (_) => setSheetState(() => category = value),
                          ),
                        )).toList(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: GridView.builder(
                        itemCount: stickers.length,
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 6,
                          crossAxisSpacing: 5,
                          mainAxisSpacing: 5,
                        ),
                        itemBuilder: (_, index) {
                          final sticker = stickers[index];
                          final isFavorite = _favoriteStickers.contains(sticker);
                          return InkWell(
                            borderRadius: BorderRadius.circular(9),
                            onTap: () => Navigator.pop(sheetContext, sticker),
                            child: Ink(
                              decoration: const BoxDecoration(),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Center(child: Text(sticker, style: const TextStyle(fontSize: 21))),
                                  Positioned(
                                    top: 0,
                                    right: 0,
                                    child: SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: IconButton(
                                        padding: EdgeInsets.zero,
                                        visualDensity: VisualDensity.compact,
                                        tooltip: isFavorite ? 'Remove from favorites' : 'Add to favorites',
                                        onPressed: () {
                                          setSheetState(() {
                                            if (isFavorite) {
                                              _favoriteStickers.remove(sticker);
                                            } else if (!_favoriteStickers.contains(sticker)) {
                                              _favoriteStickers.add(sticker);
                                            }
                                          });
                                          _rootContent['favoriteStickers'] = List<String>.from(_favoriteStickers);
                                          _scheduleSave();
                                        },
                                        icon: Icon(
                                          isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                                          size: 13,
                                          color: isFavorite
                                              ? Theme.of(context).colorScheme.primary
                                              : Theme.of(context).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
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
            ),
          );
        },
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

  Future<void> _showPageFormatSettings() async {
    if (_pageData['locked'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unlock this page before changing its format.')),
      );
      return;
    }

    const presets = <String, Size>{
      'A0': Size(3264, 4620),
      'A1': Size(2304, 3264),
      'A2': Size(1632, 2304),
      'A3': Size(1152, 1632),
      'A4': Size(816, 1152),
      'A5': Size(576, 816),
      'A6': Size(408, 576),
      'B0': Size(3264, 4615),
      'B1': Size(2306, 3264),
      'B2': Size(1632, 2306),
      'B3': Size(1152, 1632),
      'B4': Size(960, 1358),
      'B5': Size(680, 960),
      'B6': Size(408, 574),
      'Letter': Size(816, 1056),
      'Legal': Size(816, 1344),
      'Tabloid': Size(1056, 1632),
      'Custom': Size(816, 1152),
    };
    final widthController = TextEditingController(text: _pageWidth.toStringAsFixed(0));
    final heightController = TextEditingController(text: _pageHeight.toStringAsFixed(0));
    final currentSize = _pageData['pageSize']?.toString() ?? 'A4';
    var selectedSize = presets.containsKey(currentSize) ? currentSize : 'Custom';
    var landscape = _pageData['orientation']?.toString() == 'horizontal';
    var spacing = ((_pageData['spacing'] as num?)?.toDouble() ?? 28.0)
        .clamp(10.0, 80.0).toDouble();
    var paperColor = Color(
      (_pageData['paperColor'] as num?)?.toInt() ?? 0xffffffff,
    );

    void applyPreset(String value) {
      selectedSize = value;
      if (value == 'Custom') return;
      final portrait = presets[value]!;
      final size = landscape ? Size(portrait.height, portrait.width) : portrait;
      widthController.text = size.width.toStringAsFixed(0);
      heightController.text = size.height.toStringAsFixed(0);
    }

    final result = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          void changeOrientation(bool value) {
            if (landscape == value) return;
            setDialogState(() {
              landscape = value;
              if (selectedSize == 'Custom') {
                final oldWidth = widthController.text;
                widthController.text = heightController.text;
                heightController.text = oldWidth;
              } else {
                applyPreset(selectedSize);
              }
            });
          }

          return AlertDialog(
            title: const Text('Page format & paper'),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: selectedSize,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Paper preset',
                        prefixIcon: Icon(Icons.description_outlined),
                      ),
                      items: presets.keys.map((name) => DropdownMenuItem(
                        value: name,
                        child: Text(name == 'Custom' ? 'Custom dimensions' : name),
                      )).toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => applyPreset(value));
                      },
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Portrait'),
                          selected: !landscape,
                          onSelected: (value) { if (value) changeOrientation(false); },
                        ),
                        ChoiceChip(
                          label: const Text('Landscape'),
                          selected: landscape,
                          onSelected: (value) { if (value) changeOrientation(true); },
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: widthController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Page width',
                              suffixText: 'units',
                              isDense: true,
                            ),
                            onChanged: (_) => setDialogState(() => selectedSize = 'Custom'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: heightController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Page height',
                              suffixText: 'units',
                              isDense: true,
                            ),
                            onChanged: (_) => setDialogState(() => selectedSize = 'Custom'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text('Line spacing • ${spacing.round()} units',
                      style: Theme.of(context).textTheme.labelLarge),
                    Slider(
                      value: spacing,
                      min: 10,
                      max: 80,
                      divisions: 14,
                      label: spacing.round().toString(),
                      onChanged: (value) => setDialogState(() => spacing = value),
                    ),
                    const SizedBox(height: 4),
                    Text('Paper background', style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ..._palette.map((color) => InkWell(
                          onTap: () => setDialogState(() => paperColor = color),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            width: 25,
                            height: 25,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: color.toARGB32() == paperColor.toARGB32()
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).colorScheme.outlineVariant,
                                width: color.toARGB32() == paperColor.toARGB32() ? 3 : 1,
                              ),
                            ),
                          ),
                        )),
                        ActionChip(
                          avatar: const Icon(Icons.colorize_rounded, size: 16),
                          label: const Text('Custom…'),
                          onPressed: () async {
                            final candidate = await _pickCustomColor(initial: paperColor, title: 'Custom paper background');
                            if (candidate != null) setDialogState(() => paperColor = candidate);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: () {
                  final width = double.tryParse(widthController.text);
                  final height = double.tryParse(heightController.text);
                  if (width == null || height == null ||
                      !width.isFinite || !height.isFinite ||
                      width < 360 || width > 5000 ||
                      height < 360 || height > 5000) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Page dimensions must be between 360 and 5000 units.')),
                    );
                    return;
                  }
                  Navigator.pop(dialogContext, <String, Object?>{
                    'pageSize': selectedSize,
                    'pageWidth': width,
                    'pageHeight': height,
                    'orientation': landscape ? 'horizontal' : 'vertical',
                    'spacing': spacing,
                    'paperColor': paperColor.toARGB32(),
                  });
                },
                icon: const Icon(Icons.check_rounded),
                label: const Text('Apply'),
              ),
            ],
          );
        },
      ),
    );
    widthController.dispose();
    heightController.dispose();
    if (result == null || !mounted) return;

    final width = (result['pageWidth'] as num).toDouble();
    final height = (result['pageHeight'] as num).toDouble();
    _pushUndo();
    setState(() {
      _pageData['pageSize'] = result['pageSize'];
      _pageData['pageWidth'] = width;
      _pageData['pageHeight'] = height;
      _pageData['pageAspectRatio'] = math.min(width, height) / math.max(width, height);
      _pageData['orientation'] = result['orientation'];
      _pageData['spacing'] = result['spacing'];
      _pageData['paperColor'] = result['paperColor'];
    });
    _scheduleSave();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _resetCanvasView();
    });
  }

  Widget _smartPagePreview(SmartPageTemplate template) {
    final accent = Theme.of(context).colorScheme.primary;
    final paper = Theme.of(context).colorScheme.surface;
    return Container(
      height: 42,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: paper,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .7)),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (template.pageTemplate == 'cornell')
            Container(width: 22, margin: const EdgeInsets.only(right: 4), decoration: BoxDecoration(
              color: accent.withValues(alpha: .12),
              border: Border(right: BorderSide(color: accent.withValues(alpha: .45))),
            )),
          Expanded(
            child: template.pageTemplate == 'grid'
                ? Column(children: List.generate(2, (_) => Expanded(child: Row(children: List.generate(7, (_) => Expanded(child: Container(
                    margin: const EdgeInsets.all(.5),
                    decoration: BoxDecoration(border: Border.all(color: accent.withValues(alpha: .25))),
                  )))))))
                : Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(3, (index) => Row(children: [
                      if (template.pageTemplate == 'checklist')
                        Container(width: 6, height: 6, margin: const EdgeInsets.only(right: 4), decoration: BoxDecoration(
                          border: Border.all(color: accent.withValues(alpha: .8)),
                          borderRadius: BorderRadius.circular(1),
                        )),
                      Expanded(child: Container(height: 2, color: accent.withValues(alpha: index == 0 ? .45 : .2))),
                    ])),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _showSmartPagesLibrary() async {
    final templates = SmartPagesCatalog.all;
    var category = 'All';
    var query = '';
    var favoritesOnly = false;
    Set<String> favorites = <String>{};
    try {
      final saved = jsonDecode(_settings.getString('editorV2SmartPageFavorites'));
      if (saved is List) favorites = saved.whereType<String>().toSet();
    } catch (_) {
      // Ignore malformed favorites without hiding the template library.
    }
    final categories = <String>['All'];
    categories.addAll(templates.map((template) => template.category).toSet().toList()..sort());
    final selected = await showModalBottomSheet<SmartPageTemplate>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final filtered = templates.where((template) {
            final matchesCategory = category == 'All' || template.category == category;
            final matchesFavorite = !favoritesOnly || favorites.contains(template.id);
            final term = query.toLowerCase();
            final matchesQuery = term.isEmpty ||
                template.title.toLowerCase().contains(term) ||
                template.category.toLowerCase().contains(term);
            return matchesCategory && matchesFavorite && matchesQuery;
          }).toList(growable: false);
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .82,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: Column(
                  children: [
                    Row(children: [
                      Expanded(child: Text('Smart Pages • ${templates.length} templates', style: Theme.of(context).textTheme.titleLarge)),
                      IconButton(
                        tooltip: favoritesOnly ? 'Show all templates' : 'Show favorites',
                        onPressed: () => setSheetState(() => favoritesOnly = !favoritesOnly),
                        icon: Icon(favoritesOnly ? Icons.star_rounded : Icons.star_border_rounded),
                      ),
                    ]),
                    TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search_rounded),
                        hintText: 'Search calendars, planners, routines…',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) => setSheetState(() => query = value.trim()),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 40,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: categories.map((value) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(value),
                            selected: category == value,
                            onSelected: (_) => setSheetState(() => category = value),
                          ),
                        )).toList(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(child: Text('No templates match this filter.'))
                          : GridView.builder(
                              itemCount: filtered.length,
                              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 230,
                                mainAxisSpacing: 8,
                                crossAxisSpacing: 8,
                                childAspectRatio: 1.48,
                              ),
                              itemBuilder: (_, index) {
                                final template = filtered[index];
                                final favorite = favorites.contains(template.id);
                                return Card(
                                  clipBehavior: Clip.antiAlias,
                                  child: InkWell(
                                    onTap: () => Navigator.pop(sheetContext, template),
                                    child: Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(children: [
                                            Expanded(child: Text(template.category, maxLines: 1, overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context).textTheme.labelSmall)),
                                            IconButton(
                                              visualDensity: VisualDensity.compact,
                                              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                                              padding: EdgeInsets.zero,
                                              tooltip: favorite ? 'Remove favorite' : 'Add favorite',
                                              onPressed: () async {
                                                setSheetState(() {
                                                  if (favorite) {
                                                    favorites.remove(template.id);
                                                  } else {
                                                    favorites.add(template.id);
                                                  }
                                                });
                                                await _settings.setString('editorV2SmartPageFavorites', jsonEncode(favorites.toList()));
                                              },
                                              icon: Icon(favorite ? Icons.star_rounded : Icons.star_border_rounded, size: 18),
                                            ),
                                          ]),
                                          Text(template.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                                          const SizedBox(height: 4),
                                          _smartPagePreview(template),
                                          const SizedBox(height: 3),
                                          Text(template.body.replaceAll('\n', ' • '), maxLines: 1, overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context).textTheme.bodySmall),
                                        ],
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
            ),
          );
        },
      ),
    );
    if (selected == null || !mounted) return;
    if (_pageData['locked'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unlock this page before inserting a Smart Page.')),
      );
      return;
    }
    _pushUndo();
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final titleBoxId = '$id-smart-title';
    final bodyBoxId = '$id-smart-body';
    final nextPage = EditorV2DocumentCodec.normalizePage(<String, Object?>{
      ...Map<String, Object?>.from(_pageData),
      'id': '$id-smart-page',
      'template': selected.pageTemplate,
      'strokes': <Object?>[],
      'images': <Object?>[],
      'textBoxes': <Object?>[
        <String, Object?>{
          'id': titleBoxId, 'x': .06, 'y': .035, 'width': .88, 'height': .075,
          'text': selected.title, 'fontSize': 30.0, 'bold': true,
          'color': 0xff17202a, 'textAlign': 'left',
        },
        <String, Object?>{
          'id': bodyBoxId, 'x': .06, 'y': .13, 'width': .88, 'height': .82,
          'text': selected.body, 'fontSize': 17.0,
          'color': 0xff263238, 'textAlign': 'left',
        },
      ],
      'backgroundImage': null,
      'pdfLazyRender': false,
      'smartPageTemplateId': selected.id,
    });
    _textControllers[titleBoxId] = TextEditingController(text: selected.title);
    _textControllers[bodyBoxId] = TextEditingController(text: selected.body);
    setState(() {
      _pages.insert((_page + 1).clamp(0, _pages.length).toInt(), nextPage);
      _page = (_page + 1).clamp(0, _pages.length - 1).toInt();
      _clearSelectionIds();
      _lassoRect = null;
    });
    _scheduleSave();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _resetCanvasView();
    });
  }

  Future<void> _chooseTemplate() async {
    if (_pageData['locked'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unlock this page before changing its template.')),
      );
      return;
    }
    final selected = await showModalBottomSheet<PageTemplate>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: GridView.builder(
            shrinkWrap: true,
            itemCount: PageTemplate.values.length + 1,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.1,
            ),
            itemBuilder: (_, index) {
              if (index == 0) {
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) unawaited(_showSmartPagesLibrary());
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.auto_awesome_rounded, size: 30, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(height: 8),
                          const Text('Smart Pages', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w900)),
                          const SizedBox(height: 4),
                          Text('Planners, study notes and trackers', textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelSmall),
                        ],
                      ),
                    ),
                  ),
                );
              }
              final template = PageTemplate.values[index - 1];
              final isSelected = template.name == _pageData['template']?.toString();
              return InkWell(
                onTap: () => Navigator.pop(sheetContext, template),
                borderRadius: BorderRadius.circular(12),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: isSelected ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: .35) : Theme.of(context).colorScheme.surface,
                    border: Border.all(
                      color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant,
                      width: isSelected ? 2 : 1,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
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
                      ),
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(child: Text(template.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: isSelected ? FontWeight.w900 : FontWeight.w500))),
                            if (isSelected) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.check_circle_rounded, size: 14)),
                          ],
                        ),
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

  void _addPage({int? insertAfter, Map<String, Object?>? templateFrom}) {
    _pushUndo();
    final previous = templateFrom ?? _pageData;
    final page = EditorV2DocumentCodec.normalizePage(<String, Object?>{
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'template': previous['template'] ?? 'dotted',
      'paperColor': previous['paperColor'] ?? 0xffffffff,
      'lineColor': previous['lineColor'] ?? 0xffd8dee8,
      'lineOpacity': previous['lineOpacity'] ?? .85,
      'spacing': previous['spacing'] ?? 28.0,
      'lineWidth': previous['lineWidth'] ?? .7,
      'pageSize': previous['pageSize'] ?? 'A4',
      'pageWidth': previous['pageWidth'],
      'pageHeight': previous['pageHeight'],
      'pageAspectRatio': previous['pageAspectRatio'],
      'orientation': previous['orientation'] ?? 'vertical',
      'strokes': <Object?>[],
      'images': <Object?>[],
      'textBoxes': <Object?>[],
    });
    setState(() {
      final insertion = ((insertAfter ?? _page) + 1).clamp(0, _pages.length).toInt();
      _pages.insert(insertion, page);
      _page = insertion;
      _clearSelectionIds();
      _lassoRect = null;
    });
    _scheduleSave();
  }

  Future<Uint8List> _rasterizeSvg(Uint8List sourceBytes) async {
    final source = utf8.decode(sourceBytes, allowMalformed: false);
    final pictureInfo = await vg.vg.loadPicture(vg.SvgStringLoader(source), null);
    try {
      final logicalSize = pictureInfo.size;
      if (!logicalSize.width.isFinite ||
          !logicalSize.height.isFinite ||
          logicalSize.width <= 0 ||
          logicalSize.height <= 0) {
        throw const FormatException('The SVG has no valid intrinsic dimensions.');
      }
      const maxDimension = 2400.0;
      final scale = math.min(
        maxDimension / logicalSize.width,
        maxDimension / logicalSize.height,
      ).clamp(.1, 3.0).toDouble();
      final width = (logicalSize.width * scale).ceil().clamp(1, 2400).toInt();
      final height = (logicalSize.height * scale).ceil().clamp(1, 2400).toInt();
      final image = await pictureInfo.picture.toImage(width, height);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) throw StateError('SVG rasterization returned no image data.');
        return data.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } finally {
      pictureInfo.picture.dispose();
    }
  }

  String _decodeXmlText(String value) {
    return value
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAllMapped(
          RegExp(r'&#(x[0-9a-fA-F]+|[0-9]+);'),
          (match) {
            final token = match.group(1)!;
            final codePoint = token.startsWith('x')
                ? int.tryParse(token.substring(1), radix: 16)
                : int.tryParse(token);
            return codePoint == null ? '' : String.fromCharCode(codePoint);
          },
        );
  }

  String _xmlTextNodes(String xml) => RegExp(
        r'<(?:[A-Za-z0-9_]+:)?t\b[^>]*>(.*?)</(?:[A-Za-z0-9_]+:)?t>',
        dotAll: true,
      ).allMatches(xml).map((match) => _decodeXmlText(match.group(1) ?? '')).join('');

  int _xmlFileIndex(String path) {
    final match = RegExp(r'(\d+)\.xml$').firstMatch(path);
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }

  Map<String, String> _unzipTextXmlFiles(Uint8List bytes) {
    final archive = zip.ZipDecoder().decodeBytes(bytes);
    final result = <String, String>{};
    for (final entry in archive.files) {
      if (!entry.isFile || !entry.name.toLowerCase().endsWith('.xml')) continue;
      final content = entry.content;
      if (content is List<int>) {
        result[entry.name] = utf8.decode(content, allowMalformed: true);
      }
    }
    return result;
  }

  List<String> _powerPointSlideTexts(Uint8List bytes) {
    final files = _unzipTextXmlFiles(bytes);
    final paths = files.keys
        .where((path) => RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(path))
        .toList()
      ..sort((a, b) => _xmlFileIndex(a).compareTo(_xmlFileIndex(b)));
    return paths.map((path) {
      final xml = files[path] ?? '';
      return RegExp(
        r'<(?:[A-Za-z0-9_]+:)?t\b[^>]*>(.*?)</(?:[A-Za-z0-9_]+:)?t>',
        dotAll: true,
      ).allMatches(xml)
          .map((match) => _decodeXmlText(match.group(1) ?? ''))
          .where((value) => value.trim().isNotEmpty)
          .join('\n');
    }).where((text) => text.trim().isNotEmpty).toList();
  }

  List<String> _excelSheetTexts(Uint8List bytes) {
    final files = _unzipTextXmlFiles(bytes);
    final sharedStrings = <String>[];
    final sharedXml = files['xl/sharedStrings.xml'];
    if (sharedXml != null) {
      for (final item in RegExp(r'<si\b[^>]*>(.*?)</si>', dotAll: true).allMatches(sharedXml)) {
        sharedStrings.add(_xmlTextNodes(item.group(1) ?? ''));
      }
    }

    final sheets = files.keys
        .where((path) => RegExp(r'^xl/worksheets/sheet\d+\.xml$').hasMatch(path))
        .toList()
      ..sort((a, b) => _xmlFileIndex(a).compareTo(_xmlFileIndex(b)));
    final output = <String>[];
    for (final path in sheets) {
      final xml = files[path] ?? '';
      final rows = <String>[];
      for (final rowMatch in RegExp(r'<row\b[^>]*>(.*?)</row>', dotAll: true).allMatches(xml)) {
        final rowXml = rowMatch.group(1) ?? '';
        final values = <int, String>{};
        for (final cellMatch in RegExp(r'<c\b([^>]*)>(.*?)</c>', dotAll: true).allMatches(rowXml)) {
          final attributes = cellMatch.group(1) ?? '';
          final body = cellMatch.group(2) ?? '';
          final ref = RegExp(r'\br="([A-Z]+)\d+"').firstMatch(attributes)?.group(1);
          if (ref == null) continue;
          var column = 0;
          for (final code in ref.codeUnits) {
            column = column * 26 + code - 64;
          }
          column--;
          final type = RegExp(r'\bt="([^"]+)"').firstMatch(attributes)?.group(1);
          String value;
          if (type == 's') {
            final index = int.tryParse(RegExp(r'<v>(.*?)</v>', dotAll: true).firstMatch(body)?.group(1) ?? '');
            value = index != null && index >= 0 && index < sharedStrings.length
                ? sharedStrings[index]
                : '';
          } else if (type == 'inlineStr') {
            value = _xmlTextNodes(body);
          } else {
            value = _decodeXmlText(
              RegExp(r'<v>(.*?)</v>', dotAll: true).firstMatch(body)?.group(1) ?? '',
            );
          }
          values[column] = value;
        }
        if (values.isEmpty) continue;
        final maxColumn = values.keys.reduce((left, right) => left > right ? left : right);
        rows.add(List<String>.generate(
          maxColumn + 1,
          (index) => values[index] ?? '',
        ).join('\t'));
      }
      if (rows.isNotEmpty) output.addAll(_chunkLines(rows, 32));
    }
    return output;
  }

  List<String> _chunkLines(List<String> lines, int linesPerPage) {
    final chunks = <String>[];
    for (var offset = 0; offset < lines.length; offset += linesPerPage) {
      chunks.add(lines.skip(offset).take(linesPerPage).join('\n'));
    }
    return chunks;
  }

  Future<void> _insertImportedTextPages(
    List<String> pageTexts, {
    required String sourceName,
  }) async {
    final nonEmpty = pageTexts.where((text) => text.trim().isNotEmpty).toList();
    if (nonEmpty.isEmpty) {
      throw StateError('No readable text was found in "$sourceName".');
    }
    if (nonEmpty.length > 500) {
      throw StateError('This import contains more than 500 text pages; split the file and import smaller sections.');
    }
    _pushUndo();
    final previous = _pageData;
    final baseId = DateTime.now().microsecondsSinceEpoch.toString();
    final inserted = <Map<String, Object?>>[];
    for (var index = 0; index < nonEmpty.length; index++) {
      final boxId = '$baseId-import-text-$index';
      inserted.add(EditorV2DocumentCodec.normalizePage(<String, Object?>{
        'id': '$baseId-import-page-$index',
        'template': PageTemplate.blank.name,
        'paperColor': previous['paperColor'] ?? 0xffffffff,
        'lineColor': previous['lineColor'] ?? 0xffd8dee8,
        'lineOpacity': previous['lineOpacity'] ?? .85,
        'spacing': previous['spacing'] ?? 28.0,
        'lineWidth': previous['lineWidth'] ?? .7,
        'pageSize': previous['pageSize'] ?? 'A4',
        'pageWidth': _pageWidth,
        'pageHeight': _pageHeight,
        'pageAspectRatio': _pageAspectRatioFor(previous),
        'orientation': previous['orientation'] ?? 'vertical',
        'strokes': <Object?>[],
        'images': <Object?>[],
        'textBoxes': <Object?>[
          <String, Object?>{
            'id': boxId,
            'x': .045,
            'y': .045,
            'width': .91,
            'height': .91,
            'text': nonEmpty[index],
            'fontSize': 15.0,
            'color': 0xff17202a,
            'sticker': false,
          },
        ],
        'importedSource': sourceName,
        'importedPageNumber': index + 1,
      }));
    }
    setState(() {
      final insertAt = (_page + 1).clamp(0, _pages.length).toInt();
      _pages.insertAll(insertAt, inserted);
      _page = insertAt;
      _clearSelectionIds();
      _lassoRect = null;
    });
    _initializeTextControllers();
    _scheduleSave();
  }

  Future<void> _importOtherFormats() async {
    if (_pageData['locked'] == true) return;
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const <String>[
          'svg', 'png', 'jpg', 'jpeg', 'webp', 'csv', 'ppt', 'pptx',
          'xls', 'xlsx', 'excel', 'nebo',
        ],
      );
      if (file == null) return;
      final sourceBytes = await file.readAsBytes();
      if (sourceBytes.isEmpty) throw StateError('The selected file is empty.');
      if (sourceBytes.length > 80 * 1024 * 1024) {
        throw StateError('Files over 80 MB cannot be imported into the canvas.');
      }
      final extension = file.name.split('.').last.toLowerCase();
      await _documents.saveBytes(
        noteId: widget.note.id,
        name: file.name,
        type: extension,
        bytes: sourceBytes,
        metadata: <String, dynamic>{
          'source': 'editor-v2-format-import',
          'importedAt': DateTime.now().toIso8601String(),
        },
      );

      if (const <String>{'png', 'jpg', 'jpeg', 'webp'}.contains(extension)) {
        await _insertImageBytes(sourceBytes, name: file.name);
      } else if (extension == 'svg') {
        await _insertImageBytes(await _rasterizeSvg(sourceBytes), name: file.name);
      } else if (extension == 'csv') {
        final csvText = utf8.decode(sourceBytes, allowMalformed: true);
        final lines = csvText.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
        await _insertImportedTextPages(_chunkLines(lines, 32), sourceName: file.name);
      } else if (extension == 'pptx') {
        await _insertImportedTextPages(_powerPointSlideTexts(sourceBytes), sourceName: file.name);
      } else if (extension == 'xlsx' || extension == 'excel') {
        await _insertImportedTextPages(_excelSheetTexts(sourceBytes), sourceName: file.name);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Saved file to note attachments. This file variant is preserved, but editable canvas conversion is not available yet: ' + file.name),
            duration: const Duration(seconds: 5),
          ));
        }
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Imported file to the canvas. Original file preserved in note attachments: ' + file.name),
        ));
      }
    } catch (error, stackTrace) {
      debugPrint('[Snote][EditorV2] format import failed: $error\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not import this file: $error')),
        );
      }
    }
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
      final asset = await _documents.saveBytes(
        noteId: widget.note.id,
        name: file.name,
        type: 'pdf',
        bytes: sourceBytes,
        metadata: <String, dynamic>{
          'source': 'editor-v2-import',
          'sha256': sha256.convert(sourceBytes).toString(),
        },
      );
      _pdfSourceAssets[asset.id] = asset;
      _pdfSourceBytesCache[asset.id] = sourceBytes;
      final result = await _renderPdfPages(sourceBytes, file.name, sourceAssetId: asset.id);
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


  Future<void> _showPageSearch() async {
    final controller = TextEditingController();
    var query = '';
    final chosen = await showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final q = query.trim().toLowerCase();
          final indexes = List<int>.generate(_pages.length, (index) => index).where((index) {
            if (q.isEmpty) return true;
            final page = _pages[index];
            final template = page['template']?.toString() ?? '';
            final name = page['pdfSourceName']?.toString() ?? '';
            final text = page['textBoxes'] is List
                ? (page['textBoxes'] as List).whereType<Map>().map((box) => box['text']?.toString() ?? '').join(' ')
                : '';
            return '${index + 1}'.contains(q) || template.toLowerCase().contains(q) ||
                name.toLowerCase().contains(q) || text.toLowerCase().contains(q);
          }).toList();
          return AlertDialog(
            title: const Text('Search / jump to page'),
            content: SizedBox(
              width: 420,
              height: 430,
              child: Column(children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText: 'Page number, text, or PDF name',
                    isDense: true,
                  ),
                  onChanged: (value) => setDialogState(() => query = value),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: indexes.isEmpty
                      ? const Center(child: Text('No matching pages'))
                      : ListView.builder(
                          itemCount: indexes.length,
                          itemBuilder: (_, itemIndex) {
                            final index = indexes[itemIndex];
                            final page = _pages[index];
                            return ListTile(
                              dense: true,
                              selected: index == _page,
                              leading: CircleAvatar(
                                radius: 14,
                                child: Text('${index + 1}', style: const TextStyle(fontSize: 10)),
                              ),
                              title: Text('Page ${index + 1}'),
                              subtitle: Text(
                                page['pdfSourceName']?.toString() ?? page['template']?.toString() ?? 'Notebook page',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => Navigator.pop(dialogContext, index),
                            );
                          },
                        ),
                ),
              ]),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel'))],
          );
        },
      ),
    );
    controller.dispose();
    if (chosen != null && mounted) _goToPage(chosen);
  }

  Future<void> _insertBlankPageAfter(int index) async {
    if (index < 0 || index >= _pages.length) return;
    final targetId = _pages[index]['id']?.toString();
    final target = _pages[index];
    final sourceId = target['pdfSourceAssetId']?.toString();
    final sourcePage = (target['pdfSourcePage'] as num?)?.toInt();

    // Lazy PDF records cannot assume A4/portrait. Read the selected page's
    // bounds directly, preserving mixed page sizes without rasterizing it.
    if (target['pdfLazyRender'] == true &&
        sourceId != null &&
        sourceId.isNotEmpty &&
        sourcePage != null) {
      try {
        final document = await _pdfDocumentForSource(sourceId);
        final pdfPage = await document.getPage(sourcePage);
        try {
          final pointWidth = pdfPage.width;
          final pointHeight = pdfPage.height;
          if (pointWidth.isFinite &&
              pointHeight.isFinite &&
              pointWidth > 0 &&
              pointHeight > 0) {
            final liveTarget = _pages.indexWhere(
              (page) => page['id']?.toString() == targetId,
            );
            if (liveTarget >= 0) {
              final page = _pages[liveTarget];
              // Convert PDF points to approximately 96-DPI canvas units.
              // A1/A3 and landscape pages therefore retain their real size ratio.
              page['pageWidth'] = (pointWidth * 4 / 3).clamp(360.0, 5000.0);
              page['pageHeight'] = (pointHeight * 4 / 3).clamp(360.0, 5000.0);
              page['pageAspectRatio'] = pointWidth / pointHeight;
              page['orientation'] =
                  pointWidth > pointHeight ? 'horizontal' : 'vertical';
              page['pageSize'] = 'Custom';
            }
          }
        } finally {
          await pdfPage.close();
        }
      } catch (error, stackTrace) {
        debugPrint(
          '[Snote][EditorV2] target PDF page dimensions failed: $error\n$stackTrace',
        );
      }
    }

    if (!mounted) return;
    final currentIndex = _pages.indexWhere(
      (page) => page['id']?.toString() == targetId,
    );
    if (currentIndex >= 0) {
      _addPage(
        insertAfter: currentIndex,
        templateFrom: _pages[currentIndex],
      );
    }
  }

  Future<Color?> _pickCustomColor({
    required Color initial,
    required String title,
  }) async {
    final controller = TextEditingController(
      text: '#${initial.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
    );
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Hex color',
            hintText: '#FFCC88 or #AARRGGBB',
            helperText: 'Use #RRGGBB or #AARRGGBB',
          ),
          onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            icon: const Icon(Icons.colorize_rounded),
            label: const Text('Use color'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return null;
    final hex = value.trim().replaceFirst('#', '');
    try {
      if (hex.length == 6 || hex.length == 8) {
        final parsed = int.parse(hex, radix: 16);
        return Color(hex.length == 6 ? (0xff000000 | parsed) : parsed);
      }
    } on FormatException {
      // Report invalid input without changing the page's current color.
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid color such as #FFCC88 or #AARRGGBB.')),
      );
    }
    return null;
  }

  Future<void> _choosePageBackground(int index) async {
    if (index < 0 || index >= _pages.length) return;
    final page = _pages[index];
    if (page['locked'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unlock this page before changing its background.')),
      );
      return;
    }
    final current = Color((page['paperColor'] as num?)?.toInt() ?? 0xffffffff);
    final chosen = await showDialog<Color>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Page ${index + 1} background'),
        content: Wrap(
          spacing: 9,
          runSpacing: 9,
          children: [
            ActionChip(
              avatar: const Icon(Icons.colorize_rounded, size: 17),
              label: const Text('Custom…'),
              onPressed: () async {
                final selectedColor = await _pickCustomColor(initial: current, title: 'Custom page background');
                if (selectedColor != null && dialogContext.mounted) Navigator.pop(dialogContext, selectedColor);
              },
            ),
            ..._palette.map((color) => InkWell(
            onTap: () => Navigator.pop(dialogContext, color),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: color.toARGB32() == current.toARGB32()
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outlineVariant,
                  width: color.toARGB32() == current.toARGB32() ? 3 : 1,
                ),
              ),
            ),
          )).toList(),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    _pushUndo();
    setState(() => page['paperColor'] = chosen.toARGB32());
    _scheduleSave();
  }

  void _copyPage(int index) {
    if (index < 0 || index >= _pages.length) return;
    _pageClipboard = EditorV2DocumentCodec.clonePages(<Map<String, Object?>>[_pages[index]]).single;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Page copied. Use Paste as page to insert it.')));
  }

  void _cutPage(int index) {
    if (index < 0 || index >= _pages.length) return;
    if (_pages[index]['locked'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unlock this page before cutting it.')),
      );
      return;
    }
    _copyPage(index);
    _deletePage(index);
  }

  void _pastePage({int? insertAfter}) {
    final source = _pageClipboard;
    if (source == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copy a page first.')));
      return;
    }
    _pushUndo();
    final copy = EditorV2DocumentCodec.clonePages(<Map<String, Object?>>[source]).single;
    copy['id'] = DateTime.now().microsecondsSinceEpoch.toString();
    setState(() {
      final insertion = ((insertAfter ?? _page) + 1).clamp(0, _pages.length).toInt();
      _pages.insert(insertion, EditorV2DocumentCodec.normalizePage(copy));
      _page = insertion;
    });
    _scheduleSave();
  }

  void _duplicatePage(int index) {
    if (index < 0 || index >= _pages.length) return;
    _pageClipboard = EditorV2DocumentCodec.clonePages(<Map<String, Object?>>[_pages[index]]).single;
    _pastePage(insertAfter: index);
  }

  Future<void> _confirmDeletePage(int index) async {
    if (index < 0 || index >= _pages.length) return;
    if (_pages[index]['locked'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unlock this page before deleting it.')));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete page?'),
        content: Text('Delete page ${index + 1}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(dialogContext).colorScheme.error),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) _deletePage(index);
  }

  Future<void> _clearPageWithConfirmation(int index) async {
    if (index < 0 || index >= _pages.length) return;
    final page = _pages[index];
    if (page['locked'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unlock this page before clearing it.')));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear page content?'),
        content: const Text('Remove all handwriting, images and text? The paper template will remain.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(dialogContext).colorScheme.error),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Clear page'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _pushUndo();
    final rawBoxes = page['textBoxes'];
    if (rawBoxes is List) {
      for (final item in rawBoxes.whereType<Map>()) {
        final id = item['id']?.toString();
        if (id != null) _textControllers.remove(id)?.dispose();
      }
    }
    page['strokes'] = <Object?>[];
    page['images'] = <Object?>[];
    page['textBoxes'] = <Object?>[];
    setState(() {
      if (index == _page) _clearSelectionIds();
      _lassoRect = null;
    });
    _scheduleSave();
  }

  Future<void> _sharePage(int index) async {
    if (index < 0 || index >= _pages.length) return;
    if (_pages[index]['locked'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unlock this page before sharing it.')));
      return;
    }
    final originalPage = _page;
    try {
      await _flushSave();
      if (!mounted) return;
      setState(() => _page = index);
      await WidgetsBinding.instance.endOfFrame;
      final object = _pageCaptureKey.currentContext?.findRenderObject();
      if (object is! RenderRepaintBoundary) throw StateError('Page ${index + 1} is not ready to share.');
      final image = await object.toImage(pixelRatio: 1.5);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) throw StateError('Could not capture page ${index + 1}.');
        final bytes = data.buffer.asUint8List();
        final filename = '${_safeFilename(_title.text)}-page-${index + 1}.png';
        if (kIsWeb) {
          await FilePicker.saveFile(fileName: filename, bytes: bytes, mimeType: 'image/png');
        } else {
          await SharePlus.instance.share(ShareParams(
            title: '${_title.text} — Page ${index + 1}',
            files: <XFile>[XFile.fromData(bytes, mimeType: 'image/png', name: filename)],
          ));
        }
      } finally {
        image.dispose();
      }
    } catch (error, stackTrace) {
      debugPrint('[Snote][EditorV2] page share failed: $error\n$stackTrace');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not share page: $error')));
    } finally {
      if (mounted) setState(() => _page = EditorV2DocumentCodec.clampPage(originalPage, _pages.length));
    }
  }

  void _deletePage(int index) {
    if (index < 0 || index >= _pages.length) return;
    if (_pages[index]['locked'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unlock this page before deleting it.')),
      );
      return;
    }
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
      _clearSelectionIds();
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

  void _warmAdjacentPdfPages(int pageIndex) {
    // Render only the neighboring PDF pages after the active page is visible.
    // Current-page rendering stays demand-driven so navigation is not blocked.
    for (final index in <int>[pageIndex - 1, pageIndex + 1]) {
      if (index < 0 || index >= _pages.length) continue;
      final record = _pages[index];
      if (record['pdfLazyRender'] != true) continue;
      final assetId = record['pdfSourceAssetId']?.toString();
      final sourcePage = (record['pdfSourcePage'] as num?)?.toInt();
      if (assetId == null || assetId.isEmpty || sourcePage == null) continue;
      unawaited(_lazyPdfPageRaster(assetId, sourcePage).catchError((Object error) {
        debugPrint('[Snote][PDF] adjacent-page prefetch failed: $error');
        return null;
      }));
    }
  }

  void _goToPage(int index) {
    if (index < 0 || index >= _pages.length || index == _page) return;
    setState(() {
      _page = index;
      _clearSelectionIds();
      _lassoRect = null;
    });
    _scheduleSave();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _page == index) _warmAdjacentPdfPages(index);
    });
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
        final pageRecord = _pages[index];
        if (pageRecord['pdfLazyRender'] == true) {
          final assetId = pageRecord['pdfSourceAssetId']?.toString();
          final sourcePage = (pageRecord['pdfSourcePage'] as num?)?.toInt();
          if (assetId == null || sourcePage == null ||
              await _lazyPdfPageRaster(assetId, sourcePage) == null) {
            throw StateError('Could not prepare PDF page ${index + 1} for export.');
          }
        }
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

  Future<void> _collectToolToPencase({
    required CanvasTool tool,
    required Color color,
    required double size,
    required double opacity,
    required double pressure,
    required double velocity,
    required PressureCurve curve,
  }) async {
    final preset = <String, Object?>{
      'tool': tool.name,
      'color': color.toARGB32(),
      'size': size,
      'opacity': opacity,
      'pressureSensitivity': pressure,
      'velocitySensitivity': velocity,
      'pressureCurve': curve.name,
      'label': '${tool.label} ${_favoritePens.length + 1}',
    };
    setState(() {
      _favoritePens.add(preset);
      if (_favoritePens.length > 200) _favoritePens.removeAt(0);
      _showFavoritesShowcase = true;
    });
    await _saveFavoritePens();
    await _settings.setBool('editorV2ShowFavoritesShowcase', true);
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
    final dock = const <String>{'top', 'bottom', 'left', 'right'}.contains(value)
        ? value
        : 'top';
    setState(() {
      _toolbarDock = dock;
      _floatingToolbar = true;
    });
    await _settings.setString('editorV2ToolbarDock', dock);
    await _settings.setBool('editorV2FloatingToolbar', true);
  }

  Future<void> _toggleFloatingToolbar() async {
    setState(() => _floatingToolbar = !_floatingToolbar);
    await _settings.setBool('editorV2FloatingToolbar', _floatingToolbar);
  }

  Future<void> _toggleCompactFloatingToolbar() async {
    setState(() => _compactFloatingToolbar = !_compactFloatingToolbar);
    await _settings.setBool('editorV2CompactFloatingToolbar', _compactFloatingToolbar);
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
        SnackBar(content: Text('Page ${index + 1} ${locked ? 'locked' : 'unlocked'}')),
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
    var stylusHold = _settings.getBool('stylusHoldActions');
    var pressureErase = _settings.getBool('pressureErase');
    var showNavigation = _showPageNavigation;
    var showPageNumbers = _settings.getBool('showPageNumbers');
    var floatingNavigation = _floatingPageNavigation;
    var floatingToolbar = _floatingToolbar;
    var showFavorites = _showFavoritesShowcase;
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
                  decoration: const InputDecoration(labelText: 'Page template', prefixIcon: Icon(Icons.grid_4x4_rounded)),
                  items: PageTemplate.values.map((value) => DropdownMenuItem(value: value, child: Text(value.name))).toList(),
                  onChanged: (value) { if (value != null) setSheetState(() => template = value); },
                ),
                const SizedBox(height: 12),
                Row(children: [Icon(Icons.palette_outlined, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 8), const Text('Paper color')]),
                const SizedBox(height: 6),
                Wrap(spacing: 9, runSpacing: 8, children: [
                  ..._palette.map((candidate) => InkWell(
                    onTap: () => setSheetState(() => paper = candidate),
                    child: Container(width: 27, height: 27, decoration: BoxDecoration(
                      color: candidate, shape: BoxShape.circle,
                      border: Border.all(color: paper == candidate ? Theme.of(context).colorScheme.primary : Colors.black26, width: paper == candidate ? 3 : 1),
                    )),
                  )),
                  ActionChip(
                    avatar: const Icon(Icons.colorize_rounded, size: 16),
                    label: const Text('Custom…'),
                    onPressed: () async {
                      final candidate = await _pickCustomColor(initial: paper, title: 'Custom paper color');
                      if (candidate != null) setSheetState(() => paper = candidate);
                    },
                  ),
                ]),
                const SizedBox(height: 12),
                Row(children: [Icon(Icons.color_lens_outlined, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 8), const Text('Line / dot color')]),
                const SizedBox(height: 6),
                Wrap(spacing: 9, runSpacing: 8, children: [
                  ..._palette.where((candidate) => candidate != Colors.white).map((candidate) => InkWell(
                    onTap: () => setSheetState(() => line = candidate),
                    child: Container(width: 27, height: 27, decoration: BoxDecoration(
                      color: candidate, shape: BoxShape.circle,
                      border: Border.all(color: line == candidate ? Theme.of(context).colorScheme.primary : Colors.black26, width: line == candidate ? 3 : 1),
                    )),
                  )),
                  ActionChip(
                    avatar: const Icon(Icons.colorize_rounded, size: 16),
                    label: const Text('Custom…'),
                    onPressed: () async {
                      final candidate = await _pickCustomColor(initial: line, title: 'Custom line / dot color');
                      if (candidate != null) setSheetState(() => line = candidate);
                    },
                  ),
                ]),
                Row(children: [Icon(Icons.space_dashboard_outlined, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 8), Text('Grid / dot spacing: ${spacing.round()}')]),
                Slider(min: 10, max: 80, value: spacing, onChanged: (value) => setSheetState(() => spacing = value)),
                Row(children: [Icon(Icons.opacity_rounded, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 8), Text('Grid / dot opacity: ${(opacity * 100).round()}%')]),
                Slider(min: 0, max: 1, value: opacity, onChanged: (value) => setSheetState(() => opacity = value)),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.back_hand_outlined),
                  title: const Text('Palm rejection'),
                  subtitle: const Text('Ignore finger touches while the stylus is active'),
                  value: palm,
                  onChanged: (value) => setSheetState(() => palm = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.swap_vert_rounded),
                  title: const Text('Show page navigation'),
                  value: showNavigation,
                  onChanged: (value) => setSheetState(() => showNavigation = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.format_list_numbered_rounded),
                  title: const Text('Show page numbers'),
                  value: showPageNumbers,
                  onChanged: (value) => setSheetState(() => showPageNumbers = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.widgets_outlined),
                  title: const Text('Floating / movable toolbar'),
                  value: floatingToolbar,
                  onChanged: (value) => setSheetState(() => floatingToolbar = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.inventory_2_outlined),
                  title: const Text('Favorite pen case'),
                  value: showFavorites,
                  onChanged: (value) => setSheetState(() => showFavorites = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.vertical_align_center_rounded),
                  title: const Text('Floating vertical page navigation'),
                  value: floatingNavigation,
                  onChanged: (value) => setSheetState(() => floatingNavigation = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.gesture_rounded),
                  title: const Text('Stylus hold actions'),
                  subtitle: const Text('Hold on a stroke to select it; hold on blank paper for temporary eraser'),
                  value: stylusHold,
                  onChanged: (value) => setSheetState(() => stylusHold = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.crop_16_9_rounded),
                  title: const Text('Hold-to-erase on blank paper'),
                  value: pressureErase,
                  onChanged: (value) => setSheetState(() => pressureErase = value),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () async {
                      final pageLocked = _pageData['locked'] == true;
                      final pageSettingsChanged =
                          template.name != _pageData['template']?.toString() ||
                          spacing != ((_pageData['spacing'] as num?)?.toDouble() ?? 28) ||
                          opacity != ((_pageData['lineOpacity'] as num?)?.toDouble() ?? .85) ||
                          paper.toARGB32() != ((_pageData['paperColor'] as num?)?.toInt() ?? 0xffffffff) ||
                          line.toARGB32() != ((_pageData['lineColor'] as num?)?.toInt() ?? 0xffd8dee8);
                      if (!pageLocked && pageSettingsChanged) {
                        _pushUndo();
                        _pageData['template'] = template.name;
                        _pageData['spacing'] = spacing;
                        _pageData['lineOpacity'] = opacity;
                        _pageData['paperColor'] = paper.toARGB32();
                        _pageData['lineColor'] = line.toARGB32();
                      } else if (pageLocked && pageSettingsChanged && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('App settings were saved. Unlock this page to change its paper or template.')),
                        );
                      }
                      setState(() {
                        _showPageNavigation = showNavigation;
                        _floatingPageNavigation = floatingNavigation;
                        _floatingToolbar = floatingToolbar;
                        _showFavoritesShowcase = showFavorites;
                      });
                      await _settings.setBool('palmRejection', palm);
                      await _settings.setBool('stylusHoldActions', stylusHold);
                      await _settings.setBool('pressureErase', pressureErase);
                      await _settings.setBool('showPageNavigation', showNavigation);
                      await _settings.setBool('showPageNumbers', showPageNumbers);
                      await _settings.setBool('editorV2FloatingPageNavigation', floatingNavigation);
                      await _settings.setBool('editorV2FloatingToolbar', floatingToolbar);
                      await _settings.setBool('editorV2ShowFavoritesShowcase', showFavorites);
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


  void _showCanvasHud() {
    _viewportHudTimer?.cancel();
    if (!_showViewportHud && mounted) setState(() => _showViewportHud = true);
    _viewportHudTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted && !_viewportLocked) setState(() => _showViewportHud = false);
    });
  }

  void _toggleCanvasLock() {
    setState(() {
      _viewportLocked = !_viewportLocked;
      _showViewportHud = true;
    });
    _showCanvasHud();
  }

  void _resetCanvasView() {
    final availableWidth = MediaQuery.sizeOf(context).width -
        (_showPagePreview && !_fullScreenMode ? 220 : 12);
    final scale = (availableWidth.clamp(260.0, _pageWidth) / _pageWidth).clamp(.15, 1.0).toDouble();
    _transform.value = Matrix4.identity()..scale(scale);
    setState(() {
      _viewportLocked = false;
      _panMode = false;
      _showViewportHud = true;
    });
    _showCanvasHud();
  }

  void _toggleFullScreen() {
    setState(() => _fullScreenMode = !_fullScreenMode);
    unawaited(SystemChrome.setEnabledSystemUIMode(
      _fullScreenMode ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    ));
  }

  void _toggleWatermarkCover() {
    if (!_hasPdfBackgroundPages) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Watermark cover is available on PDF pages.')),
      );
      return;
    }

    if (_watermarkCoverMode) {
      setState(() {
        _watermarkCoverMode = false;
        _tool = _toolBeforeWatermarkCover ?? CanvasTool.ballpoint;
        _color = _colorBeforeWatermarkCover ?? const Color(0xff17202a);
        _size = _sizeBeforeWatermarkCover ?? 3;
        _opacity = _opacityBeforeWatermarkCover ?? 1;
        _toolBeforeWatermarkCover = null;
        _colorBeforeWatermarkCover = null;
        _sizeBeforeWatermarkCover = null;
        _opacityBeforeWatermarkCover = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Watermark cover mode off. The original PDF remains unchanged.')),
      );
      return;
    }

    _toolBeforeWatermarkCover = _tool;
    _colorBeforeWatermarkCover = _color;
    _sizeBeforeWatermarkCover = _size;
    _opacityBeforeWatermarkCover = _opacity;
    setState(() {
      _watermarkCoverMode = true;
      _tool = CanvasTool.ballpoint;
      _color = Colors.white;
      _size = 40;
      _opacity = 1;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Whiteout cover enabled. Draw over a watermark to mask it; this does not remove it from the source PDF.',
        ),
        duration: Duration(seconds: 5),
      ),
    );
  }

  void _zoom(double factor) {
    if (_viewportLocked) return;
    final next = _transform.value.clone()..scale(factor);
    _transform.value = next;
    _showCanvasHud();
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

  String get _elapsedClock {
    final minutes = _studySeconds ~/ 60;
    final seconds = _studySeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void _onMenuSelected(String value) {
    switch (value) {
      case 'addPage':
        _addPage();
      case 'text':
        break;
      case 'image':
        unawaited(_addImage());
      case 'clipboardImage':
        unawaited(_pasteClipboardImage());
      case 'pasteSelection':
        _pasteStrokes();
      case 'clipboardHistory':
        unawaited(_showClipboardHistory());
      case 'noteSwitcher':
        unawaited(_openNoteSwitcher());
      case 'splitView':
        unawaited(_openMultiSplitWorkspace());
      case 'toggleNoteSwitcher':
        unawaited(_toggleNoteSwitcher());
      case 'calculator':
        _openCalculator();
      case 'toolbarLayout':
        unawaited(_showToolbarLayoutSettings());
      case 'calculatorSettings':
        unawaited(_specialToolSettingsSheet('calculator'));
      case 'screenshotSettings':
        unawaited(_specialToolSettingsSheet('screenshot'));
      case 'sticker':
        unawaited(_addSticker());
      case 'pdf':
        unawaited(_importPdf());
      case 'importOtherFormats':
        unawaited(_importOtherFormats());
      case 'export':
        unawaited(_exportPdf());
      case 'template':
        unawaited(_chooseTemplate());
      case 'smartPages':
        unawaited(_showSmartPagesLibrary());
      case 'bookmarks':
        unawaited(_showBookmarks());
      case 'timer':
        setState(() => _showFloatingTimer = true);
      case 'webSearch':
        unawaited(SnoteWebSearchPanel.show(context));
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
      case 'compactToolbar':
        unawaited(_toggleCompactFloatingToolbar());
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
      case 'appSettings':
        unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsPage())));
      case 'togglePageLock':
        unawaited(_togglePageLock());
      case 'notesLayer':
        _setPdfBackgroundVisible(false);
      case 'pdfLayer':
        _setPdfBackgroundVisible(true);
      case 'watermarkCover':
        _toggleWatermarkCover();
      case 'pan':
        setState(() => _panMode = !_panMode);
      case 'zoomIn':
        _zoom(1.2);
      case 'zoomOut':
        _zoom(.83);
      case 'fit':
        final scale = (MediaQuery.sizeOf(context).width - 30).clamp(260.0, _pageWidth) / _pageWidth;
        _transform.value = Matrix4.identity()..scale(scale);
      case 'fullscreen':
        _toggleFullScreen();
      case 'readingMode':
        setState(() {
          _readingMode = !_readingMode;
          _fullScreenMode = _readingMode;
          _panMode = _readingMode;
          if (!_readingMode && _toolBeforeReading != null) {
            _tool = _toolBeforeReading!;
            _toolBeforeReading = null;
          }
        });
        unawaited(SystemChrome.setEnabledSystemUIMode(_readingMode ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge));
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
      CanvasTool.fill => Icons.format_color_fill_rounded,
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

  Widget _buildToolbarToolButton(CanvasTool tool) {
    Widget tile({required bool faded}) => Opacity(
          opacity: faded ? .25 : 1,
          child: Tooltip(
            message: '${tool.label}\nDouble-tap for settings • long-press and drag to reorder',
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                borderRadius: BorderRadius.circular(7),
                onTapDown: (details) => _toolSettingsAnchor = details.globalPosition,
                onDoubleTap: () => _strokeSettings(tool, _toolSettingsAnchor),
                onTap: () => _selectTool(tool),
                child: SizedBox(width: 30, height: 30, child: Stack(alignment: Alignment.center, children: [Icon(_toolIcon(tool), size: 18, color: _tool == tool ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface), if (_tool == tool) Positioned(bottom: 1, child: Container(width: 4, height: 4, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, shape: BoxShape.circle))) ])),
              ),
            ),
          ),
        );

    return DragTarget<Object>(
      onWillAcceptWithDetails: (details) => details.data != tool,
      onAcceptWithDetails: (details) => unawaited(_moveDroppedTool(details.data, 'toolbar', target: tool)),
      builder: (context, candidates, rejected) => LongPressDraggable<Object>(
        data: tool,
        maxSimultaneousDrags: 1,
        feedback: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(7),
          child: SizedBox(width: 29, height: 29, child: Icon(_toolIcon(tool), size: 17, color: Theme.of(context).colorScheme.primary)),
        ),
        childWhenDragging: tile(faded: true),
        child: tile(faded: false),
      ),
    );
  }

  Future<void> _showToolbarLayoutSettings() async {
    var length = _toolbarLength, thickness = _toolbarThickness;
    var ml = _toolbarMarginLeft, mt = _toolbarMarginTop;
    var mr = _toolbarMarginRight, mb = _toolbarMarginBottom;
    var pl = _toolbarPaddingLeft, pt = _toolbarPaddingTop;
    var pr = _toolbarPaddingRight, pb = _toolbarPaddingBottom;
    var locked = _toolbarDimensionsLocked;
    final result = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          Widget slider(String label, double value, double min, double max,
              ValueChanged<double> onChanged, {int divisions = 24}) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: Text(label)),
                  Text(value.toStringAsFixed(0), style: Theme.of(context).textTheme.labelMedium),
                ]),
                Slider(
                  value: value.clamp(min, max).toDouble(),
                  min: min, max: max, divisions: divisions,
                  onChanged: locked ? null : onChanged,
                ),
              ],
            );
          }
          return AlertDialog(
            title: const Text('Toolbar size & spacing'),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Lock toolbar dimensions'),
                    subtitle: const Text('Prevents accidental layout adjustments.'),
                    value: locked,
                    onChanged: (value) => setDialogState(() => locked = value),
                  ),
                  slider('Horizontal length', length, 180, 900, (v) => setDialogState(() => length = v), divisions: 36),
                  slider('Vertical width / thickness', thickness, 28, 96, (v) => setDialogState(() => thickness = v), divisions: 34),
                  const Divider(),
                  Text('Outer margin by direction', style: Theme.of(context).textTheme.titleSmall),
                  slider('Left margin', ml, 0, 24, (v) => setDialogState(() => ml = v)),
                  slider('Top margin', mt, 0, 24, (v) => setDialogState(() => mt = v)),
                  slider('Right margin', mr, 0, 24, (v) => setDialogState(() => mr = v)),
                  slider('Bottom margin', mb, 0, 24, (v) => setDialogState(() => mb = v)),
                  const Divider(),
                  Text('Inner padding by direction', style: Theme.of(context).textTheme.titleSmall),
                  slider('Left padding', pl, 0, 20, (v) => setDialogState(() => pl = v)),
                  slider('Top padding', pt, 0, 20, (v) => setDialogState(() => pt = v)),
                  slider('Right padding', pr, 0, 20, (v) => setDialogState(() => pr = v)),
                  slider('Bottom padding', pb, 0, 20, (v) => setDialogState(() => pb = v)),
                ]),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
              TextButton(
                onPressed: () => setDialogState(() {
                  length = 360; thickness = 34;
                  ml = 0; mt = 0; mr = 0; mb = 0;
                  pl = 2; pt = 1; pr = 2; pb = 1;
                }),
                child: const Text('Reset'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, <String, Object?>{
                  'length': length, 'thickness': thickness,
                  'ml': ml, 'mt': mt, 'mr': mr, 'mb': mb,
                  'pl': pl, 'pt': pt, 'pr': pr, 'pb': pb, 'locked': locked,
                }),
                child: const Text('Apply'),
              ),
            ],
          );
        },
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _toolbarLength = (result['length'] as num).toDouble();
      _toolbarThickness = (result['thickness'] as num).toDouble();
      _toolbarMarginLeft = (result['ml'] as num).toDouble();
      _toolbarMarginTop = (result['mt'] as num).toDouble();
      _toolbarMarginRight = (result['mr'] as num).toDouble();
      _toolbarMarginBottom = (result['mb'] as num).toDouble();
      _toolbarPaddingLeft = (result['pl'] as num).toDouble();
      _toolbarPaddingTop = (result['pt'] as num).toDouble();
      _toolbarPaddingRight = (result['pr'] as num).toDouble();
      _toolbarPaddingBottom = (result['pb'] as num).toDouble();
      _toolbarDimensionsLocked = result['locked'] == true;
    });
    await Future.wait([
      _settings.setDouble('editorV2ToolbarLength', _toolbarLength),
      _settings.setDouble('editorV2ToolbarThickness', _toolbarThickness),
      _settings.setDouble('editorV2ToolbarMarginLeft', _toolbarMarginLeft),
      _settings.setDouble('editorV2ToolbarMarginTop', _toolbarMarginTop),
      _settings.setDouble('editorV2ToolbarMarginRight', _toolbarMarginRight),
      _settings.setDouble('editorV2ToolbarMarginBottom', _toolbarMarginBottom),
      _settings.setDouble('editorV2ToolbarPaddingLeft', _toolbarPaddingLeft),
      _settings.setDouble('editorV2ToolbarPaddingTop', _toolbarPaddingTop),
      _settings.setDouble('editorV2ToolbarPaddingRight', _toolbarPaddingRight),
      _settings.setDouble('editorV2ToolbarPaddingBottom', _toolbarPaddingBottom),
      _settings.setBool('editorV2ToolbarDimensionsLocked', _toolbarDimensionsLocked),
    ]);
  }

  Widget _buildToolbar({required bool vertical}) {
    Widget action({
      required String tooltip,
      required IconData icon,
      required VoidCallback onPressed,
      Color? color,
      bool captureAnchor = false,
    }) {
      final button = IconButton(
        visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
        padding: const EdgeInsets.all(2),
        constraints: const BoxConstraints.tightFor(width: 28, height: 28),
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 17, color: color),
      );
      if (!captureAnchor) return button;
      return Listener(
        onPointerDown: (event) => _toolSettingsAnchor = event.position,
        child: button,
      );
    }
    final actions = <Widget>[
      action(tooltip: _panMode ? 'Exit pan mode' : 'Pan / zoom', icon: _panMode ? Icons.pan_tool : Icons.pan_tool_outlined, onPressed: () => setState(() => _panMode = !_panMode)),
      action(
        tooltip: 'Color palette & opacity',
        icon: Icons.palette_outlined,
        color: _color,
        captureAnchor: true,
        onPressed: () => unawaited(_strokeSettings(null, _toolSettingsAnchor)),
      ),
      action(tooltip: 'Capture screen to canvas', icon: Icons.screenshot_monitor_rounded, onPressed: () => unawaited(_captureScreenToCanvas())),
      if (_hasPdfBackgroundPages)
        action(
          tooltip: _watermarkCoverMode
              ? 'Exit watermark cover mode'
              : 'Watermark cover / whiteout (masks only; source PDF unchanged)',
          icon: Icons.layers_clear_rounded,
          color: _watermarkCoverMode ? Theme.of(context).colorScheme.primary : null,
          onPressed: _toggleWatermarkCover,
        ),

      action(tooltip: 'Selection clipboard history', icon: Icons.content_paste_go_rounded, onPressed: () => unawaited(_showClipboardHistory())),
      action(tooltip: 'Shape box', icon: Icons.category_outlined, onPressed: () => _openToolPicker(initialCategory: 'Shapes & diagrams')),
      action(tooltip: 'Sticker library', icon: Icons.emoji_emotions_outlined, onPressed: () => unawaited(_addSticker())),
    ];
    final quickButtons = _toolKeysForLocation('toolbar')
        .map((key) => Padding(
              padding: const EdgeInsets.all(.5),
              child: _buildPlacedToolButton(key, 'toolbar'),
            ))
        .toList();
    final children = <Widget>[
      if (_floatingToolbar || _fullScreenMode)
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (details) => setState(() => _floatingOffset += details.delta),
          child: Tooltip(
            message: 'Drag toolbar from here',
            child: SizedBox(width: 28, height: 28, child: Icon(Icons.drag_indicator_rounded, size: 18, color: Theme.of(context).colorScheme.primary)),
          ),
        ),
      ...actions,
      if (!vertical) const VerticalDivider(width: 5, indent: 6, endIndent: 6),
      ...quickButtons,
      action(tooltip: 'Insert page', icon: Icons.note_add_outlined, onPressed: _addPage),
      PopupMenuButton<String>(
        tooltip: 'Workspace options',
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 28, height: 28),
        onSelected: _onMenuSelected,
        itemBuilder: (_) => <PopupMenuEntry<String>>[
          PopupMenuItem(value: 'image', child: Text('Insert image from file')),
          if (_specialToolLocations('screenshot').isNotEmpty)
            PopupMenuItem(value: 'clipboardImage', child: Text('Paste screenshot from clipboard')),
          PopupMenuItem(value: 'pasteSelection', enabled: _selectionClipboard != null, child: Text('Paste copied selection')),
          PopupMenuItem(value: 'clipboardHistory', enabled: _selectionClipboardHistory.isNotEmpty, child: Text('Clipboard history (last 4)')),
          if (_specialToolLocations('calculator').isNotEmpty)
            PopupMenuItem(value: 'calculator', child: Text('Scientific calculator')),
          const PopupMenuItem(value: 'toolbarLayout', child: Text('Toolbar size, margins & padding')),
          const PopupMenuItem(value: 'smartPages', child: Text('Smart Pages library (200+)')),
          const PopupMenuItem(value: 'calculatorSettings', child: Text('Calculator placement / settings')),
          const PopupMenuItem(value: 'screenshotSettings', child: Text('Screenshot tool placement / settings')),
          PopupMenuItem(value: 'sticker', child: Text('Sticker library')),

          PopupMenuItem(value: 'pdf', child: Text('Import / annotate PDF')),
          PopupMenuItem(value: 'importOtherFormats', child: Text('Import SVG, CSV, PNG, PPTX, Excel or Nebo file')),
          PopupMenuItem(value: 'export', child: Text('Export pages to PDF')),
          PopupMenuItem(value: 'bookmarks', child: Text('Bookmarks')),
          PopupMenuItem(value: 'timer', child: Text('Study timer')),
          PopupMenuItem(value: 'splitView', child: Text('Open multi-split notes')),
          PopupMenuDivider(),
          PopupMenuItem(value: 'dockTop', child: Text('Dock toolbar to top')),
          PopupMenuItem(value: 'dockLeft', child: Text('Dock toolbar to left')),
          PopupMenuItem(value: 'dockRight', child: Text('Dock toolbar to right')),
          PopupMenuItem(value: 'float', child: Text('Toggle floating toolbar')),
          PopupMenuItem(value: 'compactToolbar', child: Text(_compactFloatingToolbar ? 'Disable compact floating toolbar' : 'Enable compact floating toolbar')),
          PopupMenuItem(value: 'favoritesShowcase', child: Text('Show / hide favorite pen case')),
          PopupMenuItem(value: 'favoritesOrientation', child: Text('Rotate pen case')),
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
    final screenWidth = MediaQuery.sizeOf(context).width;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final compactWidth = vertical
        ? _toolbarThickness.clamp(28.0, 96.0).toDouble()
        : math.min(
            math.max(1.0, screenWidth - 12),
            math.min(_toolbarLength, actions.length * 28.0 + quickButtons.length * 30.0 + 69.0),
          );
    final compactHeight = vertical
        ? math.min(_toolbarLength, math.max(180.0, screenHeight - 24))
        : _toolbarThickness.clamp(28.0, 96.0).toDouble();
    return SnoteFloatingToolbar(
      children: children,
      vertical: vertical,
      compact: _compactFloatingToolbar,
      fullScreen: _fullScreenMode,
      width: compactWidth,
      height: compactHeight,
      marginLeft: _fullScreenMode ? 0 : _toolbarMarginLeft,
      marginTop: _fullScreenMode ? 0 : _toolbarMarginTop,
      marginRight: _fullScreenMode ? 0 : _toolbarMarginRight,
      marginBottom: _fullScreenMode ? 0 : _toolbarMarginBottom,
      paddingLeft: _fullScreenMode ? 0 : _toolbarPaddingLeft,
      paddingTop: _fullScreenMode ? 0 : _toolbarPaddingTop,
      paddingRight: _fullScreenMode ? 0 : _toolbarPaddingRight,
      paddingBottom: _fullScreenMode ? 0 : _toolbarPaddingBottom,
    );
  }

  Widget _buildFavoriteShowcase() {
    final placedToolChips = _toolKeysForLocation('pencase')
        .map((key) => _buildPlacedToolButton(key, 'pencase'))
        .toList();
    final favoriteChips = (_showFavoritesShowcase ? _favoritePens : const <Map<String, Object?>>[]).map((favorite) {
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
            width: _favoritesVertical ? 34 : 38,
            height: _favoritesVertical ? 38 : 34,
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
    final chips = <Widget>[
      ...placedToolChips,
      ...favoriteChips,
    ];
    final screen = MediaQuery.sizeOf(context);
    if (_favoriteCollapsed) {
      final dockLeft = _favoriteOffset.dx < screen.width / 2;
      return Positioned(
        left: dockLeft ? 0 : null,
        right: dockLeft ? null : 0,
        top: _favoriteOffset.dy.clamp(72.0, math.max(72.0, screen.height - 80)).toDouble(),
        child: Material(
          elevation: 7,
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.horizontal(
            left: Radius.circular(dockLeft ? 0 : 14),
            right: Radius.circular(dockLeft ? 14 : 0),
          ),
          child: InkWell(
            onTap: () {
              setState(() => _favoriteCollapsed = false);
              unawaited(_settings.setBool('editorV2FavoriteCollapsed', false));
            },
            child: const SizedBox(
              width: 30,
              height: 68,
              child: Tooltip(message: 'Expand favorite pens and tools', child: Icon(Icons.favorite_rounded)),
            ),
          ),
        ),
      );
    }
    return Positioned(
      left: _favoriteOffset.dx.clamp(0, math.max(0, screen.width - (_favoritesVertical ? 62 : 120))).toDouble(),
      top: _favoriteOffset.dy.clamp(0, math.max(0, screen.height - 120)).toDouble(),
      child: GestureDetector(
        onPanUpdate: (details) => setState(() => _favoriteOffset += details.delta),
        onPanEnd: (_) {
          final leftEdge = _favoriteOffset.dx < 28;
          final rightEdge = _favoriteOffset.dx > screen.width - 120;
          if (leftEdge || rightEdge) {
            setState(() {
              _favoritesVertical = true;
              _favoriteOffset = Offset(
                leftEdge ? 4 : math.max(4, screen.width - 62),
                _favoriteOffset.dy.clamp(72, math.max(72, screen.height - 120)).toDouble(),
              );
            });
            unawaited(_settings.setBool('editorV2FavoritesVertical', true));
            unawaited(_settings.setString('editorV2FavoriteDock', leftEdge ? 'left' : 'right'));
            unawaited(_settings.setString('editorV2FavoriteOffset', jsonEncode({
              'dx': _favoriteOffset.dx,
              'dy': _favoriteOffset.dy,
            })));
          } else {
            unawaited(_settings.setString('editorV2FavoriteDock', 'floating'));
            unawaited(_settings.setString('editorV2FavoriteOffset', jsonEncode({
              'dx': _favoriteOffset.dx,
              'dy': _favoriteOffset.dy,
            })));
          }
        },
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
                  IconButton(
                    tooltip: 'Collapse pen showcase to screen edge',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(width: 22, height: 22),
                    onPressed: () {
                      final dockLeft = _favoriteOffset.dx < screen.width / 2;
                      setState(() {
                        _favoriteCollapsed = true;
                        _favoriteOffset = Offset(dockLeft ? 0 : screen.width - 30, _favoriteOffset.dy);
                        unawaited(_settings.setBool('editorV2FavoriteCollapsed', true));
                      });
                      unawaited(_settings.setString('editorV2FavoriteDock', dockLeft ? 'left' : 'right'));
                    },
                    icon: const Icon(Icons.favorite_rounded, size: 15),
                  ),
                  const SizedBox(width: 3),
                  InkWell(
                    onTap: _toggleFavoritesOrientation,
                    child: Icon(_favoritesVertical ? Icons.swap_vert_rounded : Icons.swap_horiz_rounded, size: 14),
                  ),
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

  void _openCalculator() {
    setState(() => _calculatorVisible = !_calculatorVisible);
  }

  Widget _buildFloatingCalculator() {
    final screen = MediaQuery.sizeOf(context);
    final width = _calculatorWidth.clamp(270.0, math.max(270.0, screen.width - 16)).toDouble();
    final height = _calculatorHeight.clamp(360.0, math.max(360.0, screen.height - 32)).toDouble();
    if (_calculatorCollapsed) {
      final dockLeft = _calculatorOffset.dx < screen.width / 2;
      return Positioned(
        left: dockLeft ? 0 : null,
        right: dockLeft ? null : 0,
        top: _calculatorOffset.dy.clamp(8.0, math.max(8.0, screen.height - 82)).toDouble(),
        child: Material(
          elevation: 7,
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.horizontal(
            left: Radius.circular(dockLeft ? 0 : 14),
            right: Radius.circular(dockLeft ? 14 : 0),
          ),
          child: InkWell(
            onTap: () {
              setState(() => _calculatorCollapsed = false);
              unawaited(_settings.setBool('editorV2CalculatorCollapsed', false));
            },
            child: const SizedBox(
              width: 32,
              height: 72,
              child: Tooltip(message: 'Expand calculator', child: Icon(Icons.calculate_rounded)),
            ),
          ),
        ),
      );
    }
    return Positioned(
      left: _calculatorOffset.dx.clamp(0, math.max(0, screen.width - width)).toDouble(),
      top: _calculatorOffset.dy.clamp(0, math.max(0, screen.height - height)).toDouble(),
      child: _ScientificCalculatorDialog(
        initialWidth: width,
        initialHeight: height,
        onResize: (size) => setState(() {
          _calculatorWidth = size.width;
          _calculatorHeight = size.height;
        }),
        onMove: (delta) => setState(() => _calculatorOffset += delta),
        onCollapse: () {
          final dockLeft = _calculatorOffset.dx < screen.width / 2;
          setState(() {
            _calculatorCollapsed = true;
            _calculatorOffset = Offset(dockLeft ? 0 : screen.width - 32, _calculatorOffset.dy);
          });
          unawaited(_settings.setBool('editorV2CalculatorCollapsed', true));
        },
        onClose: () => setState(() => _calculatorVisible = false),
      ),
    );
  }

  Widget _buildPageBackground(Map<String, Object?> page, {bool showPdf = true, bool thumbnail = false}) {
    if (showPdf && page['pdfLazyRender'] == true) {
      final assetId = page['pdfSourceAssetId']?.toString();
      final sourcePage = (page['pdfSourcePage'] as num?)?.toInt();
      if (assetId == null || assetId.isEmpty || sourcePage == null) {
        return const ColoredBox(color: Color(0xfffff8e7), child: Center(child: Icon(Icons.picture_as_pdf_rounded, color: Colors.redAccent)));
      }
      return FutureBuilder<Uint8List?>(
        future: _lazyPdfPageRaster(assetId, sourcePage, thumbnail: thumbnail),
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes != null && bytes.isNotEmpty) {
            return Image.memory(bytes, fit: BoxFit.fill,
              filterQuality: thumbnail ? FilterQuality.low : FilterQuality.high,
              errorBuilder: (_, error, stackTrace) => const ColoredBox(color: Color(0xfffff8e7), child: Center(child: Icon(Icons.broken_image_outlined))),
            );
          }
          if (snapshot.hasError) {
            return ColoredBox(color: const Color(0xfffff8e7),
              child: Center(child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text('PDF page $sourcePage could not be rendered.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: thumbnail ? 8 : 12)),
              )),
            );
          }
          return ColoredBox(
            color: Colors.white,
            child: Center(
              child: SizedBox(
                width: thumbnail ? 16 : 24,
                height: thumbnail ? 16 : 24,
                child: CircularProgressIndicator(
                  strokeWidth: thumbnail ? 1.6 : 2,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          );
        },
      );
    }
    final source = page['backgroundImage'];
    if (showPdf && source is String && source.isNotEmpty) {
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
          child: IgnorePointer(child: Image.memory(bytes, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined))),
        ));
      } catch (_) {}
    }
    return Stack(clipBehavior: Clip.none, children: children);
  }

  void _updateTextBoxField(String id, String key, Object? value) {
    final raw = _pageData['textBoxes'];
    if (raw is! List) return;
    for (final item in raw.whereType<Map>()) {
      if (item['id']?.toString() == id) {
        item[key] = value;
        return;
      }
    }
  }

  List<Map<String, Object?>> _decodeTextFormatRanges(Object? raw) {
    if (raw is! List) return <Map<String, Object?>>[];
    return raw.whereType<Map>().map((range) => range.map<String, Object?>(
      (key, value) => MapEntry(key.toString(), value),
    )).where((range) => range['start'] is num && range['end'] is num).toList();
  }

  void _applyTextBoxFormatSelection(
    String id,
    String key,
    TextEditingController controller,
  ) {
    final selection = controller.selection;
    if (!selection.isValid || selection.isCollapsed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select some text first to apply formatting.')),
      );
      return;
    }
    final raw = _pageData['textBoxes'];
    if (raw is! List) return;
    for (final item in raw.whereType<Map>()) {
      if (item['id']?.toString() != id) continue;
      final ranges = _decodeTextFormatRanges(item['formatRanges']);
      bool? current;
      for (final range in ranges) {
        final start = (range['start'] as num).toInt();
        final end = (range['end'] as num).toInt();
        if (start <= selection.start && end >= selection.end && range.containsKey(key)) {
          current = range[key] == true;
        }
      }
      ranges.add(<String, Object?>{
        'start': selection.start,
        'end': selection.end,
        key: current != true,
      });
      item['formatRanges'] = ranges;
      if (controller is _FormattedTextEditingController) {
        controller.formatRanges = ranges;
      }
      setState(() {});
      _scheduleSave();
      return;
    }
  }

  void _adjustTextBoxFontSize(String id, double delta) {
    final raw = _pageData['textBoxes'];
    if (raw is! List) return;
    for (final item in raw.whereType<Map>()) {
      if (item['id']?.toString() == id) {
        final size = (item['fontSize'] as num?)?.toDouble() ?? 18.0;
        item['fontSize'] = (size + delta).clamp(8.0, 96.0).toDouble();
        setState(() {});
        _scheduleSave();
        return;
      }
    }
  }

  void _setTextBoxAlignment(String id, String alignment) {
    final raw = _pageData['textBoxes'];
    if (raw is! List) return;
    for (final item in raw.whereType<Map>()) {
      if (item['id']?.toString() == id) {
        item['textAlign'] = alignment;
        setState(() {});
        _scheduleSave();
        return;
      }
    }
  }

  void _resetTextBoxFormatting(String id) {
    final raw = _pageData['textBoxes'];
    if (raw is! List) return;
    for (final item in raw.whereType<Map>()) {
      if (item['id']?.toString() == id) {
        for (final key in const ['bold', 'italic', 'underline', 'strikethrough']) {
          item[key] = false;
        }
        item['fontSize'] = 18.0;
        item['textAlign'] = 'left';
        item['formatRanges'] = <Map<String, Object?>>[];
        setState(() {});
        _scheduleSave();
        return;
      }
    }
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
        () => _FormattedTextEditingController(text: box['text']?.toString() ?? ''),
      );
      final formatRanges = _decodeTextFormatRanges(box['formatRanges']);
      if (controller is _FormattedTextEditingController) {
        controller.formatRanges = formatRanges;
      }
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
        child: IgnorePointer(
          ignoring: _tool == CanvasTool.lasso,
          child: DecoratedBox(
          // Text boxes and stickers stay transparent; selection is shown by handles.
          decoration: snoteTransparentTextBoxDecoration,
          child: Stack(
            children: [
              Positioned.fill(
                child: TextField(
                  controller: controller,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  textAlign: switch (box['textAlign']?.toString()) {
                    'center' => TextAlign.center,
                    'right' => TextAlign.right,
                    'justify' => TextAlign.justify,
                    _ => TextAlign.start,
                  },
                  style: TextStyle(
                    fontSize: fontSize,
                    color: color,
                    height: 1.15,
                    fontWeight: box['bold'] == true ? FontWeight.bold : FontWeight.normal,
                    fontStyle: box['italic'] == true ? FontStyle.italic : FontStyle.normal,
                    decoration: TextDecoration.combine(<TextDecoration>[
                      if (box['underline'] == true) TextDecoration.underline,
                      if (box['strikethrough'] == true) TextDecoration.lineThrough,
                    ]),
                  ),
                  contextMenuBuilder: (context, editableTextState) {
                    final baseItems = editableTextState.contextMenuButtonItems;
                    return AdaptiveTextSelectionToolbar.buttonItems(
                      anchors: editableTextState.contextMenuAnchors,
                      buttonItems: <ContextMenuButtonItem>[
                        ...baseItems,
                        ContextMenuButtonItem(label: 'Bold selection', onPressed: () { editableTextState.hideToolbar(); _applyTextBoxFormatSelection(id, 'bold', controller); }),
                        ContextMenuButtonItem(label: 'Italic selection', onPressed: () { editableTextState.hideToolbar(); _applyTextBoxFormatSelection(id, 'italic', controller); }),
                        ContextMenuButtonItem(label: 'Underline selection', onPressed: () { editableTextState.hideToolbar(); _applyTextBoxFormatSelection(id, 'underline', controller); }),
                        ContextMenuButtonItem(label: 'Strikethrough selection', onPressed: () { editableTextState.hideToolbar(); _applyTextBoxFormatSelection(id, 'strikethrough', controller); }),
                        ContextMenuButtonItem(label: 'Increase text size', onPressed: () { editableTextState.hideToolbar(); _adjustTextBoxFontSize(id, 2); }),
                        ContextMenuButtonItem(label: 'Decrease text size', onPressed: () { editableTextState.hideToolbar(); _adjustTextBoxFontSize(id, -2); }),
                        ContextMenuButtonItem(label: 'Align center', onPressed: () { editableTextState.hideToolbar(); _setTextBoxAlignment(id, 'center'); }),
                        ContextMenuButtonItem(label: 'Align left', onPressed: () { editableTextState.hideToolbar(); _setTextBoxAlignment(id, 'left'); }),
                        ContextMenuButtonItem(label: 'Align right', onPressed: () { editableTextState.hideToolbar(); _setTextBoxAlignment(id, 'right'); }),
                        ContextMenuButtonItem(label: 'Justify text', onPressed: () { editableTextState.hideToolbar(); _setTextBoxAlignment(id, 'justify'); }),
                        ContextMenuButtonItem(label: 'Reset formatting', onPressed: () { editableTextState.hideToolbar(); _resetTextBoxFormatting(id); }),
                      ],
                    );
                  },
                  onChanged: (value) {
                    if (controller is _FormattedTextEditingController) {
                      controller.reconcileText(value);
                      _updateTextBoxField(id, 'formatRanges', controller.formatRanges);
                    }
                    _updateTextBoxField(id, 'text', value);
                    _scheduleSave();
                  },
                  decoration: InputDecoration(
                    filled: false,
                    fillColor: Colors.transparent,
                    hintText: box['sticker'] == true ? '' : 'Write text…',
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.fromLTRB(6, 4, 22, 4),
                  ),
                ),
              ),
              if (box['sticker'] != true || _selectedTextBoxIds.contains(id))
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
        ),
      ));
    }
    return Stack(clipBehavior: Clip.none, children: children);
  }

  Widget _buildPagePreviewSidebar() {
    final sidebarWidth = MediaQuery.sizeOf(context).width >= 900 ? 216.0 : 172.0;
    final cardWidth = sidebarWidth - 20;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      elevation: 2,
      child: SizedBox(
        width: sidebarWidth,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.auto_stories_rounded, size: 17),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'Pages',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(width: 30, height: 30),
                    tooltip: 'Search pages / jump to page',
                    onPressed: _showPageSearch,
                    icon: const Icon(Icons.search_rounded, size: 18),
                  ),
                  Text(
                    _pages.length.toString(),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ReorderableListView.builder(
                onReorder: (oldIndex, newIndex) {
                  if (newIndex > oldIndex) newIndex--;
                  _movePage(oldIndex, newIndex);
                },
                // ReorderableListView.builder virtualizes page cards. PDF page
                // rasters are independently lazy-loaded and byte-bounded.
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                itemCount: _pages.length,
                itemBuilder: (context, index) {
                  final page = _pages[index];
                  final cardHeight = cardWidth / _pageAspectRatioFor(page);
                  final selected = index == _page;
                  final isPdf = page['pdfLazyRender'] == true ||
                      (page['backgroundImage'] is String &&
                          (page['backgroundImage'] as String).isNotEmpty);
                  final rawStrokes = _strokesFor(page);
                  final rawTextBoxes = page['textBoxes'] is List
                      ? (page['textBoxes'] as List).whereType<Map>().toList()
                      : const <Map>[];
                  return Padding(
                    key: ValueKey(page['id']?.toString() ?? 'sidebar-page-$index'),
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        RepaintBoundary(
                          child: Container(
                            height: cardHeight,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(
                              color: selected
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.outlineVariant,
                              width: selected ? 2 : 1,
                            ),
                            boxShadow: selected
                                ? [
                                    BoxShadow(
                                      color: Theme.of(context).colorScheme.primary.withValues(alpha: .10),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ]
                                : const [],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                InkWell(
                                  onTap: () => _goToPage(index),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      _buildPageBackground(
                                        page,
                                        showPdf: true,
                                        thumbnail: true,
                                      ),
                                      FittedBox(
                                        fit: BoxFit.contain,
                                        child: SizedBox(
                                          width: _pageWidth,
                                          height: _pageHeight,
                                          child: Stack(
                                            fit: StackFit.expand,
                                            children: [
                                              CustomPaint(
                                                painter: EditorV2InkPainter(
                                                  strokes: rawStrokes,
                                                ),
                                              ),
                                              for (final box in rawTextBoxes)
                                                Positioned(
                                                  left: (((box['x'] as num?)?.toDouble() ?? .1) * _pageWidth).clamp(0.0, _pageWidth - 1).toDouble(),
                                                  top: (((box['y'] as num?)?.toDouble() ?? .1) * _pageHeight).clamp(0.0, _pageHeight - 1).toDouble(),
                                                  width: (((box['width'] as num?)?.toDouble() ?? .68) * _pageWidth).clamp(1.0, _pageWidth).toDouble(),
                                                  height: (((box['height'] as num?)?.toDouble() ?? .16) * _pageHeight).clamp(1.0, _pageHeight).toDouble(),
                                                  child: IgnorePointer(
                                                    child: Text(
                                                      box['text']?.toString() ?? '',
                                                      maxLines: 8,
                                                      overflow: TextOverflow.clip,
                                                      style: TextStyle(
                                                        color: Color((box['color'] as num?)?.toInt() ?? 0xff17202a),
                                                        fontSize: (((box['fontSize'] as num?)?.toDouble() ?? 22) * .75).clamp(8.0, 24.0).toDouble(),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Positioned(
                                  left: 6,
                                  bottom: 6,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.surface.withValues(alpha: .94),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: Theme.of(context).colorScheme.outlineVariant,
                                      ),
                                    ),
                                    child: Text(
                                      'Page ${index + 1}',
                                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                        fontWeight: FontWeight.w900,
                                        color: Theme.of(context).colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                ),
                                if (isPdf)
                                  const Positioned(
                                    left: 6,
                                    top: 6,
                                    child: Icon(Icons.picture_as_pdf_rounded, size: 15, color: Colors.redAccent),
                                  ),
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  child: Material(
                                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                    borderRadius: const BorderRadius.only(
                                      bottomLeft: Radius.circular(8),
                                    ),
                                    child: PopupMenuButton<String>(
                                      tooltip: 'Page ${index + 1} options',
                                      useRootNavigator: true,
                                      position: PopupMenuPosition.under,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                                      iconSize: 22,
                                      icon: Icon(Icons.more_vert_rounded, color: Theme.of(context).colorScheme.onSurface),
                                      onSelected: (action) {
                                        switch (action) {
                                          case 'blank':
                                            unawaited(_insertBlankPageAfter(index));
                                          case 'background':
                                            unawaited(_choosePageBackground(index));
                                          case 'up':
                                            _movePage(index, index - 1);
                                          case 'down':
                                            _movePage(index, index + 1);
                                          case 'cut':
                                            _cutPage(index);
                                          case 'copy':
                                            _copyPage(index);
                                          case 'paste':
                                            _pastePage(insertAfter: index);
                                          case 'duplicate':
                                            _duplicatePage(index);
                                          case 'clear':
                                            unawaited(_clearPageWithConfirmation(index));
                                          case 'share':
                                            unawaited(_sharePage(index));
                                          case 'bookmark':
                                            setState(() {
                                              final pageNumber = index + 1;
                                              if (_bookmarkedPages.contains(pageNumber)) {
                                                _bookmarkedPages.remove(pageNumber);
                                              } else {
                                                _bookmarkedPages.add(pageNumber);
                                                _bookmarkedPages.sort();
                                              }
                                            });
                                            _scheduleSave();
                                          case 'delete':
                                            unawaited(_confirmDeletePage(index));
                                        }
                                      },
                                      itemBuilder: (_) => <PopupMenuEntry<String>>[
                                        const PopupMenuItem(value: 'blank', child: ListTile(dense: true, leading: Icon(Icons.note_add_outlined), title: Text('Insert blank page'))),
                                        const PopupMenuItem(value: 'background', child: ListTile(dense: true, leading: Icon(Icons.format_color_fill_rounded), title: Text('Change background'))),
                                        PopupMenuItem(value: 'up', enabled: index > 0, child: const ListTile(dense: true, leading: Icon(Icons.arrow_upward_rounded), title: Text('Move up'))),
                                        PopupMenuItem(value: 'down', enabled: index < _pages.length - 1, child: const ListTile(dense: true, leading: Icon(Icons.arrow_downward_rounded), title: Text('Move down'))),
                                        const PopupMenuDivider(),
                                        const PopupMenuItem(value: 'cut', child: ListTile(dense: true, leading: Icon(Icons.content_cut_rounded), title: Text('Cut page'))),
                                        const PopupMenuItem(value: 'copy', child: ListTile(dense: true, leading: Icon(Icons.copy_rounded), title: Text('Copy page'))),
                                        PopupMenuItem(value: 'paste', enabled: _pageClipboard != null, child: const ListTile(dense: true, leading: Icon(Icons.content_paste_rounded), title: Text('Paste after'))),
                                        const PopupMenuItem(value: 'duplicate', child: ListTile(dense: true, leading: Icon(Icons.control_point_duplicate_rounded), title: Text('Duplicate'))),
                                        const PopupMenuItem(value: 'clear', child: ListTile(dense: true, leading: Icon(Icons.cleaning_services_outlined), title: Text('Clear page…'))),
                                        const PopupMenuItem(value: 'share', child: ListTile(dense: true, leading: Icon(Icons.share_outlined), title: Text('Share page'))),
                                        PopupMenuItem(
                                          value: 'bookmark',
                                          child: ListTile(
                                            dense: true,
                                            leading: Icon(_bookmarkedPages.contains(index + 1) ? Icons.bookmark_remove_outlined : Icons.bookmark_add_outlined),
                                            title: Text(_bookmarkedPages.contains(index + 1) ? 'Remove bookmark' : 'Bookmark page'),
                                          ),
                                        ),
                                        const PopupMenuItem(value: 'delete', child: ListTile(dense: true, leading: Icon(Icons.delete_outline_rounded), title: Text('Delete page…'))),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _addPage,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add Page'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
            Positioned.fill(child: _buildPageBackground(page, showPdf: _pdfBackgroundVisible, thumbnail: false)),
            Positioned.fill(
                child: IgnorePointer(
                  ignoring: !_textMode || page['locked'] == true,
                  child: Padding(
                    padding: const EdgeInsets.all(42),
                    child: QuillEditor(
                      focusNode: _quillFocus,
                      scrollController: _quillScroll,
                      controller: _quill,
                      config: const QuillEditorConfig(placeholder: ''),
                    ),
                  ),
                ),
              ),
            Positioned.fill(
                child: IgnorePointer(
                  ignoring: _textMode || page['locked'] == true,
                  child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _onPointerDown,
                onPointerMove: _onPointerMove,
                onPointerUp: _onPointerUp,
                onPointerCancel: _onPointerCancel,
                onPointerHover: (event) {
                  if (_tool == CanvasTool.eraser || _tool == CanvasTool.pixelEraser) {
                    _eraserCursor = event.localPosition;
                    final baseRadius = _tool == CanvasTool.pixelEraser ||
                            _settings.getString('eraserMode') == 'pixel'
                        ? 7.0
                        : math.max(18, _size * 2).toDouble();
                    _eraserCursorRadius = _pressureEraseRadius(event, baseRadius: baseRadius);
                    setState(() {});
                  }
                },
                child: CustomPaint(
                  painter: EditorV2InkPainter(
                    strokes: strokes,
                    liveStroke: live,
                    selectedStrokeIds: selected,
                    eraserCursor: _tool == CanvasTool.eraser || _tool == CanvasTool.pixelEraser ? _eraserCursor : null,
                    eraserRadius: _eraserCursorRadius,
                  ),
                  size: Size(_pageWidth, _pageHeight),
                ),
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
            if (page['locked'] == true)
              Positioned(
                top: 8,
                right: 8,
                child: IgnorePointer(
                  child: Material(
                    color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: .94),
                    borderRadius: BorderRadius.circular(8),
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lock_rounded, size: 15, color: Theme.of(context).colorScheme.onErrorContainer),
                          const SizedBox(width: 5),
                          Text('PAGE LOCKED', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onErrorContainer)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (_lassoRect != null && _selectionCount > 0 && _selectionBounds() != null) ...[
              Positioned.fromRect(
                rect: _selectionBounds()!,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onPanStart: (_) => _startSelectionTransform(resize: false),
                  onPanUpdate: (details) => _updateSelectionTransform(details.delta),
                  onPanEnd: (_) => _finishSelectionTransform(),
                  child: Container(color: Colors.transparent),
                ),
              ),
              Positioned(
                left: (_selectionBounds()!.center.dx + 14).clamp(0, _pageWidth - 24).toDouble(),
                top: (_selectionBounds()!.top - 12).clamp(0, _pageHeight - 24).toDouble(),
                child: Tooltip(
                  message: 'Duplicate selection',
                  child: GestureDetector(
                    onTap: () => _pasteStrokes(duplicate: true),
                    child: Material(
                      color: Theme.of(context).colorScheme.secondary,
                      shape: const CircleBorder(),
                      elevation: 3,
                      child: const SizedBox(width: 22, height: 22, child: Icon(Icons.control_point_duplicate_rounded, size: 13, color: Colors.white)),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: _selectionBounds()!.center.dx - 11,
                top: _selectionBounds()!.top - 12,
                child: Tooltip(
                  message: 'Drag to move selected content',
                  child: GestureDetector(
                    onPanStart: (_) => _startSelectionTransform(resize: false),
                    onPanUpdate: (details) => _updateSelectionTransform(details.delta),
                    onPanEnd: (_) => _finishSelectionTransform(),
                    child: Material(
                      color: Theme.of(context).colorScheme.primary,
                      shape: const CircleBorder(),
                      elevation: 3,
                      child: const SizedBox(width: 22, height: 22, child: Icon(Icons.open_with_rounded, size: 14, color: Colors.white)),
                    ),
                  ),
                ),
              ),
              ...<({Offset position, Offset direction, String label})>[
                (position: Offset(.5, 0), direction: Offset(0, -1), label: 'Resize from top'),
                (position: Offset(.5, 1), direction: Offset(0, 1), label: 'Resize from bottom'),
                (position: Offset(0, .5), direction: Offset(-1, 0), label: 'Resize from left'),
                (position: Offset(1, .5), direction: Offset(1, 0), label: 'Resize from right'),
                (position: Offset(0, 0), direction: Offset(-1, -1), label: 'Resize from top-left corner'),
                (position: Offset(1, 0), direction: Offset(1, -1), label: 'Resize from top-right corner'),
                (position: Offset(0, 1), direction: Offset(-1, 1), label: 'Resize from bottom-left corner'),
                (position: Offset(1, 1), direction: Offset(1, 1), label: 'Resize from bottom-right corner'),
              ].map((handle) {
                final bounds = _selectionBounds()!;
                return Positioned(
                  left: (bounds.left + bounds.width * handle.position.dx - 7.5).clamp(0, _pageWidth - 15).toDouble(),
                  top: (bounds.top + bounds.height * handle.position.dy - 7.5).clamp(0, _pageHeight - 15).toDouble(),
                  child: Tooltip(
                    message: handle.label,
                    child: GestureDetector(
                      onPanStart: (_) => _startSelectionTransform(resize: true, resizeDirection: handle.direction),
                      onPanUpdate: (details) => _updateSelectionTransform(details.delta),
                      onPanEnd: (_) => _finishSelectionTransform(),
                      child: Container(
                        width: 15,
                        height: 15,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          border: Border.all(color: Colors.white, width: 1.5),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
            if (_lassoRect != null && _selectionCount > 0 && _selectionBounds() != null)
              Positioned(
                left: math.min(_pageWidth - 38, math.max(4, _selectionBounds()!.right + 7)),
                top: _selectionBounds()!.top.clamp(4, _pageHeight - 340).toDouble(),
                child: Material(
                  elevation: 8,
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(visualDensity: VisualDensity.compact, constraints: const BoxConstraints.tightFor(width: 30, height: 28), tooltip: 'Convert selected handwriting to text', onPressed: _convertSelectedInkToText, icon: const Icon(Icons.text_fields_rounded, size: 16)),
                      IconButton(visualDensity: VisualDensity.compact, constraints: const BoxConstraints.tightFor(width: 30, height: 28), tooltip: 'Copy selection', onPressed: _copySelection, icon: const Icon(Icons.copy_rounded, size: 16)),
                      IconButton(visualDensity: VisualDensity.compact, constraints: const BoxConstraints.tightFor(width: 30, height: 28), tooltip: 'Cut selection', onPressed: _cutSelection, icon: const Icon(Icons.content_cut_rounded, size: 16)),
                      IconButton(visualDensity: VisualDensity.compact, constraints: const BoxConstraints.tightFor(width: 30, height: 28), tooltip: 'Paste copied selection', onPressed: _selectionClipboard == null ? null : () => _pasteStrokes(), icon: const Icon(Icons.content_paste_rounded, size: 16)),

                      IconButton(visualDensity: VisualDensity.compact, constraints: const BoxConstraints.tightFor(width: 30, height: 28), tooltip: 'Bring selection to front', onPressed: () => _changeSelectionLayer(bringToFront: true), icon: const Icon(Icons.flip_to_front_rounded, size: 16)),
                      IconButton(visualDensity: VisualDensity.compact, constraints: const BoxConstraints.tightFor(width: 30, height: 28), tooltip: 'Send selection to back', onPressed: () => _changeSelectionLayer(bringToFront: false), icon: const Icon(Icons.flip_to_back_rounded, size: 16)),
                      IconButton(visualDensity: VisualDensity.compact, constraints: const BoxConstraints.tightFor(width: 30, height: 28), tooltip: 'Delete selection', onPressed: _deleteSelection, icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Colors.redAccent)),
                    ]),
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
            panEnabled: _panMode && !_viewportLocked,
            scaleEnabled: !_viewportLocked,
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
            onInteractionUpdate: (_) => _showCanvasHud(),
            child: _buildPageSurface(),
          ),
        ),
      ),
    );
  }

  Widget _buildPageFooter() {
    final isBookmarked = _bookmarkedPages.contains(_page + 1);
    return Align(
      alignment: Alignment.centerRight,
      heightFactor: 1,
      child: Padding(
        padding: const EdgeInsets.only(right: 8, bottom: 4),
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          elevation: 2,
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            width: 38,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 30, height: 28),
                  tooltip: 'Previous page',
                  onPressed: _page > 0 ? () => _goToPage(_page - 1) : null,
                  icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 20),
                ),
                if (_settings.getBool('showPageNumbers'))
                  InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: _showPagePicker,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
                    child: Text(
                      '${_page + 1}\n/${_pages.length}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, height: 1.1),
                    ),
                  ),
                ),
                if (_studyRemaining > 0)
                  Tooltip(
                    message: 'Timer active • elapsed $_elapsedClock',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.timer_outlined, size: 13),
                        Text(_clock, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w800, fontFeatures: [ui.FontFeature.tabularFigures()])),
                      ]),
                    ),
                  ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 30, height: 28),
                  tooltip: isBookmarked ? 'Remove bookmark' : 'Bookmark page',
                  onPressed: _toggleBookmark,
                  icon: Icon(isBookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, size: 15),
                ),
                Tooltip(
                  message: _saving || _savePending ? 'Saving note' : 'Note saved locally',
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: _saving || _savePending
                        ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.7))
                        : const Icon(Icons.cloud_done_outlined, size: 13),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 30, height: 28),
                  tooltip: _page + 1 < _pages.length ? 'Next page' : 'Add next page',
                  onPressed: _page + 1 < _pages.length ? () => _goToPage(_page + 1) : _addPage,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                ),
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 30, height: 28),
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
                      case 'format':
                        unawaited(_showPageFormatSettings());
                      case 'clear':
                        unawaited(_clearPageWithConfirmation(_page));
                      case 'share':
                        unawaited(_sharePage(_page));
                      case 'delete':
                        unawaited(_confirmDeletePage(_page));
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
                    PopupMenuItem(value: 'background', child: Text('Change template')),
                    PopupMenuItem(value: 'format', child: Text('Page format & background')),
                    PopupMenuItem(value: 'preview', child: Text('Page preview / reorder')),
                    PopupMenuItem(value: 'clear', child: Text('Clear page…')),
                    PopupMenuItem(value: 'share', child: Text('Share page')),
                    PopupMenuDivider(),
                    PopupMenuItem(value: 'delete', child: Text('Delete page…')),
                  ],
                  icon: const Icon(Icons.more_vert_rounded, size: 16),
                ),
              ],
            ),
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
                  final isPdf = page['pdfLazyRender'] == true || (page['backgroundImage'] is String && (page['backgroundImage'] as String).isNotEmpty);
                  return Card(
                    key: ValueKey(page['id']?.toString() ?? 'page-$index'),
                    color: index == _page ? Theme.of(context).colorScheme.primaryContainer : null,
                    child: ListTile(
                      leading: SizedBox(
                        width: 42,
                        height: 52,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              _buildPageBackground(page, showPdf: true, thumbnail: true),
                              Align(
                                alignment: Alignment.bottomRight,
                                child: Container(
                                  margin: const EdgeInsets.all(2),
                                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: .88),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    '${index + 1}',
                                    style: const TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.black,
                                    ),
                                  ),
                                ),
                              ),
                              if (isPdf)
                                const Align(
                                  alignment: Alignment.topLeft,
                                  child: Padding(
                                    padding: EdgeInsets.all(2),
                                    child: Icon(Icons.picture_as_pdf_rounded, size: 10, color: Colors.redAccent),
                                  ),
                                ),
                            ],
                          ),
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
                                case 'clear':
                                  Navigator.pop(sheetContext);
                                  unawaited(_clearPageWithConfirmation(index));
                                case 'share':
                                  Navigator.pop(sheetContext);
                                  unawaited(_sharePage(index));
                                case 'delete':
                                  Navigator.pop(sheetContext);
                                  unawaited(_confirmDeletePage(index));
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'copy', child: Text('Copy page')),
                              PopupMenuItem(value: 'cut', child: Text('Cut page')),
                              PopupMenuItem(value: 'paste', child: Text('Paste copied page after this')),
                              PopupMenuItem(value: 'duplicate', child: Text('Duplicate page')),
                              PopupMenuItem(value: 'background', child: Text('Change page background')),
                              PopupMenuItem(value: 'clear', child: Text('Clear page…')),
                              PopupMenuItem(value: 'share', child: Text('Share page')),
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
      _clearSelectionIds();
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
    final titleBarToolKeys = _toolKeysForLocation('titleBar');
    final titleBarToolButtons = titleBarToolKeys
        .map((key) => _buildPlacedToolButton(key, 'titleBar'))
        .toList();
    return Scaffold(
      appBar: _fullScreenMode ? null : AppBar(
        leading: BackButton(
          onPressed: () async {
            await _flushSave();
            if (mounted) Navigator.maybePop(context);
          },
        ),
        titleSpacing: 0,
        toolbarHeight: 48,
        title: Row(
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 27, height: 30),
              tooltip: _showPagePreview ? 'Hide page sidebar' : 'Show page sidebar',
              onPressed: () {
                final next = !_showPagePreview;
                setState(() => _showPagePreview = next);
                unawaited(_settings.setBool('showPagePreview', next));
              },
              icon: Icon(
                _showPagePreview ? Icons.view_sidebar_rounded : Icons.view_sidebar_outlined,
                size: 18,
              ),
            ),
            if (!_settings.getBool('showUndoOnRight'))
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(width: 27, height: 30),
                tooltip: 'Undo',
                onPressed: _undoStack.isEmpty ? null : _undo,
                icon: const Icon(Icons.undo_rounded, size: 18),
              ),
            if (!_settings.getBool('showUndoOnRight'))
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(width: 27, height: 30),
                tooltip: 'Redo',
                onPressed: _redoStack.isEmpty ? null : _redo,
                icon: const Icon(Icons.redo_rounded, size: 18),
              ),
            SizedBox(
              width: math.min(280.0, MediaQuery.sizeOf(context).width * .38),
              child: DragTarget<Object>(
                onAcceptWithDetails: (details) => unawaited(
                  _moveDroppedTool(details.data, 'titleBar'),
                ),
                builder: (context, candidates, rejected) => TextField(
                  controller: _title,
                  maxLines: 1,
                  onChanged: (_) => _scheduleSave(),
                  onSubmitted: (_) => _save(force: true),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  decoration: InputDecoration(
                    hintText: 'Untitled note',
                    border: InputBorder.none,
                    filled: candidates.isNotEmpty,
                    fillColor: candidates.isNotEmpty
                        ? Theme.of(context).colorScheme.primaryContainer
                        : null,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                ),
              ),
            ),
            if (MediaQuery.sizeOf(context).width >= 640 && _hasPdfBackgroundPages)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  style: SegmentedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(42, 32),
                  ),
                  segments: const [
                    ButtonSegment<bool>(value: false, label: Text('Notes')),
                    ButtonSegment<bool>(value: true, label: Text('PDF')),
                  ],
                  selected: <bool>{_pdfBackgroundVisible},
                  onSelectionChanged: (selection) => _setPdfBackgroundVisible(selection.first),
                ),
              ),
          ],
        ),
        actions: [
          if (_settings.getBool('showUndoOnRight')) ...[
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Undo',
              onPressed: _undoStack.isEmpty ? null : _undo,
              icon: const Icon(Icons.undo_rounded, size: 18),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Redo',
              onPressed: _redoStack.isEmpty ? null : _redo,
              icon: const Icon(Icons.redo_rounded, size: 18),
            ),
          ],
          if (_saveError != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Save failed. Tap to retry. ${_saveError}',
              onPressed: () => _save(force: true),
              icon: Icon(Icons.cloud_off_rounded, color: Theme.of(context).colorScheme.error),
            ),
          if (_showNoteSwitcherInTitleBar)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Show tabs / switch open notes',
              onPressed: _toggleTabsBar,
              icon: Icon(_showTabsBar ? Icons.tab_rounded : Icons.tab_unselected_rounded),
            ),
          if (MediaQuery.sizeOf(context).width >= 500)
            PopupMenuButton<String>(
              tooltip: 'Page template and format',
              onSelected: (value) {
                if (value == 'template') {
                  unawaited(_chooseTemplate());
                } else if (value == 'format') {
                  unawaited(_showPageFormatSettings());
                } else {
                  unawaited(_showPageAndEditorSettings());
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'template', child: Text('Choose template (with preview)')),
                PopupMenuItem(value: 'format', child: Text('Dimensions, spacing & background')),
                PopupMenuItem(value: 'settings', child: Text('Template colors & editor settings')),
              ],
              icon: const Icon(Icons.grid_on_rounded),
            ),
          if (_settings.getBool('showTitleBarTimer'))
            IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Timer, alarm and stopwatch',
            onPressed: () => setState(() => _showFloatingTimer = true),
            icon: const Icon(Icons.timer_outlined, size: 19),
          ),
          if (_settings.getBool('showTitleBarSearch'))
            IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Google and web search',
            onPressed: () => unawaited(SnoteWebSearchPanel.show(context)),
            icon: const Icon(Icons.travel_explore_rounded, size: 19),
          ),
          if (titleBarToolButtons.isNotEmpty)
            SizedBox(
              width: math.min(
                MediaQuery.sizeOf(context).width * .32,
                titleBarToolButtons.length * 30.0,
              ).toDouble(),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(mainAxisSize: MainAxisSize.min, children: titleBarToolButtons),
              ),
            ),
          if (_hasPdfBackgroundPages && MediaQuery.sizeOf(context).width < 640)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: _pdfBackgroundVisible ? 'Switch to Notes layer' : 'Switch to PDF layer',
              onPressed: () => _setPdfBackgroundVisible(!_pdfBackgroundVisible),
              icon: Icon(_pdfBackgroundVisible ? Icons.edit_note_rounded : Icons.picture_as_pdf_rounded),
            ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Capture screenshot to canvas',
            onPressed: () => unawaited(_captureScreenToCanvas()),
            icon: const Icon(Icons.screenshot_monitor_rounded, size: 18),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: _fullScreenMode ? 'Exit full screen' : 'Enter full screen',
            onPressed: _toggleFullScreen,
            icon: Icon(_fullScreenMode ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded, size: 19),
          ),
          PopupMenuButton<String>(
            tooltip: 'Note and application controls',
            onSelected: _onMenuSelected,
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'fit', child: Text('Fit page to width')),
              const PopupMenuItem(value: 'fullscreen', child: Text('Toggle full screen')),
              PopupMenuItem(value: 'readingMode', child: Text(_readingMode ? 'Exit reading mode' : 'Reading mode')),
              const PopupMenuItem(value: 'image', child: Text('Insert image from file')),
              const PopupMenuItem(value: 'clipboardImage', child: Text('Paste screenshot from clipboard')),
              PopupMenuItem(value: 'pasteSelection', enabled: _selectionClipboard != null, child: const Text('Paste copied selection')),
              PopupMenuItem(value: 'clipboardHistory', enabled: _selectionClipboardHistory.isNotEmpty, child: const Text('Clipboard history (last 4)')),
              const PopupMenuItem(value: 'toolbarLayout', child: Text('Toolbar size, margins & padding')),
               const PopupMenuItem(value: 'smartPages', child: Text('Smart Pages library (200+)')),
               const PopupMenuItem(value: 'pageSettings', child: Text('Note page settings')),
              const PopupMenuItem(value: 'appSettings', child: Text('App settings')),
              const PopupMenuItem(value: 'template', child: Text('Page template')),
              PopupMenuItem(value: 'toggleNoteSwitcher', child: Text(_showNoteSwitcherInTitleBar ? 'Hide note switcher in title bar' : 'Show note switcher in title bar')),
              const PopupMenuItem(value: 'noteSwitcher', child: Text('Switch note')),
              const PopupMenuItem(value: 'calculator', child: Text('Scientific calculator')),
              if (_hasPdfBackgroundPages) ...[
                PopupMenuItem(value: 'notesLayer', child: Text(_pdfBackgroundVisible ? 'Switch to notes layer' : 'Notes layer active')),
                PopupMenuItem(value: 'pdfLayer', child: Text(_pdfBackgroundVisible ? 'PDF layer active' : 'Switch to PDF layer')),
              ],
              PopupMenuItem(
                value: 'togglePageLock',
                child: Text(_pageData['locked'] == true ? 'Unlock current page' : 'Lock current page'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'save', child: Text('Save note now')),
              const PopupMenuItem(value: 'export', child: Text('Export annotated document to PDF')),
              if (_hasPdfBackgroundPages)
                PopupMenuItem(
                  value: 'watermarkCover',
                  child: Text(_watermarkCoverMode
                      ? 'Exit watermark cover mode'
                      : 'Watermark cover / whiteout (source PDF unchanged)'),
                ),
            ],
            icon: const Icon(Icons.settings_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _locked && !_unlocked
              ? _buildLockedBody()
              : _loadError != null
                  ? _buildErrorBody()
                  : Column(
                      children: [
                        // Keep the canvas flush to the app bar while tabs are hidden.
                        // When enabled, the compact strip appears directly beneath the title bar.
                        if (_showTabsBar && !_fullScreenMode)
                          SizedBox(
                            height: 34,
                            child: _buildNoteTabs(),
                          ),
                        Expanded(child: _buildEditorLayout()),
                      ],
                    ),
    );
  }

  Widget _buildEditorLayout() {
    final sidebarWidth = MediaQuery.sizeOf(context).width >= 900 ? 216.0 : 172.0;
    final viewport = Expanded(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            left: _showPagePreview && !_fullScreenMode ? sidebarWidth + 8 : 0,
            child: _buildCanvas(),
          ),
          if (_showPagePreview && !_fullScreenMode)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: sidebarWidth,
              child: _buildPagePreviewSidebar(),
            ),
          if (!_readingMode && (_floatingToolbar || _fullScreenMode) && !_toolbarCollapsedToEdge)
            Positioned(
              left: _floatingOffset.dx.clamp(0, math.max(0, MediaQuery.sizeOf(context).width - 160)).toDouble(),
              top: _floatingOffset.dy.clamp(0, math.max(0, MediaQuery.sizeOf(context).height - 210)).toDouble(),
              child: GestureDetector(
                onPanUpdate: (details) => setState(() => _floatingOffset += details.delta),
                onPanEnd: (_) {
                  final screen = MediaQuery.sizeOf(context);
                  final x = _floatingOffset.dx;
                  final y = _floatingOffset.dy;
                  if (x <= 18) {
                    setState(() => _floatingOffset = Offset(0, y.clamp(0, screen.height - 120).toDouble()));
                    unawaited(_setToolbarDock('left'));
                  } else if (x >= screen.width - 100) {
                    setState(() => _floatingOffset = Offset(math.max(0, screen.width - 66), y.clamp(0, screen.height - 120).toDouble()));
                    unawaited(_setToolbarDock('right'));
                  } else if (y <= 18) {
                    setState(() => _floatingOffset = Offset(x.clamp(0, screen.width - 180).toDouble(), 0));
                    unawaited(_setToolbarDock('top'));
                  } else if (y >= screen.height - 130) {
                    setState(() => _floatingOffset = Offset(x.clamp(0, screen.width - 180).toDouble(), math.max(0, screen.height - 112)));
                    unawaited(_setToolbarDock('bottom'));
                  }
                },
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(12),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Builder(builder: (context) {
                        final vertical = _toolbarDock == 'left' || _toolbarDock == 'right';
                        final screen = MediaQuery.sizeOf(context);
                        return ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: vertical
                                ? _toolbarThickness.clamp(28.0, 96.0).toDouble()
                                : math.min(_compactFloatingToolbar ? _toolbarLength : 360.0, screen.width - 12),
                            maxHeight: vertical
                                ? math.min(_toolbarLength, screen.height - 24)
                                : _toolbarThickness.clamp(28.0, 96.0).toDouble(),
                          ),
                          child: _buildToolbar(vertical: vertical),
                        );
                      }),
                      Positioned(
                        right: -5,
                        bottom: -5,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanUpdate: (details) {
                            if (_toolbarDimensionsLocked) return;
                            final vertical = _toolbarDock == 'left' || _toolbarDock == 'right';
                            setState(() {
                              if (vertical) {
                                _toolbarThickness = (_toolbarThickness + details.delta.dx).clamp(28.0, 96.0).toDouble();
                                _toolbarLength = (_toolbarLength + details.delta.dy).clamp(180.0, 900.0).toDouble();
                              } else {
                                _toolbarLength = (_toolbarLength + details.delta.dx).clamp(180.0, 900.0).toDouble();
                                _toolbarThickness = (_toolbarThickness + details.delta.dy).clamp(28.0, 96.0).toDouble();
                              }
                            });
                          },
                          onPanEnd: (_) {
                            unawaited(_settings.setDouble('editorV2ToolbarLength', _toolbarLength));
                            unawaited(_settings.setDouble('editorV2ToolbarThickness', _toolbarThickness));
                          },
                          child: Material(
                            color: Theme.of(context).colorScheme.primary,
                            shape: const CircleBorder(),
                            elevation: 2,
                            child: const SizedBox(width: 18, height: 18, child: Icon(Icons.open_in_full_rounded, size: 11, color: Colors.white)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (!_readingMode && (_showFavoritesShowcase || _pencaseTools.isNotEmpty)) _buildFavoriteShowcase(),
          // Page navigation is now handled by the expanded page-preview sidebar.
          if (_fullScreenMode && !_readingMode && !_toolbarCollapsedToEdge)
            Positioned(
              top: 8,
              right: 52,
              child: Material(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                shape: const CircleBorder(),
                elevation: 5,
                child: IconButton(
                  tooltip: 'Collapse toolbar to screen edge',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    setState(() => _toolbarCollapsedToEdge = true);
                    unawaited(_settings.setBool('editorV2ToolbarCollapsed', true));
                  },
                  icon: const Icon(Icons.brush_rounded, size: 18),
                ),
              ),
            ),
          if (_fullScreenMode && _toolbarCollapsedToEdge)
            Positioned(
              right: 0,
              top: 96,
              child: Material(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(14)),
                elevation: 7,
                child: InkWell(
                  onTap: () {
                    setState(() => _toolbarCollapsedToEdge = false);
                    unawaited(_settings.setBool('editorV2ToolbarCollapsed', false));
                  },
                  child: const SizedBox(width: 30, height: 72, child: Tooltip(message: 'Expand toolbar', child: Icon(Icons.brush_rounded))),
                ),
              ),
            ),
          if (_calculatorVisible) _buildFloatingCalculator(),
          if (_showFloatingTimer)
            Positioned.fill(
              child: SnoteFloatingTimerPanel(
                onClose: () => setState(() => _showFloatingTimer = false),
              ),
            ),
          if (_showViewportHud || _viewportLocked)
            Positioned(
              top: 8,
              left: _showPagePreview && !_fullScreenMode ? sidebarWidth + 8 : 8,
              right: _fullScreenMode ? 54 : 8,
              child: Center(
                child: Material(
                  color: const Color(0xe91b2430),
                  elevation: 8,
                  borderRadius: BorderRadius.circular(28),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(_viewportLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
                        size: 15, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        _viewportLocked ? 'Canvas locked' : 'Canvas • ${(_transform.value.getMaxScaleOnAxis() * 100).round()}%',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 3),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints.tightFor(width: 30, height: 30),
                        tooltip: _viewportLocked ? 'Unlock canvas' : 'Lock canvas',
                        onPressed: _toggleCanvasLock,
                        icon: Icon(_viewportLocked ? Icons.lock_open_rounded : Icons.lock_rounded,
                          color: Colors.white, size: 17),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints.tightFor(width: 30, height: 30),
                        tooltip: 'Reset location / fit page',
                        onPressed: _resetCanvasView,
                        icon: const Icon(Icons.center_focus_strong_rounded, color: Colors.white, size: 17),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          if (_readingMode)
            Positioned(
              left: 12,
              right: 12,
              top: 8,
              child: SafeArea(
                child: Center(
                  child: Material(
                    elevation: 6,
                    borderRadius: BorderRadius.circular(28),
                    color: Theme.of(context).colorScheme.surface.withValues(alpha: .94),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(tooltip: 'Previous page', onPressed: _page > 0 ? () => _goToPage(_page - 1) : null, icon: const Icon(Icons.chevron_left_rounded)),
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text('${_page + 1} / ${_pages.length}', style: const TextStyle(fontWeight: FontWeight.w700))),
                      IconButton(tooltip: 'Next page', onPressed: _page + 1 < _pages.length ? () => _goToPage(_page + 1) : null, icon: const Icon(Icons.chevron_right_rounded)),
                      IconButton(tooltip: 'Exit reading mode', onPressed: () => _onMenuSelected('readingMode'), icon: const Icon(Icons.close_rounded)),
                    ]),
                  ),
                ),
              ),
            ),
          if (_fullScreenMode && !_readingMode)
            Positioned(
              right: 8,
              top: 8,
              child: Material(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                shape: const CircleBorder(),
                elevation: 5,
                child: IconButton(
                  tooltip: 'Exit full screen',
                  onPressed: _toggleFullScreen,
                  icon: const Icon(Icons.fullscreen_exit_rounded),
                ),
              ),
            ),
        ],
      ),
    );

    final canvasWithFooter = Column(children: [viewport]);

    if (_fullScreenMode) {
      return canvasWithFooter;
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
                width: 32,
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
                width: 34,
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
    _viewportHudTimer?.cancel();
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
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
    for (final documentFuture in _pdfDocumentFutures.values) {
      unawaited(documentFuture.then<void>((document) => document.close()).catchError((Object error) {
        debugPrint('[Snote][EditorV2] PDF document cache cleanup failed: $error');
      }));
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
  final ValueChanged<Size> onResize;
  final VoidCallback onClose;
  final ValueChanged<Offset> onMove;
  final VoidCallback onCollapse;

  const _ScientificCalculatorDialog({
    required this.initialWidth,
    required this.initialHeight,
    required this.onResize,
    required this.onClose,
    required this.onMove,
    required this.onCollapse,
  });

  @override
  State<_ScientificCalculatorDialog> createState() => _ScientificCalculatorDialogState();
}

class _ScientificCalculatorDialogState extends State<_ScientificCalculatorDialog> {
  final TextEditingController _expression = TextEditingController();
  String _answer = '0';
  String? _error;
  bool _degrees = true;
  bool _collapsed = false;
  double _width = 330;
  double _height = 465;

  static const List<String> _keys = <String>[
    'sin', 'cos', 'tan', '√',
    'ln', 'log', 'π', '^',
    '(', ')', '⌫', 'AC',
    '7', '8', '9', '÷',
    '4', '5', '6', '×',
    '1', '2', '3', '−',
    '0', '.', 'e', '+',
    'C', 'abs', '=', '%',
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
        if (text.isNotEmpty) _expression.text = text.substring(0, text.length - 1);
        _expression.selection = TextSelection.collapsed(offset: _expression.text.length);
        return;
      }
      if (key == '=') {
        try {
          final value = _ScientificExpressionParser(_expression.text, degrees: _degrees).parse();
          if (!value.isFinite) throw const FormatException('Result is not finite');
          _answer = value.abs() < 1e-12 ? '0' : _format(value);
        } catch (_) {
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
        'sin' || 'cos' || 'tan' || 'ln' || 'log' || 'abs' => '$key(',
        '%' => '/100',
        _ => key,
      };
      final selection = _expression.selection;
      final text = _expression.text;
      final start = selection.isValid ? selection.start : text.length;
      final end = selection.isValid ? selection.end : text.length;
      _expression.value = TextEditingValue(
        text: text.replaceRange(start, end, insert),
        selection: TextSelection.collapsed(offset: start + insert.length),
      );
    });
  }

  String _format(double value) {
    final fixed = value.toStringAsPrecision(10);
    if (!fixed.contains('.')) return fixed;
    return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  @override
  void dispose() {
    _expression.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final width = _width.clamp(270.0, math.max(270.0, screen.width - 16)).toDouble();
    final height = _height.clamp(360.0, math.max(360.0, screen.height - 32)).toDouble();
    final scheme = Theme.of(context).colorScheme;
    if (_collapsed) {
      final dockLeft = screen.width / 2 > _width / 2;
      return GestureDetector(
        onTap: () => setState(() => _collapsed = false),
        onPanUpdate: (details) => widget.onMove(details.delta),
        child: Material(
          color: scheme.primaryContainer,
          elevation: 8,
          borderRadius: BorderRadius.horizontal(
            left: Radius.circular(dockLeft ? 0 : 12),
            right: Radius.circular(dockLeft ? 12 : 0),
          ),
          child: SizedBox(width: 28, height: 76, child: Icon(dockLeft ? Icons.chevron_right_rounded : Icons.chevron_left_rounded)),
        ),
      );
    }
    return SizedBox(
      width: width,
      height: height,
      child: Material(
        color: scheme.surface,
        elevation: 12,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            GestureDetector(
              onPanUpdate: (details) => widget.onMove(details.delta),
              child: Container(
                color: scheme.primaryContainer,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.drag_indicator_rounded, size: 18),
                    const SizedBox(width: 4),
                    const Expanded(child: Text('Calculator', style: TextStyle(fontWeight: FontWeight.w800))),
                    IconButton(
                      tooltip: 'Collapse calculator to screen edge',
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints.tightFor(width: 30, height: 30),
                      onPressed: () {
                        widget.onCollapse();
                        setState(() => _collapsed = true);
                      },
                      icon: const Icon(Icons.calculate_rounded, size: 18),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _degrees = !_degrees),
                      child: Text(_degrees ? 'DEG' : 'RAD'),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints.tightFor(width: 30, height: 30),
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _expression,
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, fontFeatures: [ui.FontFeature.tabularFigures()]),
                    decoration: const InputDecoration(hintText: '0', border: InputBorder.none, isDense: true),
                    onSubmitted: (_) => _press('='),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      _error ?? _answer,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800, color: _error == null ? scheme.primary : scheme.error, fontFeatures: const [ui.FontFeature.tabularFigures()]),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: GridView.builder(
                  physics: const ClampingScrollPhysics(),
                  itemCount: _keys.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    crossAxisSpacing: 5,
                    mainAxisSpacing: 5,
                    childAspectRatio: 1.3,
                  ),
                  itemBuilder: (_, index) {
                    final key = _keys[index];
                    final isOperator = const {'÷', '×', '−', '+', '^', '=', '%'}.contains(key);
                    final isFunction = const {'sin','cos','tan','√','ln','log','π','abs'}.contains(key);
                    final isClear = const {'C','AC','⌫'}.contains(key);
                    return FilledButton.tonal(
                      style: FilledButton.styleFrom(
                        padding: EdgeInsets.zero,
                        backgroundColor: isOperator
                            ? scheme.primaryContainer
                            : isFunction
                                ? scheme.secondaryContainer
                                : isClear
                                    ? scheme.errorContainer.withValues(alpha: .7)
                                    : scheme.surfaceContainerHigh,
                        foregroundColor: scheme.onSurface,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                      ),
                      onPressed: () => _press(key),
                      child: Text(key, style: TextStyle(fontSize: key.length > 2 ? 13 : 18, fontWeight: FontWeight.w700)),
                    );
                  },
                ),
              ),
            ),
            GestureDetector(
              onPanUpdate: (details) {
                _width = (_width + details.delta.dx).clamp(270.0, math.max(270.0, screen.width - 16)).toDouble();
                _height = (_height + details.delta.dy).clamp(360.0, math.max(360.0, screen.height - 32)).toDouble();
                widget.onResize(Size(_width, _height));
                setState(() {});
              },
              child: Container(
                height: 18,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 5),
                child: Icon(Icons.drag_handle_rounded, size: 17, color: scheme.outline),
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

class _ToolPickerChoice {
  final CanvasTool tool;
  final bool configure;
  final Offset? anchor;
  const _ToolPickerChoice(this.tool, {this.configure = false, this.anchor});
}

class _EditorV2ShapePreviewPainter extends CustomPainter {
  final String shape;
  final Color color;

  const _EditorV2ShapePreviewPainter({
    required this.shape,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: size.width * .72,
      height: size.height * .72,
    );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    Path polygon(List<Offset> points) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      path.close();
      return path;
    }

    void drawArrowHead(Offset from, Offset to) {
      final direction = to - from;
      if (direction.distance < 1) return;
      final unit = direction / direction.distance;
      final normal = Offset(-unit.dy, unit.dx);
      final base = to - unit * 5;
      canvas.drawLine(to, base + normal * 3, paint);
      canvas.drawLine(to, base - normal * 3, paint);
    }

    final name = shape.toLowerCase();
    if (name.contains('doublearrow')) {
      final a = Offset(bounds.left, bounds.center.dy);
      final b = Offset(bounds.right, bounds.center.dy);
      canvas.drawLine(a, b, paint);
      drawArrowHead(a, b);
      drawArrowHead(b, a);
    } else if (name.contains('arrow') || name == 'vectorarrow') {
      final a = Offset(bounds.left, bounds.bottom);
      final b = Offset(bounds.right, bounds.top);
      canvas.drawLine(a, b, paint);
      drawArrowHead(a, b);
    } else if (name.contains('line') || name == 'divider' || name == 'raydiagram') {
      canvas.drawLine(
        Offset(bounds.left, bounds.bottom),
        Offset(bounds.right, bounds.top),
        paint,
      );
    } else if (name.contains('roundedrectangle') || name == 'flowchartterminator') {
      canvas.drawRRect(
        RRect.fromRectAndRadius(bounds, const Radius.circular(4)),
        paint,
      );
    } else if (name.contains('rectangle') || name == 'flowchartprocess' || name == 'cuboid') {
      canvas.drawRect(bounds, paint);
    } else if (name.contains('ellipse') || name == 'circle' || name == 'sphere' || name == 'flowchartconnector') {
      canvas.drawOval(bounds, paint);
    } else if (name.contains('triangle') || name == 'pyramid') {
      canvas.drawPath(polygon(<Offset>[
        Offset(bounds.center.dx, bounds.top),
        bounds.bottomRight,
        bounds.bottomLeft,
      ]), paint);
    } else if (name.contains('diamond') || name == 'flowchartdecision') {
      canvas.drawPath(polygon(<Offset>[
        Offset(bounds.center.dx, bounds.top),
        bounds.centerRight,
        Offset(bounds.center.dx, bounds.bottom),
        bounds.centerLeft,
      ]), paint);
    } else if (name.contains('parallelogram') || name == 'flowchartinputoutput') {
      canvas.drawPath(polygon(<Offset>[
        Offset(bounds.left + bounds.width * .2, bounds.top),
        bounds.topRight,
        Offset(bounds.right - bounds.width * .2, bounds.bottom),
        bounds.bottomLeft,
      ]), paint);
    } else if (name.contains('star')) {
      final points = List<Offset>.generate(10, (index) {
        final radius = index.isEven ? .48 : .22;
        final angle = -math.pi / 2 + index * math.pi / 5;
        return Offset(
          bounds.center.dx + math.cos(angle) * bounds.width * radius,
          bounds.center.dy + math.sin(angle) * bounds.height * radius,
        );
      });
      canvas.drawPath(polygon(points), paint);
    } else if (name.contains('hexagon') ||
        name.contains('pentagon') ||
        name.contains('octagon') ||
        name.contains('nonagon') ||
        name.contains('decagon') ||
        name.contains('custompolygon')) {
      final sides = name.contains('pentagon')
          ? 5
          : name.contains('octagon')
              ? 8
              : name.contains('nonagon')
                  ? 9
                  : name.contains('decagon')
                      ? 10
                      : 6;
      final points = List<Offset>.generate(sides, (index) {
        final angle = -math.pi / 2 + index * math.pi * 2 / sides;
        return Offset(
          bounds.center.dx + math.cos(angle) * bounds.width * .48,
          bounds.center.dy + math.sin(angle) * bounds.height * .48,
        );
      });
      canvas.drawPath(polygon(points), paint);
    } else if (name.contains('graph') || name.contains('chart') || name.contains('plot')) {
      canvas.drawLine(bounds.bottomLeft, bounds.topLeft, paint);
      canvas.drawLine(bounds.bottomLeft, bounds.bottomRight, paint);
      final curve = Path()
        ..moveTo(bounds.left + bounds.width * .12, bounds.bottom - bounds.height * .15)
        ..lineTo(bounds.left + bounds.width * .38, bounds.top + bounds.height * .45)
        ..lineTo(bounds.left + bounds.width * .58, bounds.top + bounds.height * .58)
        ..lineTo(bounds.right - bounds.width * .08, bounds.top + bounds.height * .14);
      canvas.drawPath(curve, paint);
    } else {
      // Science and math tools without a dedicated pictogram still get a
      // visible preview, rather than a blank card.
      canvas.drawRect(bounds, paint);
      canvas.drawLine(
        Offset(bounds.left, bounds.bottom),
        Offset(bounds.right, bounds.top),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EditorV2ShapePreviewPainter oldDelegate) =>
      oldDelegate.shape != shape || oldDelegate.color != color;
}

class _EditorV2ToolPicker extends StatefulWidget {
  final CanvasTool selected;
  final String? initialCategory;
  final Set<String> favoriteShapes;
  final ValueChanged<Set<String>> onFavoriteShapesChanged;
  const _EditorV2ToolPicker({
    required this.selected,
    this.initialCategory,
    required this.favoriteShapes,
    required this.onFavoriteShapesChanged,
  });

  @override
  State<_EditorV2ToolPicker> createState() => _EditorV2ToolPickerState();
}

class _EditorV2ToolPickerState extends State<_EditorV2ToolPicker> {
  final TextEditingController _search = TextEditingController();
  final Set<String> _favoriteShapes = <String>{};
  String _category = 'All tools';

  @override
  void initState() {
    super.initState();
    _favoriteShapes.addAll(widget.favoriteShapes);
    if (widget.initialCategory != null) _category = widget.initialCategory!;
  }

  void _toggleShapeFavorite(CanvasTool tool) {
    if (!tool.isShape) return;
    setState(() {
      if (!_favoriteShapes.add(tool.name)) {
        _favoriteShapes.remove(tool.name);
      }
    });
    widget.onFavoriteShapesChanged(Set<String>.from(_favoriteShapes));
  }
  Offset _lastGlobalPointer = Offset.zero;

  static const Set<String> _mathTools = <String>{
    'unitCircle', 'cubicGraph', 'exponentialGraph', 'logarithmicGraph',
    'tangentGraph', 'ellipseAxes', 'vectorField', 'polarGraph',
    'cartesianPlane', 'coordinateAxes', 'parabola', 'sineWave', 'angle',
    'vectorArrow', 'projectilePath', 'numberLine', 'equalsSign', 'notEqualSign',
    'approximateEqual', 'greaterThanSign', 'lessThanSign', 'plusMinus',
    'infinitySymbol', 'integralSymbol', 'sigmaSymbol', 'deltaSymbol', 'thetaSymbol',
    'omegaSymbol', 'squareRootSymbol', 'fractionBar', 'matrixGrid', 'summationSymbol',
    'derivativeSymbol', 'coordinatePoint', 'linearGraph', 'circleGraph', 'scatterPlot',
    'lineChart', 'areaChart', 'donutChart', 'stackedBarChart', 'networkGraph', 'vennDiagram',
  };
  static const Set<String> _chartTools = <String>{
    'histogram', 'barChart', 'pieChart', 'flowchartTerminator',
    'flowchartProcess', 'flowchartDecision', 'flowchartInputOutput',
    'flowchartDocument', 'flowchartDatabase', 'flowchartConnector',
    'timeline', 'tableGrid', 'checklist', 'flowchartPreparation',
    'flowchartManualInput', 'flowchartDelay', 'flowchartOffPage',
    'documentStack', 'databaseCylinder', 'serverRack', 'networkNode', 'networkLink',
  };
  static const Set<String> _physicsTools = <String>{
    'rayDiagram', 'convexLens', 'concaveLens', 'planeMirror',
    'forceDiagram', 'pulley', 'spring', 'lever', 'inclinedPlane',
    'gear', 'magnet', 'thermometer', 'stopwatch', 'waveform',
    'gearTrain', 'pendulum', 'weightSymbol', 'electricField', 'magneticField',
    'waveFront', 'photonSymbol',
  };
  static const Set<String> _circuitTools = <String>{
    'circuitResistor', 'circuitBattery', 'capacitor', 'circuitSwitch', 'circuitLamp',
    'wifiSymbol', 'batterySymbol', 'groundSymbol', 'voltageSource', 'currentSource',
    'inductorSymbol', 'diodeSymbol', 'transistorSymbol', 'logicAnd', 'logicOr',
    'logicNot', 'logicXor', 'cloudSymbol',
  };
  static const Set<String> _chemistryTools = <String>{
    'atom', 'molecule', 'benzeneRing', 'beaker', 'testTube',
    'conicalFlask', 'orbital', 'ionSymbol', 'ionicBond', 'covalentBond',
    'moleculeChain', 'crystalLattice', 'organicChain', 'aminoAcid', 'proteinSymbol',
  };
  static const Set<String> _biologyTools = <String>{
    'animalCell', 'plantCell', 'dnaHelix', 'neuron', 'leaf', 'microscope',
    'cellMembrane', 'chloroplast', 'mitochondrion', 'ribosome', 'brainIcon',
    'heartOrgan', 'lungIcon', 'bloodCell', 'bacteriaIcon', 'virusIcon',
    'flowerIcon', 'treeIcon', 'atomNucleus', 'electronOrbit',
  };
  static const Set<String> _geometryTools = <String>{
    'octagon', 'nonagon', 'decagon', 'heptagon', 'hexagram', 'pentagram',
    'arrowUp', 'arrowDown', 'arrowLeft', 'arrowRight', 'doubleArrow',
    'curvedArrow', 'zigzag', 'lightningBolt', 'crescentMoon', 'sunSymbol',
    'doubleChevron', 'chevron', 'bracketLeft', 'bracketRight', 'braceLeft',
    'braceRight',
  };
  static const Set<String> _instrumentTools = <String>{
    'ruler', 'compass', 'protractor', 'divider', 'dashedLine', 'dottedLine',
  };

  String _categoryOf(CanvasTool tool) {
    if (tool.isPen) return 'Pens';
    if (const {'eraser', 'pixelEraser', 'lasso', 'fill'}.contains(tool.name)) return 'Editing';
    if (_geometryTools.contains(tool.name)) return 'Geometry & symbols';
    if (_mathTools.contains(tool.name)) return 'Math & graphs';
    if (_chartTools.contains(tool.name)) return 'Charts & flowcharts';
    if (_physicsTools.contains(tool.name)) return 'Physics & mechanics';
    if (_circuitTools.contains(tool.name)) return 'Electrical circuits';
    if (_chemistryTools.contains(tool.name)) return 'Chemistry';
    if (_biologyTools.contains(tool.name)) return 'Biology';
    if (_instrumentTools.contains(tool.name)) return 'Rulers & measuring';
    if (tool == CanvasTool.sticker) return 'Stickers';
    return 'Shapes & diagrams';
  }

  IconData _pickerIcon(CanvasTool tool) {
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
      CanvasTool.fill => Icons.format_color_fill_rounded,
      CanvasTool.sticker => Icons.emoji_emotions_outlined,
      CanvasTool.ruler => Icons.straighten_rounded,
      CanvasTool.compass || CanvasTool.protractor => Icons.architecture_rounded,
      CanvasTool.divider => Icons.vertical_distribute_rounded,
      _ when tool.name.toLowerCase().contains('chart') ||
          tool.name == 'histogram' ||
          tool.name == 'pieChart' => Icons.bar_chart_rounded,
      _ when tool.name.toLowerCase().contains('cell') ||
          tool.name.toLowerCase().contains('dna') ||
          tool.name.toLowerCase().contains('neuron') => Icons.biotech_rounded,
      _ when tool.name.toLowerCase().contains('circuit') ||
          tool.name.toLowerCase().contains('voltage') ||
          tool.name.toLowerCase().contains('transistor') => Icons.electrical_services_rounded,
      _ when tool.name.toLowerCase().contains('flowchart') => Icons.account_tree_rounded,
      _ => Icons.category_outlined,
    };
  }

  Widget _toolPreview(CanvasTool tool) {
    final scheme = Theme.of(context).colorScheme;
    if (tool.isShape) {
      return SizedBox(
        width: 42,
        height: 26,
        child: CustomPaint(
          painter: _EditorV2ShapePreviewPainter(
            shape: tool.name,
            color: scheme.primary,
          ),
        ),
      );
    }
    return Icon(_pickerIcon(tool), size: 23, color: scheme.primary);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = <String>[
      'All tools', 'Favorites', 'Pens', 'Editing', 'Shapes & diagrams', 'Geometry & symbols',
      'Rulers & measuring', 'Math & graphs', 'Charts & flowcharts',
      'Physics & mechanics', 'Electrical circuits', 'Chemistry', 'Biology', 'Stickers',
    ];
    final query = _search.text.trim().toLowerCase();
    final items = CanvasTool.values.where((tool) {
      final matchesQuery = query.isEmpty ||
          tool.label.toLowerCase().contains(query) ||
          tool.name.toLowerCase().contains(query);
      final matchesCategory = _category == 'All tools' ||
          (_category == 'Favorites'
              ? tool.isShape && _favoriteShapes.contains(tool.name)
              : _categoryOf(tool) == _category);
      return tool != CanvasTool.pixelEraser && matchesQuery && matchesCategory;
    }).toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 4, 12, 12 + MediaQuery.viewInsetsOf(context).bottom),
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
              height: MediaQuery.sizeOf(context).height * .54,
              child: GridView.builder(
                itemCount: items.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: MediaQuery.sizeOf(context).width >= 1100
                      ? 5
                      : MediaQuery.sizeOf(context).width >= 700
                          ? 4
                          : 3,
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 6,
                  childAspectRatio: 1.7,
                ),
                itemBuilder: (_, index) {
                  final tool = items[index];
                  final selected = tool == widget.selected;
                  return InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTapDown: (details) => _lastGlobalPointer = details.globalPosition,
                    onDoubleTap: () => Navigator.pop(
                      context,
                      _ToolPickerChoice(tool, configure: true, anchor: _lastGlobalPointer),
                    ),
                    onTap: () => Navigator.pop(context, _ToolPickerChoice(tool)),
                    child: Ink(
                      decoration: BoxDecoration(
                        color: selected ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: selected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.all(5),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _toolPreview(tool),
                                  const SizedBox(height: 4),
                                  Text(
                                    tool.label,
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (tool.isShape)
                            Positioned(
                              top: 0,
                              right: 0,
                              width: 28,
                              height: 28,
                              child: IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                tooltip: _favoriteShapes.contains(tool.name)
                                    ? 'Remove shape from favorites'
                                    : 'Add shape to favorites',
                                onPressed: () => _toggleShapeFavorite(tool),
                                icon: Icon(
                                  _favoriteShapes.contains(tool.name)
                                      ? Icons.star_rounded
                                      : Icons.star_border_rounded,
                                  size: 16,
                                  color: _favoriteShapes.contains(tool.name)
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 4),
            const Text('Tap to choose • double-tap to configure this tool', style: TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _FormattedTextEditingController extends TextEditingController {
  _FormattedTextEditingController({super.text}) : _lastText = text ?? '';

  String _lastText;
  List<Map<String, Object?>> formatRanges = <Map<String, Object?>>[];

  void reconcileText(String nextText) {
    final oldText = _lastText;
    if (oldText == nextText) return;
    var prefix = 0;
    final sharedLength = math.min(oldText.length, nextText.length);
    while (prefix < sharedLength && oldText.codeUnitAt(prefix) == nextText.codeUnitAt(prefix)) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < oldText.length - prefix &&
        suffix < nextText.length - prefix &&
        oldText.codeUnitAt(oldText.length - 1 - suffix) ==
            nextText.codeUnitAt(nextText.length - 1 - suffix)) {
      suffix++;
    }
    final oldChangedEnd = oldText.length - suffix;
    final delta = nextText.length - oldText.length;
    formatRanges = formatRanges.map((range) {
      final updated = Map<String, Object?>.from(range);
      var start = (updated['start'] as num?)?.toInt() ?? 0;
      var end = (updated['end'] as num?)?.toInt() ?? start;
      if (start >= oldChangedEnd) {
        start += delta;
        end += delta;
      } else if (end > prefix) {
        end += delta;
      }
      start = start.clamp(0, nextText.length).toInt();
      end = end.clamp(start, nextText.length).toInt();
      updated['start'] = start;
      updated['end'] = end;
      return updated;
    }).where((range) =>
      ((range['end'] as num?)?.toInt() ?? 0) >
      ((range['start'] as num?)?.toInt() ?? 0)
    ).toList();
    _lastText = nextText;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final text = value.text;
    if (text.isEmpty || formatRanges.isEmpty) {
      return TextSpan(text: text, style: style);
    }
    final boundaries = <int>{0, text.length};
    for (final range in formatRanges) {
      final start = ((range['start'] as num?)?.toInt() ?? 0).clamp(0, text.length).toInt();
      final end = ((range['end'] as num?)?.toInt() ?? start).clamp(start, text.length).toInt();
      if (end > start) {
        boundaries.add(start);
        boundaries.add(end);
      }
    }
    final points = boundaries.toList()..sort();
    final spans = <InlineSpan>[];
    for (var i = 0; i < points.length - 1; i++) {
      final start = points[i];
      final end = points[i + 1];
      if (end <= start) continue;
      bool? bold;
      bool? italic;
      bool? underline;
      bool? strike;
      for (final range in formatRanges) {
        final rangeStart = (range['start'] as num?)?.toInt() ?? 0;
        final rangeEnd = (range['end'] as num?)?.toInt() ?? rangeStart;
        if (rangeStart <= start && rangeEnd >= end) {
          if (range.containsKey('bold')) bold = range['bold'] == true;
          if (range.containsKey('italic')) italic = range['italic'] == true;
          if (range.containsKey('underline')) underline = range['underline'] == true;
          if (range.containsKey('strikethrough')) strike = range['strikethrough'] == true;
        }
      }
      final decorations = <TextDecoration>[
        if (underline == true) TextDecoration.underline,
        if (strike == true) TextDecoration.lineThrough,
      ];
      final segmentStyle = (style ?? const TextStyle()).merge(TextStyle(
        fontWeight: bold == null ? null : (bold ? FontWeight.bold : FontWeight.normal),
        fontStyle: italic == null ? null : (italic ? FontStyle.italic : FontStyle.normal),
        decoration: underline == null && strike == null
            ? null
            : TextDecoration.combine(decorations),
      ));
      spans.add(TextSpan(text: text.substring(start, end), style: segmentStyle));
    }
    return TextSpan(style: style, children: spans);
  }
}

class _CaptureRegionSelector extends StatefulWidget {
  const _CaptureRegionSelector();

  @override
  State<_CaptureRegionSelector> createState() => _CaptureRegionSelectorState();
}

class _CaptureRegionSelectorState extends State<_CaptureRegionSelector> {
  Offset? _start;
  Offset? _current;
  Rect? _resizeOrigin;
  String? _activeResizeHandle;

  Rect get _selection {
    final start = _start;
    final current = _current;
    if (start == null || current == null) return Rect.zero;
    return Rect.fromPoints(start, current);
  }

  void _beginResize(String handle) {
    _resizeOrigin = _selection;
    _activeResizeHandle = handle;
  }

  void _updateResize(DragUpdateDetails details) {
    final origin = _resizeOrigin;
    final handle = _activeResizeHandle;
    if (origin == null || handle == null) return;
    final dx = details.delta.dx;
    final dy = details.delta.dy;
    var left = origin.left;
    var top = origin.top;
    var right = origin.right;
    var bottom = origin.bottom;
    if (handle.contains('l')) left = (left + dx).clamp(0.0, right - 12).toDouble();
    if (handle.contains('r')) right = (right + dx).clamp(left + 12, MediaQuery.sizeOf(context).width).toDouble();
    if (handle.contains('t')) top = (top + dy).clamp(0.0, bottom - 12).toDouble();
    if (handle.contains('b')) bottom = (bottom + dy).clamp(top + 12, MediaQuery.sizeOf(context).height).toDouble();
    setState(() {
      _start = Offset(left, top);
      _current = Offset(right, bottom);
    });
    _resizeOrigin = Rect.fromLTRB(left, top, right, bottom);
  }

  List<Widget> _resizeHandles(Rect selection, Color color) {
    const points = <({String key, double x, double y})>[
      (key: 'tl', x: 0, y: 0), (key: 't', x: .5, y: 0),
      (key: 'tr', x: 1, y: 0), (key: 'r', x: 1, y: .5),
      (key: 'br', x: 1, y: 1), (key: 'b', x: .5, y: 1),
      (key: 'bl', x: 0, y: 1), (key: 'l', x: 0, y: .5),
    ];
    return points.map((point) {
      final center = Offset(selection.left + selection.width * point.x, selection.top + selection.height * point.y);
      return Positioned(
        left: center.dx - 9,
        top: center.dy - 9,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) => _beginResize(point.key),
          onPanUpdate: _updateResize,
          onPanEnd: (_) { _resizeOrigin = null; _activeResizeHandle = null; },
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: color,
              border: Border.all(color: Colors.white, width: 1.5),
              borderRadius: BorderRadius.circular(4),
              boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x55000000), blurRadius: 3)],
            ),
          ),
        ),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final selection = _selection;
    final valid = selection.width >= 12 && selection.height >= 12;
    return Material(
      color: Colors.black.withValues(alpha: .52),
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (details) => setState(() {
              _start = details.localPosition;
              _current = details.localPosition;
            }),
            onPanUpdate: (details) => setState(() => _current = details.localPosition),
            onPanEnd: (_) => setState(() {}),
            child: CustomPaint(
              painter: _CaptureRegionPainter(selection: selection),
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: 16,
            top: 18,
            right: 16,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  child: Text(
                    'Drag to select the screenshot area',
                    style: TextStyle(color: colors.onSurface, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            bottom: 20,
            child: FilledButton.tonal(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 20,
            child: FilledButton.icon(
              onPressed: valid ? () => Navigator.of(context).pop(selection) : null,
              icon: const Icon(Icons.crop_free_rounded),
              label: const Text('Capture selection'),
            ),
          ),
          if (valid) ..._resizeHandles(selection, const Color(0xff168d75)),
          if (valid)
            Positioned(
              left: selection.left.clamp(0.0, MediaQuery.sizeOf(context).width - 120).toDouble(),
              top: (selection.top - 34).clamp(8.0, MediaQuery.sizeOf(context).height - 40).toDouble(),
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Text(
                      '${selection.width.round()} × ${selection.height.round()}',
                      style: TextStyle(color: colors.onSurface, fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CaptureRegionPainter extends CustomPainter {
  final Rect selection;

  const _CaptureRegionPainter({required this.selection});

  @override
  void paint(Canvas canvas, Size size) {
    if (selection.isEmpty) return;
    final border = Paint()
      ..color = const Color(0xff66e0c2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final fill = Paint()..color = const Color(0x2266e0c2);
    final rect = selection.intersect(Offset.zero & size);
    canvas.drawRect(rect, fill);
    canvas.drawRect(rect, border);
    const handleSize = 8.0;
    final handlePaint = Paint()..color = const Color(0xff66e0c2);
    for (final point in <Offset>[
      rect.topLeft, rect.topRight, rect.bottomLeft, rect.bottomRight,
    ]) {
      canvas.drawRect(
        Rect.fromCenter(center: point, width: handleSize, height: handleSize),
        handlePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CaptureRegionPainter oldDelegate) =>
      oldDelegate.selection != selection;
}
