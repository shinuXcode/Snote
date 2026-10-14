import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart' as pdfcore;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfx/pdfx.dart';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/theme_controller.dart';
import '../../canvas_engine/ink_renderer.dart';
import '../../canvas_engine/models/pen_config.dart';
import '../../canvas_engine/models/stroke.dart';
import '../../canvas_engine/models/stroke_codec.dart';
import '../../canvas_engine/painters/canvas_painter.dart';
import '../../canvas_engine/widgets/page_background.dart';
import '../../canvas_engine/input/viewport_transform.dart';
import '../../canvas_engine/widgets/notebook_viewport.dart';
import '../../canvas_engine/widgets/snote_canvas.dart';
import '../../canvas_engine/widgets/snote_canvas_controller.dart';
import '../../core/security/note_lock_service.dart';
import '../../core/settings/app_settings.dart';
import '../../data/local/file_document_repository.dart';
import '../../data/local/note_repository.dart';
import 'note_content_compatibility.dart';
import '../settings/settings_page.dart';
import '../folders/folder_cover_library_page.dart';

// Open-note tabs are shared by editor routes during the current app session.
final ValueNotifier<List<LocalNote>> _snoteOpenNoteTabs = ValueNotifier<List<LocalNote>>(<LocalNote>[]);

class _ToolPlacementDrag {
  const _ToolPlacementDrag(this.key, this.sourceLocation);

  final String key;
  final String sourceLocation;
}

class NoteEditorPage extends StatefulWidget {
  final Uint8List? initialPdfBytes;
  final String? initialPdfName;
  final LocalNote note;
  final bool embedded;
  final ValueChanged<LocalNote>? onSwitchTab;
  final ValueChanged<LocalNote?>? onCloseTab;

  const NoteEditorPage({
    super.key,
    required this.note,
    this.initialPdfBytes,
    this.initialPdfName,
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
  final Map<String, TextEditingController> _textBoxControllers = <String, TextEditingController>{};
  final Map<String, List<Stroke>> _thumbnailStrokeCache = <String, List<Stroke>>{};
  final Map<String, Object?> _thumbnailStrokeSources = <String, Object?>{};
  final Map<String, Uint8List> _thumbnailRasterCache = <String, Uint8List>{};
  Map<String, Object?>? _pageClipboard;
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
  String? _loadError;
  String? _pageRenderError;
  String? _lastLoggedBuildState;
  bool _pageLayoutLogged = false;
  final Map<String, Uint8List> _backgroundImageCache = <String, Uint8List>{};
  final Map<String, String> _backgroundImageEncodedByPageId = <String, String>{};
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
  double _toolPencaseX = SnoteSettings.instance.getDouble('toolPencaseX');
  double _toolPencaseY = SnoteSettings.instance.getDouble('toolPencaseY');
  String _toolPencaseDock = SnoteSettings.instance.getString('toolPencaseDockSide');
  Timer? _auxToolTapTimer;
  bool _studyTimerVisible = false;
  bool _viewportZoomLocked = false;
  int _viewportResetToken = 0;
  final ValueNotifier<ViewportTransform> _viewportTransform = ValueNotifier(
    ViewportTransform(scale: SnoteSettings.instance.getDouble('noteZoom')),
  );
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

  // Defensive access: a persisted note can contain malformed/legacy page
  // metadata. Never let an out-of-range page index crash the entire editor.
  Map<String, Object?> get pageData {
    if (_pages.isEmpty) return const <String, Object?>{};
    if (_page < 0 || _page >= _pages.length) {
      _page = clampNotePageIndex(_page, _pages.length);
    }
    return _pages[_page];
  }
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
    debugPrint(
      '[Snote][Editor] initState noteId=${widget.note.id} '
      'platform=${defaultTargetPlatform.name} '
      'initialPdfBytes=${widget.initialPdfBytes?.length ?? 0}',
    );
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
    debugPrint(
      '[Snote][Editor] prepare start noteId=${widget.note.id} '
      'pdfBytes=${widget.initialPdfBytes?.length ?? 0}',
    );
    // Never expose _pageView until _load has populated _pages. The previous
    // sequence set _loading=false before awaiting _load(), so pageData could
    // index an empty list and leave note and PDF routes on a blank screen.
    try {
      final locked = await _lock.isLocked(widget.note.id);
      debugPrint('[Snote][Editor] lock check complete noteId=${widget.note.id} locked=$locked');
      if (!mounted) return;
      setState(() {
        _locked = locked;
        _unlocked = !locked;
        _loading = true;
      });

      if (locked) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      await _load();
      debugPrint('[Snote][Editor] prepare complete noteId=${widget.note.id} pages=${_pages.length}');
    } catch (error, stackTrace) {
      debugPrint('[Snote][Editor] initialization failed noteId=${widget.note.id}: $error\n$stackTrace');
      if (!mounted) return;
      // Keep existing persisted note data untouched. Present a recoverable
      // error instead of letting the editor build with an empty page list.
      setState(() {
        _loading = false;
        _loadError = 'Could not load this note: $error. Your saved data has not been deleted.';
      });
    }
  }

  Future<void> _load() async {
    debugPrint('[Snote][Editor] load start noteId=${widget.note.id}');
    final note = await _repo.get(widget.note.id);
    debugPrint(
      '[Snote][Editor] database read noteId=${widget.note.id} '
      'found=${note != null} contentBytes=${note?.contentJson?.length ?? 0}',
    );
    if (note == null) {
      throw StateError(
        'This note is no longer available in the current local account. '
        'No new blank note was created and no saved data was changed.',
      );
    }
    final parsed = <Map<String, Object?>>[];
    int? storedCoverColor;
    String? storedCoverIcon;
    String? storedCoverKey;
    bool? storedDrawMode;
    if (note?.contentJson != null && note!.contentJson!.trim().isNotEmpty) {
      // Do not silently turn an unreadable saved note into a new blank page:
      // that can make the next autosave overwrite the user's recoverable data.
      final Object? decoded;
      try {
        decoded = jsonDecode(note.contentJson!);
      } catch (error) {
        throw FormatException('Saved note content is not valid JSON: $error');
      }
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Saved note content has an unsupported format.');
      }
      final json = decoded;
      storedCoverColor = (json['coverColor'] as num?)?.toInt();
      storedCoverIcon = json['coverIcon']?.toString();
      storedCoverKey = json['coverKey']?.toString();
      final raw = json['pages'];
      if (raw is List) {
        for (final item in raw) {
          if (item is Map) {
            parsed.add(_normalize(item.map((key, value) => MapEntry(key.toString(), value))));
          }
        }
      }
      final delta = json['text_delta'];
      if (delta is List) {
        try {
          _quill.document = Document.fromJson(delta);
        } catch (error) {
          debugPrint('Snote rich-text document could not be restored: $error');
        }
      }
      storedDrawMode = restoreNoteDrawMode(
        savedMode: json['editorMode'],
        textDelta: delta,
        hasVisibleCanvasContent: parsed.any((page) {
          final strokes = page['strokes'];
          final images = page['images'];
          final textBoxes = page['textBoxes'];
          final background = page['backgroundImage'];
          return (strokes is List && strokes.isNotEmpty) ||
              (images is List && images.isNotEmpty) ||
              (textBoxes is List && textBoxes.isNotEmpty) ||
              (background is String && background.isNotEmpty);
        }),
      );
      // A document with page data that exists but cannot be decoded must be
      // surfaced as an error, not silently replaced with a blank notebook.
      if (raw != null && raw is! List) {
        throw const FormatException('Saved note pages have an unsupported format.');
      }
      if (raw is List && raw.isNotEmpty && parsed.isEmpty) {
        throw const FormatException('Saved note pages could not be restored.');
      }
      // Early Snote builds stored a single canvas page at the root of
      // content_json. Recover that page instead of opening a fresh blank page.
      if (parsed.isEmpty && (raw == null || (raw is List && raw.isEmpty))) {
        final legacyPage = legacyPageFromNoteContent(json.cast<String, Object?>());
        if (legacyPage != null) parsed.add(_normalize(legacyPage));
      }
    }

    var importedOnFirstOpen = false;
    var originalPdfPageCount = 0;

    // Recovery path for imported PDFs: the original PDF is persisted as a
    // local attachment before rendering. If the app was interrupted before
    // page snapshots were saved (or an older build saved only the attachment),
    // reconstruct notebook pages from that attachment when reopening the note.
    Uint8List? pdfBytes = widget.initialPdfBytes;
    String? pdfName = widget.initialPdfName;
    var hasPdfAttachment = false;
    // Look for the original PDF even when a stale placeholder page exists.
    // Earlier betas could save a non-empty pages envelope before rasterizing
    // the PDF, which incorrectly skipped the old `parsed.isEmpty` recovery.
    if (pdfBytes == null || pdfBytes.isEmpty) {
      final assets = await FileDocumentRepository().listForNote(widget.note.id);
      DocumentAsset? sourcePdf;
      for (final asset in assets.reversed) {
        final type = asset.type.toLowerCase();
        final name = asset.name.toLowerCase();
        if (type == 'pdf' || type == 'application/pdf' || name.endsWith('.pdf')) {
          sourcePdf = asset;
          break;
        }
      }
      hasPdfAttachment = sourcePdf != null;
      if (sourcePdf != null) {
        try {
          pdfBytes = await FileDocumentRepository().readBytes(sourcePdf);
          pdfName = sourcePdf.name;
        } catch (error) {
          throw StateError(
            'The original PDF attachment is present but could not be read: $error',
          );
        }
        if (pdfBytes.isEmpty) {
          throw StateError(
            'The original PDF attachment is empty. It was preserved; no blank page was substituted.',
          );
        }
      }
    }

    if (pdfBytes != null && pdfBytes.isNotEmpty) {
      debugPrint(
        '[Snote][PDF] restore requested noteId=${widget.note.id} '
        'name=${pdfName ?? widget.note.title} bytes=${pdfBytes.length} '
        'savedPages=${parsed.length}',
      );
    }
    if (pdfBytes != null &&
        pdfBytes.isNotEmpty &&
        shouldRestorePdfPageBackgrounds(
          parsed,
          sourceHash: sha256.convert(pdfBytes).toString(),
        )) {
      try {
        final result = await _renderPdfPages(
          pdfBytes,
          pdfName ?? (widget.note.title + '.pdf'),
        );
        if (result.totalPages < 1 || result.pages.isEmpty) {
          throw StateError('The PDF renderer returned no pages.');
        }
        // Keep any existing annotations while replacing stale/absent PDF
        // raster backgrounds with freshly rendered pages from the attachment.
        final recoveredPages = mergeSavedAnnotationsWithPdfPages(
          savedPages: List<Map<String, Object?>>.from(parsed),
          renderedPages: result.pages,
        );
        parsed
          ..clear()
          ..addAll(recoveredPages);
        originalPdfPageCount = result.totalPages;
        importedOnFirstOpen = true;
        debugPrint(
          '[Snote][PDF] rendered noteId=${widget.note.id} '
          'pages=${result.pages.length}/${result.totalPages}',
        );
      } catch (error) {
        // A document import must never degrade into a seemingly successful
        // blank notebook. Keep the source attachment and report the failure.
        throw StateError('PDF could not be rendered into notebook pages: $error');
      }
    }
    if (parsed.isEmpty && hasPdfAttachment) {
      throw StateError(
        'This note has a PDF attachment, but no pages could be restored. '
        'The original file remains saved; retry the import instead of overwriting it.',
      );
    }
    // Only genuinely empty ordinary notes get a new page. Imported PDFs must
    // either restore their pages or show a recoverable error. Persist the
    // first page immediately: new notes must not depend on a later pen stroke
    // or a delayed autosave before they have a valid document envelope.
    final createdInitialPage = parsed.isEmpty;
    if (createdInitialPage) parsed.add(_newPage());
    for (var i = 0; i < parsed.length; i++) {
      parsed[i] = _normalize(parsed[i]);
    }
    if (!mounted) return;
    setState(() {
      _pages = parsed;
      _page = 0;
      _draw = storedDrawMode ?? _draw;
      _noteCoverColor = storedCoverColor;
      _noteCoverIcon = storedCoverIcon;
      _noteCoverKey = storedCoverKey;
    });
    debugPrint(
      '[Snote][Editor] page data ready noteId=${widget.note.id} '
      'pages=${parsed.length} drawMode=${_draw ? 'handwriting' : 'text'} '
      'initialPageCreated=$createdInitialPage pdfPages=$originalPdfPageCount',
    );

    // Toolbar/settings restoration can read pageData, so it must happen only
    // after the page list has been installed. Keep the loading screen visible
    // until initialization work is complete.
    _restoreToolbar();
    // Keep-awake is optional and must never gate editor initialization. Some
    // Android vendor power-management implementations can stall the plugin
    // channel; run it independently so notes and PDF annotations become
    // usable as soon as their page data is ready.
    unawaited(_keepAwake().catchError((Object error, StackTrace stackTrace) {
      debugPrint('Snote keep-awake setup failed (non-fatal): $error\\n$stackTrace');
    }));
    if (!mounted) return;
    setState(() {
      _loading = false;
      _loadError = null;
    });
    if ((importedOnFirstOpen || createdInitialPage) && mounted) {
      _savePending = true;
      await _save(force: true);
      if (mounted && originalPdfPageCount > parsed.length) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Imported ' + parsed.length.toString() + ' of ' +
                  originalPdfPageCount.toString() +
                  ' PDF pages for performance. The original file remains attached to this note.',
            ),
          ),
        );
      }
    }
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
    p['textBoxes'] ??= <Object?>[];
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
    _auxToolTapTimer?.cancel();
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
        'editorMode': _draw ? 'handwriting' : 'text',
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

  void _toggleEditorMode() {
    setState(() => _draw = !_draw);
    _scheduleSave();
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
    _viewportTransform.dispose();
    _thumbnailRasterCache.clear();
    _thumbnailStrokeCache.clear();
    _thumbnailStrokeSources.clear();
    for (final controller in _textBoxControllers.values) {
      controller.dispose();
    }
    unawaited(WakelockPlus.disable());
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewportSize = MediaQuery.sizeOf(context);
    final buildState = 'locked=$_locked unlocked=$_unlocked loading=$_loading '
        'pages=${_pages.length} hasError=${_loadError != null} draw=$_draw '
        'viewport=${viewportSize.width}x${viewportSize.height}';
    if (_lastLoggedBuildState != buildState) {
      _lastLoggedBuildState = buildState;
      debugPrint('[Snote][Editor] build noteId=${widget.note.id} $buildState');
    }
    // Locked notes finish their first load without page data. Handle that
    // state before the empty-page guard so the password UI actually appears.
    if (_locked && !_unlocked) return _lockedView();

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.note.title)),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Opening note and restoring saved pages…'),
            ],
          ),
        ),
      );
    }
    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.note.title)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, size: 44),
                const SizedBox(height: 12),
                Text(_loadError!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () {
                    setState(() {
                      _loadError = null;
                      _loading = true;
                    });
                    unawaited(_prepare());
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    // The editor must never try to render a page before its document exists.
    // This also protects against legacy records whose page list is empty.
    if (_pages.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.note.title)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.description_outlined, size: 44),
                const SizedBox(height: 12),
                const Text(
                  'No page is available to display. Your saved data has not been changed.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _retryNoteLoad,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry loading note'),
                ),
              ],
            ),
          ),
        ),
      );
    }

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
                  onVerticalDragEnd: (_pan || _selected > 0) ? null : _pageSwipe,
                  onDoubleTap: () => setState(() => _toolbar = !_toolbar),
                  onLongPress: _settings.getBool('fingerLongPressSelection')
                      ? () => _selectTool(CanvasTool.lasso)
                      : null,
                  child: _pageView(),
                ),
              ),
              if (!_full) _header(),
              if (!_full && _tabsVisible) _openNotesTabsBar(),
              if (_preview && !_full && !_readingMode) _previewRail(),
              if (_toolbar && _draw && !_readingMode) _toolbarWidget(),
              if (!_full && _draw && !_readingMode) _toolPencaseWidget(),
              if (_shapePanel && !_full && !_readingMode) _shapePanelWidget(),
              if (_showcaseOpen && !_full && !_readingMode) _showcaseWidget(),
              if (!_full) _viewportZoomControls(),
              _StudyTimerFloating(
                visible: _studyTimerVisible && !_full,
                onVisibilityChanged: (visible) => setState(() => _studyTimerVisible = visible),
              ),
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


  Widget _viewportZoomControls() {
    final theme = Theme.of(context);
    final initialScale = _settings.getDouble('noteZoom').clamp(.5, 4).toDouble();
    return ValueListenableBuilder<ViewportTransform>(
      valueListenable: _viewportTransform,
      builder: (context, transform, _) {
        final scaleChanged = (transform.scale - initialScale).abs() > .025;
        final positionChanged = transform.pan.distance > 3;
        if (!scaleChanged && !positionChanged) return const SizedBox.shrink();
        return Positioned(
          right: 12,
          bottom: 18,
          child: Material(
            elevation: 8,
            color: theme.colorScheme.surface.withValues(alpha: .96),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    (transform.scale * 100).round().toString() + '%',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(width: 34, height: 34),
                    padding: EdgeInsets.zero,
                    tooltip: _viewportZoomLocked ? 'Unlock zoom and pan' : 'Lock zoom and pan',
                    onPressed: () => setState(() => _viewportZoomLocked = !_viewportZoomLocked),
                    icon: Icon(
                      _viewportZoomLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
                      size: 18,
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(width: 34, height: 34),
                    padding: EdgeInsets.zero,
                    tooltip: 'Reset zoom and page position',
                    onPressed: () => setState(() {
                      _viewportZoomLocked = false;
                      _viewportResetToken++;
                    }),
                    icon: const Icon(Icons.center_focus_strong_rounded, size: 18),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
                    setState(() {
                      _locked = false;
                      _unlocked = true;
                      _loading = true;
                      _loadError = null;
                    });
                    await _prepare();
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

  void _retryNoteLoad() {
    _backgroundImageCache.clear();
    _backgroundImageEncodedByPageId.clear();
    setState(() {
      _pages = <Map<String, Object?>>[];
      _page = 0;
      _loading = true;
      _loadError = null;
      _pageRenderError = null;
    });
    unawaited(_prepare());
  }

  Widget _pageView() {
    try {
      return _buildPageViewContent();
    } catch (error, stackTrace) {
      debugPrint('Snote page rendering failed: $error\n$stackTrace');
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.description_outlined, size: 42),
              const SizedBox(height: 12),
              const Text(
                'This page could not be rendered. Your saved content has not been changed.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _retryNoteLoad,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry loading note'),
              ),
            ],
          ),
        ),
      );
    }
  }

  Uint8List? _backgroundImageBytesForCurrentPage() {
    final raw = pageData['backgroundImage'];
    if (raw is! String || raw.isEmpty) {
      _pageRenderError = null;
      return null;
    }
    final pageId = pageData['id']?.toString() ?? 'page-$_page';
    if (_backgroundImageEncodedByPageId[pageId] == raw) {
      return _backgroundImageCache[pageId];
    }
    try {
      final bytes = base64Decode(raw);
      if (bytes.isEmpty) throw const FormatException('The background image is empty.');
      _backgroundImageCache[pageId] = bytes;
      _backgroundImageEncodedByPageId[pageId] = raw;
      while (_backgroundImageCache.length > 2) {
        final oldest = _backgroundImageCache.keys.first;
        _backgroundImageCache.remove(oldest);
        _backgroundImageEncodedByPageId.remove(oldest);
      }
      _pageRenderError = null;
      return bytes;
    } catch (error, stackTrace) {
      debugPrint('Snote saved background image is unreadable ($pageId): $error\n$stackTrace');
      _backgroundImageEncodedByPageId[pageId] = raw;
      while (_backgroundImageEncodedByPageId.length > 2) {
        final oldest = _backgroundImageEncodedByPageId.keys.first;
        _backgroundImageEncodedByPageId.remove(oldest);
        _backgroundImageCache.remove(oldest);
      }
      _pageRenderError = 'The saved page background could not be decoded. Other page content is preserved.';
      return null;
    }
  }

  Widget _buildPageViewContent() {
    // Defensive guard: asynchronous loads, route restoration, or a future
    // malformed import must never crash the shared note/PDF editor.
    if (_pages.isEmpty) {
      // Defensive race fallback; the parent provides an actionable retry UI.
      return const Center(
        child: Text('No page is available to display. Retry loading this note.'),
      );
    }
    _page = clampNotePageIndex(_page, _pages.length);
    final backgroundImageBytes = _backgroundImageBytesForCurrentPage();
    final sizeKey = pageData['pageSize']?.toString() ?? 'A4';
    final horizontal = pageData['orientation']?.toString() == 'horizontal';
    final storedAspectRatio = pageData['pageAspectRatio'];
    final baseAspectRatio = storedAspectRatio is num && storedAspectRatio > 0
        ? storedAspectRatio.toDouble()
        : switch (sizeKey) {
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
          // Explicitly fill the page surface. A CustomPaint without a child
          // may otherwise choose a zero size if a future viewport/layout change
          // loosens its constraints on a mobile/tablet route.
          Positioned.fill(
            child: RepaintBoundary(
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
                child: const SizedBox.expand(),
              ),
            ),
          ),
          if (backgroundImageBytes != null)
            Positioned.fill(
              child: IgnorePointer(
                child: Image.memory(
                  backgroundImageBytes,
                  fit: BoxFit.fill,
                  gaplessPlayback: true,
                  errorBuilder: (_, error, __) {
                    debugPrint('Snote page image decode failed: $error');
                    return ColoredBox(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            'This page image could not be decoded. '
                            'Your saved annotations are preserved; retry loading the note.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          if (_pageRenderError != null)
            Positioned(
              left: 8,
              right: 8,
              top: 8,
              child: IgnorePointer(
                child: Material(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      _pageRenderError!,
                      style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer, fontSize: 11),
                    ),
                  ),
                ),
              ),
            ),
          if (_settings.getBool('showAuxiliaryLine'))
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _AuxiliaryGuidePainter(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
          if (_draw)
            Positioned.fill(
              child: IgnorePointer(
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
                  showAuxiliaryLine: _settings.getBool('showAuxiliaryLine'),
                  autoAuxiliaryPoint: _settings.getBool('autoAuxiliaryPoint'),
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
            )
          else
            Positioned.fill(
              child: IgnorePointer(
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
          Positioned.fill(
            child: LayoutBuilder(
              builder: (_, constraints) => Stack(
                clipBehavior: Clip.none,
                children: _pageTextBoxes
                    .map((box) => _pageTextBoxItem(
                          box,
                          constraints.maxWidth,
                          constraints.maxHeight,
                        ))
                    .toList(),
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

    // Size the paper against the *actual viewport constraints*. AspectRatio
    // alone can receive loose/unbounded constraints inside the nested
    // Scaffold + Transform tree on Android split-pane layouts; in that case
    // the page can collapse or be laid out outside the visible canvas while
    // the floating tools remain visible. An explicit bounded size keeps the
    // sheet visible in both embedded desktop/tablet and full-screen routes.
    final Widget child = LayoutBuilder(
      builder: (context, constraints) {
        final viewportSize = MediaQuery.sizeOf(context);
        // Some nested routes briefly provide zero/loose constraints while
        // transitioning (particularly after tablet rotation). Fall back to
        // the real view size rather than drawing a one-pixel sheet.
        final maxWidth = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : viewportSize.width;
        final maxHeight = constraints.maxHeight.isFinite && constraints.maxHeight > 0
            ? constraints.maxHeight
            : viewportSize.height;
        if (!_pageLayoutLogged) {
          _pageLayoutLogged = true;
          debugPrint(
            '[Snote][Canvas] first page layout noteId=${widget.note.id} '
            'constraints=$constraints resolved=${Size(maxWidth, maxHeight)} '
            'paper=$sizeKey orientation=${horizontal ? 'landscape' : 'portrait'} '
            'infinite=$infiniteCanvas',
          );
        }
        if (infiniteCanvas) {
          final side = math.max(1.0, math.min(2400.0, math.min(maxWidth, maxHeight)));
          return Center(
            child: SizedBox(width: side, height: side, child: pageSurface),
          );
        }
        final safeAspect = aspectRatio.isFinite && aspectRatio > 0
            ? aspectRatio
            : 210 / 297;
        final width = math.max(1.0, math.min(maxWidth, maxHeight * safeAspect));
        final height = math.max(1.0, width / safeAspect);
        return Center(
          child: SizedBox(
            width: width,
            height: height,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _pageColor(),
                border: Border.all(color: const Color(0x33000000), width: 1),
                boxShadow: SnoteThemeController.instance.eInk
                    ? const <BoxShadow>[]
                    : const <BoxShadow>[
                        BoxShadow(
                          color: Color(0x22000000),
                          blurRadius: 12,
                          offset: Offset(0, 3),
                        ),
                      ],
              ),
              child: pageSurface,
            ),
          ),
        );
      },
    );

    return RepaintBoundary(
      key: _pageCaptureKey,
      child: NotebookViewport(
        allowSingleFingerPan: _pan || _readingMode,
        minScale: .5,
        maxScale: 4,
        initialScale: _settings.getDouble('noteZoom'),
        zoomLocked: _viewportZoomLocked,
        resetToken: _viewportResetToken,
        onTransformChanged: (transform) => _viewportTransform.value = transform,
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


  List<Map<String, Object?>> get _pageTextBoxes {
    final raw = pageData['textBoxes'];
    if (raw is! List) return <Map<String, Object?>>[];
    return raw
        .whereType<Map>()
        .map((item) => item.cast<String, Object?>())
        .toList();
  }

  void _addTextBox() {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final box = <String, Object?>{
      'id': id,
      'x': .16,
      'y': .14,
      'width': .66,
      'height': .18,
      'text': '',
      'fontSize': 18.0,
      'color': _penColor.toARGB32(),
    };
    setState(() {
      final boxes = pageData['textBoxes'];
      if (boxes is List) {
        boxes.add(box);
      } else {
        pageData['textBoxes'] = <Object?>[box];
      }
      _textBoxControllers[id] = TextEditingController();
    });
    _scheduleSave();
  }

  void _updateTextBox(String id, String key, Object? value) {
    for (final box in _pageTextBoxes) {
      if (box['id']?.toString() != id) continue;
      box[key] = value;
      _scheduleSave();
      return;
    }
  }

  void _removeTextBox(String id) {
    setState(() {
      final boxes = pageData['textBoxes'];
      if (boxes is List) {
        boxes.removeWhere((value) =>
            value is Map && value['id']?.toString() == id);
      }
      final controller = _textBoxControllers.remove(id);
      controller?.dispose();
    });
    _scheduleSave();
  }

  Widget _pageTextBoxItem(
    Map<String, Object?> box,
    double pageWidth,
    double pageHeight,
  ) {
    final id = box['id']?.toString() ?? '';
    final x = (box['x'] as num?)?.toDouble() ?? .16;
    final y = (box['y'] as num?)?.toDouble() ?? .14;
    final width = (box['width'] as num?)?.toDouble() ?? .66;
    final height = (box['height'] as num?)?.toDouble() ?? .18;
    final fontSize = (box['fontSize'] as num?)?.toDouble() ?? 18;
    final color = Color((box['color'] as num?)?.toInt() ?? 0xff263238);
    final initialText = box['text']?.toString() ?? '';
    final controller = _textBoxControllers.putIfAbsent(
      id,
      () => TextEditingController(text: initialText),
    );
    if (controller.text != initialText && !controller.selection.isValid) {
      controller.text = initialText;
    }

    return Positioned(
      left: (x * pageWidth).clamp(0.0, math.max(0.0, pageWidth - 48)).toDouble(),
      top: (y * pageHeight).clamp(0.0, math.max(0.0, pageHeight - 48)).toDouble(),
      width: (width * pageWidth).clamp(80.0, math.max(80.0, pageWidth)).toDouble(),
      height: (height * pageHeight).clamp(54.0, math.max(54.0, pageHeight)).toDouble(),
      child: Material(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: .93),
        elevation: 3,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: .65),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Container(
                height: 22,
                color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: .85),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (details) {
                    final currentBox = _pageTextBoxes.firstWhere(
                      (item) => item['id']?.toString() == id,
                      orElse: () => box,
                    );
                    setState(() {
                      currentBox['x'] = (x + details.delta.dx / math.max(1.0, pageWidth))
                          .clamp(0.0, math.max(0.0, 1.0 - width)).toDouble();
                      currentBox['y'] = (y + details.delta.dy / math.max(1.0, pageHeight))
                          .clamp(0.0, math.max(0.0, 1.0 - height)).toDouble();
                    });
                    _scheduleSave();
                  },
                  child: Row(children: [
                  const SizedBox(width: 5),
                  Icon(Icons.drag_indicator_rounded,
                      size: 15, color: Theme.of(context).colorScheme.onPrimaryContainer),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Text box',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(width: 24, height: 22),
                    padding: EdgeInsets.zero,
                    tooltip: 'Remove text box',
                    onPressed: () => _removeTextBox(id),
                    icon: const Icon(Icons.close_rounded, size: 14),
                  ),
                  ]),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  expands: true,
                  minLines: null,
                  maxLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  style: TextStyle(fontSize: fontSize, color: color, height: 1.15),
                  onChanged: (value) => _updateTextBox(id, 'text', value),
                  decoration: const InputDecoration(
                    hintText: 'Type while keeping your handwritten notes',
                    hintStyle: TextStyle(fontSize: 11),
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.fromLTRB(7, 5, 7, 5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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


  Future<({List<Map<String, Object?>> pages, int totalPages})> _renderPdfPages(
    Uint8List sourceBytes,
    String sourceName,
  ) async {
    if (sourceBytes.isEmpty) throw StateError('The selected PDF is empty.');
    final sourceHash = sha256.convert(sourceBytes).toString();
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
            throw StateError('Could not render PDF page ' + index.toString() + '.');
          }
          imported.add({
            'id': DateTime.now().microsecondsSinceEpoch.toString() + '-' + index.toString(),
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

  Future<void> _importPdfIntoNote() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
      if (file == null) return;
      final sourceBytes = await file.readAsBytes();
      final existingAssets = await FileDocumentRepository().listForNote(widget.note.id);
      final existingPdf = existingAssets.any((asset) =>
          asset.type == 'pdf' &&
          asset.name == file.name &&
          asset.size == sourceBytes.length);
      if (!existingPdf) {
        await FileDocumentRepository().saveBytes(
          noteId: widget.note.id,
          name: file.name,
          type: 'pdf',
          bytes: sourceBytes,
          metadata: const <String, dynamic>{'source': 'pdf-import'},
        );
      }

      final result = await _renderPdfPages(sourceBytes, file.name);
      final imported = result.pages;
      if (!mounted || imported.isEmpty) return;
      setState(() {
        final insertionIndex = (_page + 1).clamp(0, _pages.length);
        _pages.insertAll(insertionIndex, imported);
        _page = insertionIndex;
        _normalize(pageData);
      });
      _scheduleSave();
      if (mounted) {
        final message = result.totalPages > imported.length
            ? 'Imported ' + imported.length.toString() + ' of ' +
                result.totalPages.toString() +
                ' pages. The original PDF is preserved in note attachments.'
            : 'Imported ' + result.totalPages.toString() +
                ' PDF pages. The original PDF is preserved in note attachments.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF import failed: ' + error.toString())),
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

  Future<void> _exportLiveScreenshot() async {
    try {
      await _flushSave();
      await WidgetsBinding.instance.endOfFrame;
      final renderObject = _pageCaptureKey.currentContext?.findRenderObject();
      if (renderObject is! RenderRepaintBoundary) {
        throw StateError('The note page is not ready for capture.');
      }
      final ratio = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 3.0).toDouble();
      final image = await renderObject.toImage(pixelRatio: ratio);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) throw StateError('Could not encode screenshot.');
        final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        final safeTitle = _title.text.trim()
            .replaceAll(RegExp(r'[^a-zA-Z0-9 _-]'), '')
            .replaceAll(' ', '_');
        final saved = await FilePicker.saveFile(
          dialogTitle: 'Save current Snote page screenshot',
          fileName: '${safeTitle.isEmpty ? 'Snote' : safeTitle}-page-${_page + 1}.png',
          type: FileType.custom,
          allowedExtensions: const ['png'],
          bytes: bytes,
        );
        if (mounted && saved != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Screenshot saved: $saved')),
          );
        }
      } finally {
        image.dispose();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Screenshot failed: $error')),
        );
      }
    }
  }


  Future<void> _studyTimerSheet() async {
    if (!mounted) return;
    setState(() => _studyTimerVisible = !_studyTimerVisible);
  }

  Future<void> _calculatorSheet() async {
    const keys = [
      'sin', 'cos', 'tan', 'sqrt',
      '(', ')', 'abs', 'ln',
      'log', 'e', 'AC', 'DEL',
      '7', '8', '9', '÷',
      '4', '5', '6', '×',
      '1', '2', '3', '−',
      '0', '.', 'π', '+',
      '%', '^', 'Ans', '=',
    ];
    _calculatorInput.text = _calculatorInput.text.isEmpty ? '0' : _calculatorInput.text;
    _calculatorResult = '0';
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (_, setModal) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 390, maxHeight: 600),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                12, 2, 12, MediaQuery.viewInsetsOf(context).bottom + 10,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(
                        Icons.functions_rounded,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Scientific calculator',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Calculator tool settings',
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) unawaited(_toolPlacementSheet('calculator'));
                        });
                      },
                      icon: const Icon(Icons.tune_rounded),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Close calculator',
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ]),
                  TextField(
                    controller: _calculatorInput,
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.edit_rounded, size: 18),
                      labelText: 'Expression',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(13)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 7, bottom: 9),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: .70),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'RESULT',
                          style: TextStyle(
                            fontSize: 9,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w900,
                            color: Theme.of(context).colorScheme.onSecondaryContainer.withValues(alpha: .75),
                          ),
                        ),
                        Text(
                          _calculatorResult,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w900,
                            color: Theme.of(context).colorScheme.onSecondaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: GridView.count(
                      crossAxisCount: 4,
                      shrinkWrap: true,
                      mainAxisSpacing: 5,
                      crossAxisSpacing: 5,
                      childAspectRatio: 1.45,
                      physics: const NeverScrollableScrollPhysics(),
                      children: keys.map((key) {
                        final scheme = Theme.of(context).colorScheme;
                        final isResult = key == '=';
                        final isClear = key == 'AC';
                        final isDelete = key == 'DEL';
                        final isFunction = const {
                          'sin', 'cos', 'tan', 'sqrt', 'abs', 'ln', 'log', 'e', '(', ')', '%', '^', 'π', 'Ans',
                        }.contains(key);
                        final isOperator = const {'÷', '×', '−', '+'}.contains(key);
                        final background = isResult
                            ? scheme.primary
                            : isClear
                                ? scheme.errorContainer
                                : isDelete
                                    ? scheme.tertiaryContainer
                                    : (isFunction || isOperator)
                                        ? scheme.secondaryContainer
                                        : scheme.surfaceContainerHighest;
                        final foreground = isResult
                            ? scheme.onPrimary
                            : isClear
                                ? scheme.onErrorContainer
                                : isDelete
                                    ? scheme.onTertiaryContainer
                                    : (isFunction || isOperator)
                                        ? scheme.onSecondaryContainer
                                        : scheme.onSurface;
                        return FilledButton(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                            backgroundColor: background,
                            foregroundColor: foreground,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () {
                            setModal(() {
                              final current = _calculatorInput.text;
                              if (key == 'AC') {
                                _calculatorInput.text = '0';
                                _calculatorResult = '0';
                              } else if (key == 'DEL') {
                                _calculatorInput.text = current.length <= 1
                                    ? '0'
                                    : current.substring(0, current.length - 1);
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
                                final isFunction = const {
                                  'sin', 'cos', 'tan', 'sqrt', 'abs', 'ln', 'log',
                                }.contains(key);
                                final token = isFunction
                                    ? key + '('
                                    : key == '×'
                                        ? '*'
                                        : key == '÷'
                                            ? '/'
                                            : key == '−'
                                                ? '-'
                                                : key == 'π'
                                                    ? 'pi'
                                                    : key;
                                final replaceLeadingZero = current == '0' &&
                                    (RegExp(r'^\d$').hasMatch(token) ||
                                        isFunction ||
                                        token == 'pi' ||
                                        token == 'e');
                                _calculatorInput.text = replaceLeadingZero
                                    ? token
                                    : current + token;
                              }
                            });
                          },
                          child: Text(
                            key,
                            style: TextStyle(
                              fontSize: key.length > 3 ? 12 : 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        );
                      }).toList(),
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

  Widget _header() {
    final viewport = MediaQuery.sizeOf(context);
    final compact = viewport.width < 760 || viewport.height < 440;
    final titleTools = _toolKeysForLocation('titleBar');
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: Material(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: .98),
        child: SizedBox(
          height: 46,
          child: Row(
            children: [
              _compactAction(
                tooltip: 'Back to notes',
                icon: Icons.menu_rounded,
                onPressed: () async {
                  await _flushSave();
                  if (mounted) Navigator.maybePop(context);
                },
              ),
              AnimatedBuilder(
                animation: _canvas,
                builder: (_, __) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _compactAction(
                      tooltip: 'Undo',
                      icon: Icons.undo_rounded,
                      onPressed: _canvas.canUndo ? _canvas.undo : null,
                    ),
                    _compactAction(
                      tooltip: 'Redo',
                      icon: Icons.redo_rounded,
                      onPressed: _canvas.canRedo ? _canvas.redo : null,
                    ),
                    _compactAction(
                      tooltip: _tabsVisible ? 'Hide note tabs' : 'Show note tabs',
                      icon: Icons.view_carousel_rounded,
                      onPressed: () => setState(() => _tabsVisible = !_tabsVisible),
                    ),
                  ],
                ),
              ),
              Flexible(
                fit: FlexFit.loose,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: compact ? 92 : 140,
                    maxWidth: compact ? 132 : 220,
                  ),
                  child: TextField(
                    controller: _title,
                    maxLines: 1,
                    textAlignVertical: TextAlignVertical.center,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                      border: InputBorder.none,
                      hintText: 'Name this note',
                    ),
                    onChanged: (_) => _refreshCurrentOpenTab(),
                    onSubmitted: (_) => _save(force: true),
                  ),
                ),
              ),
              if (titleTools.isNotEmpty)
                SizedBox(
                  width: math.min(112.0, titleTools.length * 32.0).toDouble(),
                  child: _toolDropArea(
                    'titleBar',
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: titleTools
                            .map((key) => _placedToolButton(key, 'titleBar'))
                            .toList(),
                      ),
                    ),
                  ),
                ),
              _compactAction(
                tooltip: 'Save note',
                icon: Icons.save_outlined,
                onPressed: () => _save(force: true),
              ),
              _compactAction(
                tooltip: _settings.getBool('autoSave')
                    ? 'Auto-save is on'
                    : 'Auto-save is off; tap to enable',
                icon: _settings.getBool('autoSave')
                    ? Icons.autorenew_rounded
                    : Icons.save_as_outlined,
                onPressed: () async {
                  final enable = !_settings.getBool('autoSave');
                  await _settings.setBool('autoSave', enable);
                  if (enable && _savePending) await _save(force: true);
                  if (mounted) setState(() {});
                },
              ),
              if (!compact) ...[
                _compactAction(
                  tooltip: 'Pages / thumbnails',
                  icon: Icons.view_sidebar_outlined,
                  onPressed: () => setState(() => _preview = !_preview),
                ),
                _compactAction(
                  tooltip: _draw ? 'Text mode' : 'Handwriting mode',
                  icon: _draw ? Icons.text_fields_rounded : Icons.draw_rounded,
                  onPressed: _toggleEditorMode,
                ),
                _compactAction(
                  tooltip: 'Lock note',
                  icon: _locked ? Icons.lock_rounded : Icons.lock_outline_rounded,
                  onPressed: _lockNote,
                ),
                _compactAction(
                  tooltip: 'Fullscreen',
                  icon: _full ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                  onPressed: _toggleFullscreen,
                ),
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
              ] else
                PopupMenuButton<String>(
                  tooltip: 'More editor controls',
                  icon: const Icon(Icons.more_vert_rounded),
                  onSelected: (action) async {
                    switch (action) {
                      case 'pages':
                        setState(() => _preview = !_preview);
                        break;
                      case 'shapes':
                        setState(() => _shapePanel = !_shapePanel);
                        break;
                      case 'mode':
                        _toggleEditorMode();
                        break;
                      case 'addText':
                        _addTextBox();
                        break;
                      case 'lock':
                        _lockNote();
                        break;
                      case 'fullscreen':
                        _toggleFullscreen();
                        break;
                      case 'settings':
                        await Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SettingsPage(noteOnly: true),
                          ),
                        );
                        if (mounted) {
                          setState(() {});
                          _keepAwake();
                        }
                        break;
                      case 'screenshot':
                        await _exportLiveScreenshot();
                        break;
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'pages', child: Text('Pages / thumbnails')),
                    PopupMenuItem(value: 'shapes', child: Text('Shapes and diagrams')),
                    PopupMenuItem(value: 'mode', child: Text('Toggle text / handwriting')),
                    PopupMenuItem(value: 'addText', child: Text('Add text box to page')),
                    PopupMenuItem(value: 'lock', child: Text('Lock note')),
                    PopupMenuItem(value: 'fullscreen', child: Text('Fullscreen')),
                    PopupMenuItem(value: 'settings', child: Text('Note settings')),
                    PopupMenuItem(value: 'screenshot', child: Text('Save page screenshot')),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

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
    final defaultLeft = math.max(0.0, size.width - 42);
    final left = (_pageChangerX < 0 ? defaultLeft : _pageChangerX)
        .clamp(0.0, math.max(0.0, size.width - 40))
        .toDouble();
    final top = _pageChangerY
        .clamp(50.0, math.max(50.0, size.height - 142))
        .toDouble();

    return Positioned(
      left: _pageChangerX < 0 ? null : left,
      right: _pageChangerX < 0 ? 8 : null,
      top: top,
      child: Material(
        elevation: 3,
        color: Theme.of(context).colorScheme.surface.withValues(alpha: .94),
        borderRadius: BorderRadius.circular(11),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onPanUpdate: (details) {
                  setState(() {
                    _pageChangerX = (left + details.delta.dx)
                        .clamp(2.0, math.max(2.0, size.width - 42))
                        .toDouble();
                    _pageChangerY = (top + details.delta.dy)
                        .clamp(50.0, math.max(50.0, size.height - 142))
                        .toDouble();
                  });
                },
                child: const SizedBox(
                  width: 28,
                  height: 16,
                  child: Icon(Icons.drag_indicator_rounded, size: 14),
                ),
              ),
              if (_settings.getBool('showPageNumbers'))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '${_page + 1}/${_pages.length}',
                    style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800),
                  ),
                ),
              IconButton(
                onPressed: _previousPage,
                tooltip: 'Previous page',
                constraints: const BoxConstraints.tightFor(width: 28, height: 26),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 18),
              ),
              IconButton(
                onPressed: _nextPage,
                tooltip: 'Next page',
                constraints: const BoxConstraints.tightFor(width: 28, height: 26),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
              ),
              IconButton(
                onPressed: _addPage,
                tooltip: 'Add page',
                constraints: const BoxConstraints.tightFor(width: 28, height: 26),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add_rounded, size: 17),
              ),
            ],
          ),
        ),
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
        ? (_dockSide == 'left' || _dockSide == 'right' || _dockSide == 'bottom'
            ? Axis.vertical
            : Axis.horizontal)
        : _floatingAxis;
    final constraints = axis == Axis.vertical
        ? BoxConstraints(
            maxWidth: 84,
            maxHeight: math.max(160, screen.height - 76),
          )
        : BoxConstraints(
            maxWidth: math.max(120, screen.width - 16),
            maxHeight: 92,
          );
    final toolbar = ConstrainedBox(
      constraints: constraints,
      child: _toolbarSurface(
        _toolDropArea(
          'toolbar',
          _toolbarContent(axis, docked: _docked),
        ),
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
            left: (_dockSide == 'left' || _dockSide == 'bottom') ? 0 : null,
            right: _dockSide == 'right' ? 0 : null,
            top: _dockSide == 'top'
                ? (_full ? 0 : 46)
                : (_dockSide == 'bottom' ? (_full ? 4 : 54) : null),
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
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: math.min(5, blur), sigmaY: math.min(5, blur)),
        child: Material(
          elevation: SnoteThemeController.instance.eInk ? 0 : 4,
          color: Theme.of(context).colorScheme.surface.withValues(alpha: .88),
          child: child,
        ),
      ),
    );
  }

  Widget _toolbarContent(Axis axis, {required bool docked}) {
    final pencaseTools = _toolKeysForLocation('toolbar')
        .map(_canvasToolForKey)
        .whereType<CanvasTool>()
        .toList();
    final auxiliaryTools = _toolKeysForLocation('toolbar')
        .where((key) => key == 'calculator' || key == 'screenshot')
        .toList();
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
          padding: const EdgeInsets.all(3),
          child: Icon(Icons.drag_indicator_rounded, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
      ...pencaseTools.map((tool) => _placedToolButton(tool.name, 'toolbar')),
      ...auxiliaryTools.map((key) => _placedToolButton(key, 'toolbar')),
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
            case 'placements':
              await _toolPlacementManagerSheet();
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
            case 'screenshot':
              await _exportLiveScreenshot();
              break;
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'calculator', child: Row(children: [Icon(Icons.calculate_outlined, size: 19), SizedBox(width: 10), Text('Calculator')])),
          PopupMenuItem(value: 'placements', child: Row(children: [Icon(Icons.widgets_outlined, size: 19), SizedBox(width: 10), Text('Manage tool placements')])),
          PopupMenuItem(value: 'templates', child: Row(children: [Icon(Icons.grid_4x4_rounded, size: 19), SizedBox(width: 10), Text('Page templates')])),
          PopupMenuItem(value: 'reading', child: Row(children: [Icon(Icons.chrome_reader_mode_outlined, size: 19), SizedBox(width: 10), Text('Reading mode')])),
          PopupMenuItem(value: 'timer', child: Row(children: [Icon(Icons.timer_outlined, size: 19), SizedBox(width: 10), Text('Study timer')])),
          PopupMenuItem(value: 'palm', child: Row(children: [Icon(Icons.back_hand_outlined, size: 19), SizedBox(width: 10), Text('Toggle palm rejection')])),
          PopupMenuItem(value: 'pdf', child: Row(children: [Icon(Icons.picture_as_pdf_outlined, size: 19), SizedBox(width: 10), Text('Insert PDF pages')])),
          PopupMenuItem(value: 'showcase', child: Row(children: [Icon(Icons.inventory_2_outlined, size: 19), SizedBox(width: 10), Text('Tool showcase')])),
          PopupMenuItem(value: 'cover', child: Row(children: [Icon(Icons.photo_album_outlined, size: 19), SizedBox(width: 10), Text('Note cover page')])),
          PopupMenuItem(value: 'screenshot', child: Row(children: [Icon(Icons.screenshot_monitor_rounded, size: 19), SizedBox(width: 10), Text('Save page screenshot')])),
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
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: IconButtonTheme(
          data: IconButtonThemeData(
            style: IconButton.styleFrom(
              fixedSize: const Size(32, 34),
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
      CanvasTool.fill: Icons.format_color_fill_rounded,
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
    final selectedLocations = <String>{
      ...(_resolvedToolPlacements()[target.name] ?? const <String>['hidden']),
    };
    const placementLocations = <String>['titleBar', 'toolbar', 'pencase', 'hidden'];
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
                            Row(children: [
                    const Icon(Icons.opacity_rounded, size: 18),
                    const SizedBox(width: 8),
                    Row(children: [
                    const Icon(Icons.opacity_rounded, size: 18),
                    const SizedBox(width: 8),
                    Text('Opacity: ${(opacity * 100).round()}%'),
                  ]),
                  ]),
                            Slider(
                              value: opacity.clamp(.05, 1).toDouble(),
                              min: .05,
                              max: 1,
                              onChanged: (value) {
                                setPopup(() => opacity = value);
                                unawaited(_commitToolOptions(target: target, size: size, color: color, opacity: value, fill: fill));
                              },
                            ),
                            const Row(children: [
                              Icon(Icons.palette_outlined, size: 18),
                              SizedBox(width: 8),
                              Text('Color', style: TextStyle(fontWeight: FontWeight.w800)),
                            ]),
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
                                secondary: const Icon(Icons.format_color_fill_outlined),
                                value: fill,
                                onChanged: (value) {
                                  setPopup(() => fill = value);
                                  unawaited(_commitToolOptions(target: target, size: size, color: color, opacity: opacity, fill: value));
                                },
                                title: const Text('Fill shape'),
                              ),
                            const Divider(height: 18),
                            const Row(children: [
                              Icon(Icons.place_outlined, size: 18),
                              SizedBox(width: 8),
                              Text('Display location', style: TextStyle(fontWeight: FontWeight.w900)),
                            ]),
                            ...placementLocations.map((location) => CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              secondary: Icon(_toolPlacementIcon(location), size: 19),
                              title: Text(_toolPlacementLabel(location)),
                              value: selectedLocations.contains(location) ||
                                  (location == 'hidden' && selectedLocations.isEmpty),
                              onChanged: (value) async {
                                setPopup(() {
                                  if (value == true) {
                                    if (location == 'hidden') {
                                      selectedLocations..clear()..add('hidden');
                                    } else {
                                      selectedLocations..remove('hidden')..add(location);
                                    }
                                  } else {
                                    selectedLocations.remove(location);
                                  }
                                });
                                final next = _resolvedToolPlacements();
                                next[target.name] = selectedLocations.isEmpty
                                    ? <String>['hidden']
                                    : selectedLocations.toList();
                                await _saveToolLayout(next, _toolOrder);
                              },
                            )),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  final next = _resolvedToolPlacements();
                                  next[target.name] = <String>['pencase'];
                                  await _saveToolLayout(next, _toolOrder);
                                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                                },
                                icon: const Icon(Icons.inventory_2_outlined, size: 18),
                                label: const Text('Collect to Pencase'),
                              ),
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
                            if (target == CanvasTool.lasso) ...[
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: _selected > 0
                                      ? () {
                                          Navigator.pop(dialogContext);
                                          unawaited(_convertSelectionToText());
                                        }
                                      : null,
                                  icon: const Icon(Icons.text_fields_rounded, size: 18),
                                  label: const Text('Convert selected ink to text'),
                                ),
                              ),
                            ],
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

  List<String> get _allToolKeys => <String>[
        ...CanvasTool.values.map((tool) => tool.name),
        'calculator',
        'screenshot',
      ];

  CanvasTool? _canvasToolForKey(String key) {
    for (final tool in CanvasTool.values) {
      if (tool.name == key) return tool;
    }
    return null;
  }

  Map<String, List<String>> _resolvedToolPlacements() {
    const validLocations = <String>{'titleBar', 'toolbar', 'pencase', 'hidden'};
    final saved = <String, List<String>>{};
    try {
      final decoded = jsonDecode(_settings.getString('toolPlacements'));
      if (decoded is Map) {
        for (final entry in decoded.entries) {
          if (entry.value is! List) continue;
          var locations = (entry.value as List)
              .map((value) => value.toString())
              .where(validLocations.contains)
              .toList();
          if (locations.contains('hidden') || locations.isEmpty) {
            locations = <String>['hidden'];
          } else {
            locations = locations.toSet().toList();
          }
          saved[entry.key.toString()] = locations;
        }
      }
    } catch (_) {
      // Safely migrate older settings that did not store a placement map.
    }

    final legacyToolbar = _settings
        .getString('pencaseTools')
        .split(',')
        .where((value) => value.isNotEmpty)
        .toSet();
    final result = <String, List<String>>{};
    for (final key in _allToolKeys) {
      if (saved.containsKey(key)) {
        result[key] = List<String>.from(saved[key]!);
      } else if (legacyToolbar.contains(key) ||
          key == 'calculator' ||
          key == 'screenshot') {
        result[key] = <String>['toolbar'];
      } else {
        result[key] = <String>['hidden'];
      }
    }
    return result;
  }

  List<String> get _toolOrder {
    final result = <String>[];
    final seen = <String>{};
    try {
      final decoded = jsonDecode(_settings.getString('toolOrder'));
      if (decoded is List) {
        for (final entry in decoded) {
          final key = entry.toString();
          if (_allToolKeys.contains(key) && seen.add(key)) result.add(key);
        }
      }
    } catch (_) {}
    for (final key in _settings.getString('pencaseTools').split(',')) {
      if (_allToolKeys.contains(key) && seen.add(key)) result.add(key);
    }
    for (final key in _allToolKeys) {
      if (seen.add(key)) result.add(key);
    }
    return result;
  }

  List<String> _toolKeysForLocation(String location) {
    final placements = _resolvedToolPlacements();
    return _toolOrder.where((key) => (placements[key] ?? const <String>[]).contains(location)).toList();
  }

  String _toolPlacementLabel(String location) {
    switch (location) {
      case 'titleBar': return 'Title Bar';
      case 'toolbar': return 'Toolbar';
      case 'pencase': return 'Pencase';
      default: return 'Hidden';
    }
  }

  IconData _toolPlacementIcon(String location) {
    switch (location) {
      case 'titleBar': return Icons.title_rounded;
      case 'toolbar': return Icons.widgets_outlined;
      case 'pencase': return Icons.inventory_2_outlined;
      default: return Icons.visibility_off_outlined;
    }
  }

  IconData _toolIconForKey(String key) {
    if (key == 'calculator') return Icons.calculate_outlined;
    if (key == 'screenshot') return Icons.screenshot_monitor_rounded;
    final tool = _canvasToolForKey(key);
    return tool == null ? Icons.widgets_outlined : _toolIcon(tool);
  }

  Future<void> _saveToolLayout(
    Map<String, List<String>> placements,
    List<String> order,
  ) async {
    const visibleLocations = <String>{'titleBar', 'toolbar', 'pencase'};
    final normalized = <String, List<String>>{};
    for (final key in _allToolKeys) {
      final locations = (placements[key] ?? const <String>[])
          .where(visibleLocations.contains)
          .toSet()
          .toList();
      normalized[key] = locations.isEmpty
          ? <String>['hidden']
          : locations;
    }

    final normalizedOrder = <String>[];
    final seen = <String>{};
    for (final key in order) {
      if (_allToolKeys.contains(key) && seen.add(key)) normalizedOrder.add(key);
    }
    for (final key in _allToolKeys) {
      if (seen.add(key)) normalizedOrder.add(key);
    }

    await _settings.setString('toolPlacements', jsonEncode(normalized));
    await _settings.setString('toolOrder', jsonEncode(normalizedOrder));
    await _settings.setString(
      'pencaseTools',
      normalizedOrder.where((key) =>
        _canvasToolForKey(key) != null &&
        (normalized[key] ?? const <String>[]).contains('toolbar')
      ).join(','),
    );
    if (mounted) setState(() {});
  }

  Widget _toolDropArea(String location, Widget child) => DragTarget<_ToolPlacementDrag>(
        onAcceptWithDetails: (details) => unawaited(
          _movePlacedTool(details.data.key, details.data.sourceLocation, location),
        ),
        builder: (context, candidates, rejected) => child,
      );

  Future<void> _movePlacedTool(
    String key,
    String sourceLocation,
    String targetLocation, {
    String? targetKey,
  }) async {
    if (!_allToolKeys.contains(key)) return;
    final placements = _resolvedToolPlacements()
        .map((name, values) => MapEntry(name, List<String>.from(values)));
    final order = _toolOrder..remove(key);
    final targetIndex = targetKey == null ? -1 : order.indexOf(targetKey);
    order.insert(targetIndex < 0 ? order.length : targetIndex, key);

    if (sourceLocation != targetLocation) {
      final locations = placements[key] ?? <String>['hidden'];
      locations.remove(sourceLocation);
      locations.remove('hidden');
      if (!locations.contains(targetLocation)) locations.add(targetLocation);
      placements[key] = locations.isEmpty ? <String>['hidden'] : locations;
    }
    await _saveToolLayout(placements, order);
  }

  Widget _placedToolButton(String key, String location) {
    final icon = _toolIconForKey(key);
    final tool = _canvasToolForKey(key);
    final active = tool != null && _tool == tool;
    final inner = tool != null
        ? _toolButton(tool, icon)
        : Tooltip(
            message: key == 'calculator'
                ? 'Calculator · double-tap for settings'
                : 'Screenshot / image · double-tap for settings',
            child: GestureDetector(
              onTap: () {
                _auxToolTapTimer?.cancel();
                _auxToolTapTimer = Timer(const Duration(milliseconds: 260), () {
                  if (mounted) _activatePlacedTool(key);
                });
              },
              onDoubleTap: () {
                _auxToolTapTimer?.cancel();
                _auxToolTapTimer = null;
                unawaited(_toolPlacementSheet(key));
              },
              child: SizedBox(
                width: 29,
                height: 30,
                child: Center(child: Icon(icon, size: 18)),
              ),
            ),
          );

    return DragTarget<_ToolPlacementDrag>(
      onAcceptWithDetails: (details) => unawaited(
        _movePlacedTool(
          details.data.key,
          details.data.sourceLocation,
          location,
          targetKey: key,
        ),
      ),
      builder: (context, candidates, rejected) => LongPressDraggable<_ToolPlacementDrag>(
        data: _ToolPlacementDrag(key, location),
        maxSimultaneousDrags: 1,
        feedback: Material(
          elevation: 8,
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, color: Theme.of(context).colorScheme.primary),
          ),
        ),
        childWhenDragging: Opacity(opacity: .25, child: inner),
        child: inner,
      ),
    );
  }

  void _activatePlacedTool(String key) {
    if (key == 'calculator') {
      unawaited(_calculatorSheet());
    } else if (key == 'screenshot') {
      unawaited(_insertScreenshot());
    } else {
      final tool = _canvasToolForKey(key);
      if (tool != null) _selectTool(tool);
    }
  }

  Future<void> _toolPlacementSheet(String key) async {
    final selected = <String>{
      ...(_resolvedToolPlacements()[key] ?? const <String>['hidden']),
    };
    const locations = <String>['titleBar', 'toolbar', 'pencase', 'hidden'];
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 22),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(_toolIconForKey(key), size: 26),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${_canvasToolForKey(key)?.label ?? (key == 'calculator' ? 'Calculator' : 'Screenshot / image')} settings',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  const Text('Choose one or more locations. Hidden removes the tool from all visible tool docks. Long-press a tool icon to reorder or move it.'),
                  const SizedBox(height: 8),
                  ...locations.map((location) => CheckboxListTile(
                    secondary: Icon(_toolPlacementIcon(location)),
                    title: Text(_toolPlacementLabel(location)),
                    value: selected.contains(location) || (location == 'hidden' && selected.isEmpty),
                    onChanged: (value) => setSheetState(() {
                      if (value == true) {
                        if (location == 'hidden') {
                          selected..clear()..add('hidden');
                        } else {
                          selected..remove('hidden')..add(location);
                        }
                      } else {
                        selected.remove(location);
                      }
                    }),
                  )),
                  const Divider(),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          final next = _resolvedToolPlacements();
                          next[key] = <String>['pencase'];
                          await _saveToolLayout(next, _toolOrder);
                          if (sheetContext.mounted) Navigator.pop(sheetContext);
                        },
                        icon: const Icon(Icons.inventory_2_outlined),
                        label: const Text('Collect to Pencase'),
                      ),
                      FilledButton.icon(
                        onPressed: () async {
                          final next = _resolvedToolPlacements();
                          next[key] = selected.isEmpty ? <String>['hidden'] : selected.toList();
                          await _saveToolLayout(next, _toolOrder);
                          if (sheetContext.mounted) Navigator.pop(sheetContext);
                        },
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Save locations'),
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

  Future<void> _toolPlacementManagerSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .78,
          child: Column(children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 4, 18, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Tool placements', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 0, 18, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Double-tap a visible tool for settings. Select any tool here to configure where it appears.'),
              ),
            ),
            Expanded(
              child: ListView(
                children: _toolOrder.map((key) {
                  final selected = _resolvedToolPlacements()[key] ?? const <String>['hidden'];
                  return ListTile(
                    leading: Icon(_toolIconForKey(key)),
                    title: Text(_canvasToolForKey(key)?.label ?? (key == 'calculator' ? 'Calculator' : 'Screenshot / image')),
                    subtitle: Text(selected.map(_toolPlacementLabel).join(' · ')),
                    trailing: const Icon(Icons.tune_rounded),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) unawaited(_toolPlacementSheet(key));
                      });
                    },
                  );
                }).toList(),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _toolPencaseWidget() {
    final keys = _toolKeysForLocation('pencase');
    if (keys.isEmpty) return const SizedBox.shrink();
    final size = MediaQuery.sizeOf(context);
    final left = (_toolPencaseX < 0
            ? math.max(0.0, size.width - 50)
            : _toolPencaseX)
        .clamp(0.0, math.max(0.0, size.width - 50))
        .toDouble();
    final top = _toolPencaseY.clamp(50.0, math.max(50.0, size.height - 100)).toDouble();
    final vertical = _toolPencaseDock == 'left' || _toolPencaseDock == 'right' || _toolPencaseDock == 'bottom';
    final children = <Widget>[
      GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _toolPencaseDock = 'free';
            _toolPencaseX = (left + details.delta.dx).clamp(0.0, math.max(0.0, size.width - 50)).toDouble();
            _toolPencaseY = (top + details.delta.dy).clamp(50.0, math.max(50.0, size.height - 100)).toDouble();
          });
        },
        onPanEnd: (_) async {
          await _settings.setString('toolPencaseDockSide', _toolPencaseDock);
          await _settings.setDouble('toolPencaseX', _toolPencaseX);
          await _settings.setDouble('toolPencaseY', _toolPencaseY);
        },
        child: const SizedBox(
          width: 34,
          height: 28,
          child: Icon(Icons.drag_indicator_rounded, size: 18),
        ),
      ),
      PopupMenuButton<String>(
        tooltip: 'Attach or float tool dock',
        onSelected: (side) async {
          setState(() => _toolPencaseDock = side);
          await _settings.setString('toolPencaseDockSide', side);
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'left', child: Text('Attach left')),
          PopupMenuItem(value: 'right', child: Text('Attach right')),
          PopupMenuItem(value: 'top', child: Text('Attach top')),
          PopupMenuItem(value: 'bottom', child: Text('Attach bottom')),
          PopupMenuItem(value: 'free', child: Text('Float freely')),
        ],
        icon: const Icon(Icons.dock_rounded, size: 18),
      ),
      ...keys.map((key) => _placedToolButton(key, 'pencase')),
    ];
    final axis = vertical ? Axis.vertical : Axis.horizontal;
    final panel = Material(
      elevation: SnoteThemeController.instance.eInk ? 0 : 6,
      color: Theme.of(context).colorScheme.surface.withValues(alpha: .94),
      borderRadius: BorderRadius.circular(12),
      child: _toolDropArea(
        'pencase',
        SingleChildScrollView(
          scrollDirection: axis,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Flex(direction: axis, mainAxisSize: MainAxisSize.min, children: children),
          ),
        ),
      ),
    );
    if (_toolPencaseDock == 'left') return Positioned(left: 0, top: top, child: panel);
    if (_toolPencaseDock == 'right') return Positioned(right: 0, top: top, child: panel);
    if (_toolPencaseDock == 'top') return Positioned(left: left, top: 46, child: panel);
    if (_toolPencaseDock == 'bottom') return Positioned(left: 0, top: top, child: panel);
    return Positioned(left: left, top: top, child: panel);
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
      CanvasTool.eraser, CanvasTool.lasso, CanvasTool.fill, CanvasTool.line,
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

  Future<void> _convertSelectionToText() async {
    final platform = defaultTargetPlatform;
    if (platform != TargetPlatform.android && platform != TargetPlatform.iOS) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Handwriting recognition is available on Android and iOS.')),
      );
      return;
    }

    final selected = _canvas.selectedStrokes
        .where((stroke) =>
            stroke.shape == null &&
            stroke.stickerText == null &&
            stroke.points.isNotEmpty)
        .toList(growable: false);
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Use the lasso to select handwritten ink first.')),
      );
      return;
    }

    final targetPage = pageData;
    final targetPageId = targetPage['id']?.toString();
    final points = selected.expand((stroke) => stroke.points).toList(growable: false);
    var left = points.first.position.dx;
    var right = left;
    var top = points.first.position.dy;
    var bottom = top;
    for (final point in points.skip(1)) {
      left = math.min(left, point.position.dx);
      right = math.max(right, point.position.dx);
      top = math.min(top, point.position.dy);
      bottom = math.max(bottom, point.position.dy);
    }

    final canvasObject = _canvasRenderKey.currentContext?.findRenderObject();
    final canvasSize = canvasObject is RenderBox &&
            canvasObject.size.width > 1 &&
            canvasObject.size.height > 1
        ? canvasObject.size
        : const Size(700, 990);
    const padding = 18.0;
    final logicalWidth = math.max(48.0, right - left + padding * 2);
    final logicalHeight = math.max(48.0, bottom - top + padding * 2);
    final scale = math.min(
      3.0,
      2048.0 / math.max(logicalWidth, logicalHeight),
    ).clamp(.75, 3.0).toDouble();
    final pixelWidth = math.max(1, (logicalWidth * scale).ceil()).toInt();
    final pixelHeight = math.max(1, (logicalHeight * scale).ceil()).toInt();
    final recorder = ui.PictureRecorder();
    final bitmapCanvas = ui.Canvas(recorder);
    bitmapCanvas.drawRect(
      Rect.fromLTWH(0, 0, pixelWidth.toDouble(), pixelHeight.toDouble()),
      Paint()..color = Colors.white,
    );
    bitmapCanvas.scale(scale);
    bitmapCanvas.translate(padding - left, padding - top);
    for (final stroke in selected) {
      final readablePen = stroke.pen.copyWith(
        color: const Color(0xff111827),
        opacity: 1,
      );
      InkRenderer.drawInk(bitmapCanvas, stroke.points, readablePen);
    }

    final picture = recorder.endRecording();
    ui.Image? image;
    TextRecognizer? recognizer;
    try {
      image = await picture.toImage(pixelWidth, pixelHeight);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) {
        throw StateError('Could not prepare handwriting for recognition.');
      }
      final input = InputImage.fromBitmap(
        bitmap: byteData.buffer.asUint8List(
          byteData.offsetInBytes,
          byteData.lengthInBytes,
        ),
        width: image.width,
        height: image.height,
        rotation: 0,
      );
      recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final recognized = (await recognizer.processImage(input)).text.trim();
      if (!mounted) return;
      if (recognized.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No text was recognized. Try selecting clearer handwriting.')),
        );
        return;
      }

      final targetPageIndex = _pages.indexWhere((page) => page['id']?.toString() == targetPageId);
      if (targetPageIndex < 0) {
        throw StateError('The source page no longer exists.');
      }
      final boundsWidth = math.max(1.0, right - left);
      final boundsHeight = math.max(1.0, bottom - top);
      final x = ((left - padding) / canvasSize.width).clamp(0.0, .92).toDouble();
      final y = ((top - padding) / canvasSize.height).clamp(0.0, .92).toDouble();
      final width = ((boundsWidth + padding * 2) / canvasSize.width)
          .clamp(.12, math.max(.12, 1.0 - x)).toDouble();
      final lineCount = '\n'.allMatches(recognized).length + 1;
      final height = ((boundsHeight + padding * 2 + lineCount * 8) / canvasSize.height)
          .clamp(.06, math.max(.06, 1.0 - y)).toDouble();
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      final box = <String, Object?>{
        'id': id,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'text': recognized,
        'fontSize': (boundsHeight / lineCount * .72).clamp(14.0, 28.0).toDouble(),
        'color': const Color(0xff172334).toARGB32(),
      };
      final page = _pages[targetPageIndex];
      final rawBoxes = page['textBoxes'];
      if (rawBoxes is List) {
        rawBoxes.add(box);
      } else {
        page['textBoxes'] = <Object?>[box];
      }
      _textBoxControllers[id] = TextEditingController(text: recognized);

      if (targetPageIndex == _page && identical(page, pageData)) {
        setState(() {});
        // Replace selected handwriting only after recognition has succeeded.
        _canvas.deleteSelection();
      } else {
        setState(() {});
      }
      _scheduleSave();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Handwriting converted to editable text.')),
      );
    } catch (error, stackTrace) {
      debugPrint('Snote selected handwriting recognition failed: $error\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not convert this selection. Your handwriting is unchanged.')),
        );
      }
    } finally {
      image?.dispose();
      picture.dispose();
      await recognizer?.close();
    }
  }

  Widget _selectionTools() {
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width > size.height;
    final axis = landscape ? Axis.horizontal : Axis.vertical;
    final controls = <Widget>[
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Tooltip(
          message: 'Drag to move selection tools',
          child: Icon(Icons.drag_indicator_rounded, size: 18),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Tooltip(
          message: '$_selected selected',
          child: Text(
            landscape ? '$_selected selected' : '$_selected',
            maxLines: 1,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
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
      IconButton(
        onPressed: () => unawaited(_convertSelectionToText()),
        icon: const Icon(Icons.text_fields_rounded),
        tooltip: 'Convert selected handwriting to text',
      ),
      IconButton(onPressed: _canvas.duplicateSelection, icon: const Icon(Icons.copy_rounded), tooltip: 'Duplicate'),
      IconButton(onPressed: _canvas.deleteSelection, icon: const Icon(Icons.delete_outline_rounded), tooltip: 'Delete'),
      IconButton(onPressed: _canvas.selectAll, icon: const Icon(Icons.select_all_rounded), tooltip: 'Select all'),
      IconButton(onPressed: _canvas.clearSelection, icon: const Icon(Icons.close_rounded), tooltip: 'Close'),
    ];

    return Positioned(
      left: _selectionToolbarX < 0 ? 8 : _selectionToolbarX,
      right: landscape && _selectionToolbarX < 0 ? 8 : null,
      top: _selectionToolbarY < 0
          ? (landscape ? null : 84.0)
          : _selectionToolbarY,
      bottom: landscape
          ? (_selectionToolbarY < 0 ? 82.0 : null)
          : 82.0,
      child: GestureDetector(
        onPanUpdate: (details) {
          final bounds = MediaQuery.sizeOf(context);
          final baseX = _selectionToolbarX < 0 ? 8.0 : _selectionToolbarX;
          final baseY = _selectionToolbarY < 0
              ? (landscape ? math.max(56.0, bounds.height - 150) : 84.0)
              : _selectionToolbarY;
          setState(() {
            _selectionToolbarX = (baseX + details.delta.dx)
                .clamp(4.0, math.max(4.0, bounds.width - (landscape ? 100 : 60)));
            _selectionToolbarY = (baseY + details.delta.dy)
                .clamp(52.0, math.max(52.0, bounds.height - (landscape ? 70 : 100)));
          });
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Material(
              color: Theme.of(context).colorScheme.surface.withValues(alpha: .90),
              child: SingleChildScrollView(
                scrollDirection: axis,
                child: axis == Axis.horizontal
                    ? Row(mainAxisSize: MainAxisSize.min, children: controls)
                    : Column(mainAxisSize: MainAxisSize.min, children: controls),
              ),
            ),
          ),
        ),
      ),
    );
  }

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

  void _copyPage(int index) {
    if (index < 0 || index >= _pages.length) return;
    _pageClipboard = _clonePage(_pages[index]);
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Page copied. Use a page menu to paste it.')),
    );
  }

  void _cutPage(int index) {
    if (index < 0 || index >= _pages.length) return;
    _pageClipboard = _clonePage(_pages[index]);
    _deletePage(index);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Page cut. Use a page menu to paste it.')),
    );
  }

  void _pastePage(int index) {
    final clipboard = _pageClipboard;
    if (clipboard == null) return;
    final pasted = _clonePage(clipboard);
    pasted['id'] = DateTime.now().microsecondsSinceEpoch.toString();
    final target = (index + 1).clamp(0, _pages.length).toInt();
    _pages.insert(target, pasted);
    setState(() => _page = target);
    _scheduleSave();
  }

  void _deletePage(int index) {
    if (index < 0 || index >= _pages.length) return;
    final removedId = _pages[index]['id']?.toString();
    if (removedId != null) {
      _thumbnailStrokeCache.remove(removedId);
      _thumbnailStrokeSources.remove(removedId);
    }
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

  List<Stroke> _thumbnailStrokesFor(Map<String, Object?> page) {
    final id = page['id']?.toString() ?? '';
    final raw = page['strokes'];
    if (id.isNotEmpty &&
        _thumbnailStrokeCache.containsKey(id) &&
        identical(_thumbnailStrokeSources[id], raw)) {
      return _thumbnailStrokeCache[id]!;
    }
    final strokes = StrokeCodec.documentToStrokes({'strokes': raw});
    if (id.isNotEmpty) {
      _thumbnailStrokeSources[id] = raw;
      _thumbnailStrokeCache[id] = strokes;
      while (_thumbnailStrokeCache.length > 12) {
        final oldest = _thumbnailStrokeCache.keys.first;
        _thumbnailStrokeCache.remove(oldest);
        _thumbnailStrokeSources.remove(oldest);
      }
    }
    return strokes;
  }

  Uint8List? _thumbnailBytes(String? encoded) {
    if (encoded == null || encoded.isEmpty) return null;
    final cacheKey = '${encoded.length}:${identityHashCode(encoded)}';
    final cached = _thumbnailRasterCache[cacheKey];
    if (cached != null) return cached;
    try {
      final bytes = base64Decode(encoded);
      if (bytes.isEmpty) return null;
      _thumbnailRasterCache[cacheKey] = bytes;
      while (_thumbnailRasterCache.length > 6) {
        _thumbnailRasterCache.remove(_thumbnailRasterCache.keys.first);
      }
      return bytes;
    } catch (error) {
      debugPrint('Snote thumbnail image decode failed: $error');
      return null;
    }
  }

  String _thumbnailRevisionKey(Map<String, Object?> page) {
    final rawBoxes = page['textBoxes'];
    final boxRevision = rawBoxes is List
        ? rawBoxes.map((item) => item is Map
            ? [
                item['id'],
                item['text'],
                item['x'],
                item['y'],
                item['width'],
                item['height'],
                item['fontSize'],
                item['color'],
              ].join(',')
            : '').join('|')
        : '';
    final rawImages = page['images'];
    final imageRevision = rawImages is List
        ? rawImages.whereType<Map>().map((item) => [
              item['id'],
              item['data'] is String ? identityHashCode(item['data']) : 0,
              item['x'],
              item['y'],
              item['width'],
              item['height'],
            ].join(',')).join('|')
        : '';
    final background = page['backgroundImage']?.toString() ?? '';
    return [
      page['id'],
      identityHashCode(page['strokes']),
      boxRevision,
      imageRevision,
      background.isEmpty ? 0 : '${background.length}:${identityHashCode(background)}',
      page['template'],
      page['paperColor'],
      page['lineColor'],
      page['lineOpacity'],
      page['spacing'],
      page['orientation'],
    ].join(':');
  }

  double _thumbnailAspectRatio(Map<String, Object?> page) {
    final ratio = switch (page['pageSize']?.toString() ?? 'A4') {
      'A3' => 297 / 420,
      'A5' => 148 / 210,
      'Letter' => 215.9 / 279.4,
      'Legal' => 215.9 / 355.6,
      'Infinite' => 1.0,
      _ => 210 / 297,
    };
    return page['orientation']?.toString() == 'horizontal' ? 1 / ratio : ratio;
  }

  Size _thumbnailSourceSize() {
    final object = _canvasRenderKey.currentContext?.findRenderObject();
    if (object is RenderBox &&
        object.size.width.isFinite &&
        object.size.height.isFinite &&
        object.size.width > 1 &&
        object.size.height > 1) {
      return object.size;
    }
    return const Size(700, 990);
  }

  Widget _previewRail() {
    final screen = MediaQuery.sizeOf(context);
    final railWidth = math.min(264.0, math.max(190.0, screen.width * .28));
    final previewWidth = railWidth - 20;
    final sourceSize = _thumbnailSourceSize();
    return Positioned(
      left: 0,
      top: 0,
      bottom: 0,
      width: railWidth,
      child: Material(
        elevation: SnoteThemeController.instance.eInk ? 0 : 8,
        color: Theme.of(context).colorScheme.surface,
        child: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 4, 4),
              child: Row(children: [
                const Icon(Icons.auto_stories_rounded, size: 18),
                const SizedBox(width: 8),
                const Expanded(child: Text('Pages', style: TextStyle(fontWeight: FontWeight.w900))),
                if (_pageClipboard != null)
                  IconButton(
                    tooltip: 'Paste copied page',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _pastePage(_pages.length - 1),
                    icon: const Icon(Icons.content_paste_rounded),
                  ),
                IconButton(
                  tooltip: 'Close pages',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _preview = false),
                  icon: const Icon(Icons.close_rounded),
                ),
              ]),
            ),
            Expanded(
              child: ReorderableListView.builder(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                cacheExtent: 260,
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
                  final pageColor = _pageColorAt(index);
                  final strokes = _thumbnailStrokesFor(page);
                  final revision = _thumbnailRevisionKey(page);
                  final aspectRatio = _thumbnailAspectRatio(page);
                  final thumbnailHeight = math.min(320.0, math.max(150.0, previewWidth / aspectRatio));
                  final secure = _settings.getBool('securePagePreviews');
                  final backgroundBytes = secure
                      ? null
                      : _thumbnailBytes(page['backgroundImage']?.toString());
                  final pageImages = page['images'] is List
                      ? (page['images'] as List)
                          .whereType<Map>()
                          .map((item) => item.cast<String, Object?>())
                          .toList()
                      : <Map<String, Object?>>[];
                  return Padding(
                    key: ValueKey(page['id'].toString()),
                    padding: const EdgeInsets.only(bottom: 9),
                    child: Material(
                      elevation: index == _page ? 2 : 0,
                      color: pageColor,
                      borderRadius: BorderRadius.circular(10),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _selectPage(index),
                        child: Container(
                          height: thumbnailHeight,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: index == _page
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.outlineVariant,
                              width: index == _page ? 2 : 1,
                            ),
                          ),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (backgroundBytes != null)
                                Positioned.fill(
                                  child: Image.memory(
                                    backgroundBytes,
                                    fit: BoxFit.fill,
                                    filterQuality: FilterQuality.low,
                                    gaplessPlayback: true,
                                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                                  ),
                                ),
                              RepaintBoundary(
                                child: CustomPaint(
                                  painter: _PageThumbnailPainter(
                                    page: page,
                                    strokes: strokes,
                                    sourceSize: sourceSize,
                                    secure: secure,
                                    paintBackground: backgroundBytes == null,
                                    revisionKey: revision,
                                  ),
                                  child: const SizedBox.expand(),
                                ),
                              ),
                              if (!secure)
                                ...pageImages.map((image) {
                                  final bytes = _thumbnailBytes(image['data']?.toString());
                                  if (bytes == null) return const SizedBox.shrink();
                                  final x = ((image['x'] as num?)?.toDouble() ?? .12).clamp(0.0, .95).toDouble();
                                  final y = ((image['y'] as num?)?.toDouble() ?? .16).clamp(0.0, .95).toDouble();
                                  final w = ((image['width'] as num?)?.toDouble() ?? .22).clamp(.05, 1.0 - x).toDouble();
                                  final h = ((image['height'] as num?)?.toDouble() ?? .12).clamp(.05, 1.0 - y).toDouble();
                                  return Positioned(
                                    left: x * previewWidth,
                                    top: y * thumbnailHeight,
                                    width: w * previewWidth,
                                    height: h * thumbnailHeight,
                                    child: Image.memory(
                                      bytes,
                                      fit: BoxFit.contain,
                                      filterQuality: FilterQuality.low,
                                      gaplessPlayback: true,
                                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                                    ),
                                  );
                                }),
                              Positioned(
                                left: 7,
                                top: 7,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.surface.withValues(alpha: .92),
                                    borderRadius: BorderRadius.circular(7),
                                    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    child: Text(
                                      'Page ${index + 1}',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: Theme.of(context).colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                right: 4,
                                top: 4,
                                child: Material(
                                  color: Theme.of(context).colorScheme.surface.withValues(alpha: .94),
                                  borderRadius: BorderRadius.circular(9),
                                  child: PopupMenuButton<String>(
                                    tooltip: 'Page actions',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                                    icon: const Icon(Icons.more_vert_rounded, size: 20),
                                    onSelected: (action) {
                                      switch (action) {
                                        case 'blank': _insertBlankPage(index); break;
                                        case 'duplicate': _duplicatePage(index); break;
                                        case 'background': unawaited(_changePageBackground(index)); break;
                                        case 'up': _movePageBy(index, -1); break;
                                        case 'down': _movePageBy(index, 1); break;
                                        case 'copy': _copyPage(index); break;
                                        case 'cut': _cutPage(index); break;
                                        case 'paste': _pastePage(index); break;
                                        case 'copyToNote': unawaited(_addPageToAnotherNote(index)); break;
                                        case 'cutToNote': unawaited(_addPageToAnotherNote(index, cut: true)); break;
                                        case 'delete': _deletePage(index); break;
                                      }
                                    },
                                    itemBuilder: (_) => <PopupMenuEntry<String>>[
                                      const PopupMenuItem<String>(
                                        value: 'blank',
                                        child: ListTile(dense: true, leading: Icon(Icons.note_add_outlined), title: Text('Insert blank page')),
                                      ),
                                      const PopupMenuItem<String>(
                                        value: 'duplicate',
                                        child: ListTile(dense: true, leading: Icon(Icons.control_point_duplicate_rounded), title: Text('Duplicate page')),
                                      ),
                                      const PopupMenuItem<String>(
                                        value: 'up',
                                        child: ListTile(dense: true, leading: Icon(Icons.keyboard_arrow_up_rounded), title: Text('Move up')),
                                      ),
                                      const PopupMenuItem<String>(
                                        value: 'down',
                                        child: ListTile(dense: true, leading: Icon(Icons.keyboard_arrow_down_rounded), title: Text('Move down')),
                                      ),
                                      const PopupMenuItem<String>(
                                        value: 'copy',
                                        child: ListTile(dense: true, leading: Icon(Icons.copy_rounded), title: Text('Copy page')),
                                      ),
                                      const PopupMenuItem<String>(
                                        value: 'cut',
                                        child: ListTile(dense: true, leading: Icon(Icons.content_cut_rounded), title: Text('Cut page')),
                                      ),
                                      if (_pageClipboard != null)
                                        const PopupMenuItem<String>(
                                          value: 'paste',
                                          child: ListTile(dense: true, leading: Icon(Icons.content_paste_rounded), title: Text('Paste page after this')),
                                        ),
                                      const PopupMenuItem<String>(
                                        value: 'background',
                                        child: ListTile(dense: true, leading: Icon(Icons.palette_outlined), title: Text('Change background')),
                                      ),
                                      const PopupMenuItem<String>(
                                        value: 'copyToNote',
                                        child: ListTile(dense: true, leading: Icon(Icons.note_add_outlined), title: Text('Add to another note')),
                                      ),
                                      const PopupMenuItem<String>(
                                        value: 'cutToNote',
                                        child: ListTile(dense: true, leading: Icon(Icons.folder_open_rounded), title: Text('Move to another note')),
                                      ),
                                      const PopupMenuItem<String>(
                                        value: 'delete',
                                        child: ListTile(dense: true, leading: Icon(Icons.delete_outline_rounded), title: Text('Delete page')),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (secure)
                                Positioned.fill(
                                  child: IgnorePointer(
                                    child: ColoredBox(
                                      color: pageColor.withValues(alpha: .28),
                                      child: const Center(child: Icon(Icons.lock_outline_rounded, size: 26)),
                                    ),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: SizedBox(
                width: double.infinity,
                height: 42,
                child: FilledButton.tonalIcon(
                  onPressed: _pages.isEmpty ? null : () => _insertBlankPage(_pages.length - 1),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add Page'),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

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
        builder: (_, setDialog) {
          void updatePaperColor(Color next) {
            setDialog(() => color = next);
            setState(() => pageData['paperColor'] = next.toARGB32());
            _scheduleSave();
          }

          return AlertDialog(
            title: const Text('Paper color'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(),
                  ),
                ),
                Slider(
                  value: color.red.toDouble(),
                  min: 0,
                  max: 255,
                  label: 'Red ' + color.red.toString(),
                  onChanged: (value) =>
                      updatePaperColor(color.withRed(value.round())),
                ),
                Slider(
                  value: color.green.toDouble(),
                  min: 0,
                  max: 255,
                  label: 'Green ' + color.green.toString(),
                  onChanged: (value) =>
                      updatePaperColor(color.withGreen(value.round())),
                ),
                Slider(
                  value: color.blue.toDouble(),
                  min: 0,
                  max: 255,
                  label: 'Blue ' + color.blue.toString(),
                  onChanged: (value) =>
                      updatePaperColor(color.withBlue(value.round())),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
            ],
          );
        },
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
                  Row(children: [
                    Icon(_toolIcon(target), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${target.label} options',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close settings',
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.line_weight_rounded, size: 18),
                    const SizedBox(width: 8),
                    Text('Stroke size: ${size.toStringAsFixed(1)} px', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ]),
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
                  const Row(children: [
                    Icon(Icons.palette_outlined, size: 18),
                    SizedBox(width: 8),
                    Text('Color', style: TextStyle(fontWeight: FontWeight.w800)),
                  ]),
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
                      secondary: const Icon(Icons.gesture_rounded),
                      value: pressureErase,
                      onChanged: (value) {
                        setModal(() => pressureErase = value);
                        unawaited(_settings.setBool('pressureErase', value));
                      },
                      title: const Text('Pressure-responsive radius'),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(Icons.radio_button_unchecked_rounded),
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
                    const Row(children: [
                      Icon(Icons.gesture_rounded, size: 18),
                      SizedBox(width: 8),
                      Text('Selection outline', style: TextStyle(fontWeight: FontWeight.w800)),
                    ]),
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
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _selected > 0
                          ? () {
                              Navigator.pop(dialogContext);
                              unawaited(_convertSelectionToText());
                            }
                          : null,
                      icon: const Icon(Icons.text_fields_rounded),
                      label: const Text('Convert selected ink to text'),
                    ),
                  ] else if (target.isShape) ...[
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: dashed,
                      onChanged: (value) {
                        setModal(() => dashed = value);
                        unawaited(_commitToolOptions(target: target, size: size, color: color, opacity: opacity, fill: fill, dashed: value, sides: sides));
                      },
                      secondary: const Icon(Icons.border_style_rounded),
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
                      secondary: const Icon(Icons.format_color_fill_outlined),
                      title: const Text('Fill shape'),
                    ),
                  if (target == CanvasTool.customPolygon)
                    ListTile(
                      leading: const Icon(Icons.hexagon_outlined),
                      title: Text('Polygon sides: $sides'),
                      subtitle: Slider(value: sides.toDouble(), min: 3, max: 24, divisions: 21, onChanged: (v) {
                          setModal(() => sides = v.round());
                          unawaited(_commitToolOptions(target: target, size: size, color: color, opacity: opacity, fill: fill, dashed: dashed, sides: v.round()));
                        }),
                    ),
                  if (target.isPen) ...[
                    const SizedBox(height: 6),
                    const Row(children: [
                      Icon(Icons.speed_rounded, size: 18),
                      SizedBox(width: 8),
                      Text('Pressure response', style: TextStyle(fontWeight: FontWeight.w800)),
                    ]),
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
                        leading: const Icon(Icons.tune_rounded),
                        title: Text('Custom pressure curve: ${exponent.toStringAsFixed(2)}'),
                        subtitle: Slider(value: exponent.clamp(.35, 2.5), min: .35, max: 2.5, onChanged: (v) {
                          setModal(() => exponent = v);
                          unawaited(_settings.setDouble('pressureExponent', v));
                          setState(() {});
                        }),
                      ),
                  ],
                  const SizedBox(height: 8),
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



class _AuxiliaryGuidePainter extends CustomPainter {
  final Color color;

  const _AuxiliaryGuidePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final center = Offset(size.width / 2, size.height / 2);
    final guidePaint = Paint()
      ..color = color.withValues(alpha: .22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..isAntiAlias = true;
    const dashLength = 5.0;
    const gapLength = 5.0;

    void dashedLine(Offset start, Offset end) {
      final distance = (end - start).distance;
      if (distance <= 0) return;
      final direction = (end - start) / distance;
      var offset = 0.0;
      while (offset < distance) {
        final next = math.min(offset + dashLength, distance);
        canvas.drawLine(
          start + direction * offset,
          start + direction * next,
          guidePaint,
        );
        offset = next + gapLength;
      }
    }

    dashedLine(Offset(0, center.dy), Offset(size.width, center.dy));
    dashedLine(Offset(center.dx, 0), Offset(center.dx, size.height));
    canvas.drawCircle(
      center,
      4,
      Paint()
        ..color = color.withValues(alpha: .85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..isAntiAlias = true,
    );
    canvas.drawCircle(center, 1.4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _AuxiliaryGuidePainter oldDelegate) =>
      color != oldDelegate.color;
}

class _PageThumbnailPainter extends CustomPainter {
  final Map<String, Object?> page;
  final List<Stroke> strokes;
  final Size sourceSize;
  final bool secure;
  final bool paintBackground;
  final String revisionKey;

  const _PageThumbnailPainter({
    required this.page,
    required this.strokes,
    required this.sourceSize,
    required this.secure,
    this.paintBackground = true,
    required this.revisionKey,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || sourceSize.isEmpty) return;
    final paperColor = page['paperColor'] is num
        ? Color((page['paperColor'] as num).toInt())
        : const Color(0xffffffff);
    final template = PageTemplate.values.firstWhere(
      (value) => value.name == page['template']?.toString(),
      orElse: () => PageTemplate.dotted,
    );
    final lineColor = page['lineColor'] is num
        ? Color((page['lineColor'] as num).toInt())
        : const Color(0xffaab2bd);
    final spacing = page['spacing'] is num ? (page['spacing'] as num).toDouble() : 20.0;
    final lineOpacity = page['lineOpacity'] is num ? (page['lineOpacity'] as num).toDouble() : .8;

    canvas.save();
    canvas.scale(size.width / sourceSize.width, size.height / sourceSize.height);
    if (paintBackground) {
      canvas.drawRect(Offset.zero & sourceSize, Paint()..color = paperColor);
      PageBackground(
        template: template,
        paperColor: paperColor,
        lineColor: lineColor,
        spacing: spacing,
        lineOpacity: lineOpacity,
        cornellAssist: page['cornellAssist'] == true,
        lineWidth: page['lineWidth'] is num ? (page['lineWidth'] as num).toDouble() : .7,
      ).paint(canvas, sourceSize);
    }

    if (!secure) {
      SnoteCanvasPainter(
        strokes: strokes,
        activeStroke: null,
        activePoints: const <StrokePoint>[],
        activePen: null,
        activeTool: null,
        activeFill: false,
        activeCustomSides: 6,
        activeStickerText: null,
        selectedIds: const <String>{},
        lassoPath: const <Offset>[],
        drawActive: false,
      ).paint(canvas, sourceSize);

      final rawBoxes = page['textBoxes'];
      if (rawBoxes is List) {
        for (final item in rawBoxes.whereType<Map>()) {
          final text = item['text']?.toString() ?? '';
          if (text.trim().isEmpty) continue;
          final x = (item['x'] as num?)?.toDouble() ?? .16;
          final y = (item['y'] as num?)?.toDouble() ?? .14;
          final width = (item['width'] as num?)?.toDouble() ?? .66;
          final height = (item['height'] as num?)?.toDouble() ?? .18;
          final fontSize = ((item['fontSize'] as num?)?.toDouble() ?? 18).clamp(7.0, 24.0).toDouble();
          final textColor = item['color'] is num
              ? Color((item['color'] as num).toInt())
              : const Color(0xff263238);
          final painter = TextPainter(
            text: TextSpan(text: text, style: TextStyle(color: textColor, fontSize: fontSize, height: 1.12)),
            textDirection: TextDirection.ltr,
            maxLines: math.max(1, (height * sourceSize.height / math.max(8.0, fontSize)).floor()).toInt(),
            ellipsis: '…',
          )..layout(maxWidth: math.max(1.0, width * sourceSize.width).toDouble());
          painter.paint(canvas, Offset(x * sourceSize.width, y * sourceSize.height));
        }
      }

    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PageThumbnailPainter oldDelegate) =>
      oldDelegate.revisionKey != revisionKey ||
      oldDelegate.sourceSize != sourceSize ||
      oldDelegate.secure != secure ||
      oldDelegate.paintBackground != paintBackground;
}

class _StudyTimerFloating extends StatefulWidget {
  final bool visible;
  final ValueChanged<bool> onVisibilityChanged;

  const _StudyTimerFloating({
    required this.visible,
    required this.onVisibilityChanged,
  });

  @override
  State<_StudyTimerFloating> createState() => _StudyTimerFloatingState();
}

class _StudyTimerFloatingState extends State<_StudyTimerFloating> {
  Timer? _ticker;
  int _durationSeconds = 25 * 60;
  int _remainingSeconds = 25 * 60;
  bool _running = false;
  double _x = 12;
  double _y = 96;

  String get _clock {
    final minutes = (_remainingSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_remainingSeconds % 60).toString().padLeft(2, '0');
    return minutes + ':' + seconds;
  }

  void _adjust(int delta) {
    if (_running) return;
    setState(() {
      _durationSeconds = (_durationSeconds + delta).clamp(60, 3 * 60 * 60).toInt();
      _remainingSeconds = _durationSeconds;
    });
  }

  void _preset(int minutes) {
    _ticker?.cancel();
    _ticker = null;
    setState(() {
      _running = false;
      _durationSeconds = minutes * 60;
      _remainingSeconds = _durationSeconds;
    });
  }

  void _toggleRunning() {
    if (_running) {
      _ticker?.cancel();
      _ticker = null;
      setState(() => _running = false);
      return;
    }
    if (_remainingSeconds <= 0) setState(() => _remainingSeconds = _durationSeconds);
    setState(() => _running = true);
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (ticker) {
      if (!mounted) {
        ticker.cancel();
        return;
      }
      if (_remainingSeconds <= 1) {
        ticker.cancel();
        _ticker = null;
        setState(() {
          _remainingSeconds = 0;
          _running = false;
        });
      } else {
        setState(() => _remainingSeconds -= 1);
      }
    });
  }

  void _reset() {
    _ticker?.cancel();
    _ticker = null;
    setState(() {
      _running = false;
      _remainingSeconds = _durationSeconds;
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final screen = MediaQuery.sizeOf(context);
    final maxLeft = math.max(4.0, screen.width - 274);
    final maxTop = math.max(48.0, screen.height - 230);
    return Positioned(
      left: _x.clamp(4.0, maxLeft).toDouble(),
      top: _y.clamp(48.0, maxTop).toDouble(),
      child: Material(
        elevation: 18,
        color: scheme.surface.withValues(alpha: .97),
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 262,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onPanUpdate: (details) {
                    setState(() {
                      _x = (_x + details.delta.dx).clamp(4.0, maxLeft).toDouble();
                      _y = (_y + details.delta.dy).clamp(48.0, maxTop).toDouble();
                    });
                  },
                  child: Row(children: [
                    Icon(Icons.drag_indicator_rounded, size: 18, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 5),
                    const Expanded(
                      child: Text('Focus timer', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints.tightFor(width: 26, height: 26),
                      padding: EdgeInsets.zero,
                      tooltip: 'Hide timer',
                      onPressed: () => widget.onVisibilityChanged(false),
                      icon: const Icon(Icons.close_rounded, size: 17),
                    ),
                  ]),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [scheme.primaryContainer, scheme.tertiaryContainer],
                    ),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Column(children: [
                    Text(
                      _clock,
                      style: TextStyle(
                        fontSize: 29,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.1,
                        color: scheme.onPrimaryContainer,
                        fontFeatures: const [ui.FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      _running
                          ? 'Timer running — keep writing'
                          : _remainingSeconds == 0
                              ? 'Session complete'
                              : 'Adjust time, then start',
                      style: TextStyle(fontSize: 10, color: scheme.onPrimaryContainer),
                    ),
                  ]),
                ),
                const SizedBox(height: 7),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final minutes in const [15, 25, 45])
                      ChoiceChip(
                        label: Text(minutes.toString() + 'm'),
                        selected: _durationSeconds == minutes * 60,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        onSelected: _running ? null : (_) => _preset(minutes),
                      ),
                  ],
                ),
                Row(children: [
                  IconButton(
                    tooltip: 'Subtract one minute',
                    visualDensity: VisualDensity.compact,
                    onPressed: _running ? null : () => _adjust(-60),
                    icon: const Icon(Icons.remove_circle_outline_rounded),
                  ),
                  const Expanded(
                    child: Center(child: Text('Minutes', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
                  ),
                  IconButton(
                    tooltip: 'Add one minute',
                    visualDensity: VisualDensity.compact,
                    onPressed: _running ? null : () => _adjust(60),
                    icon: const Icon(Icons.add_circle_outline_rounded),
                  ),
                ]),
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(vertical: 7),
                      ),
                      onPressed: _toggleRunning,
                      icon: Icon(_running ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 18),
                      label: Text(_running ? 'Pause' : 'Start'),
                    ),
                  ),
                  const SizedBox(width: 7),
                  IconButton.filledTonal(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Reset timer',
                    onPressed: _reset,
                    icon: const Icon(Icons.restart_alt_rounded),
                  ),
                ]),
              ],
            ),
          ),
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
