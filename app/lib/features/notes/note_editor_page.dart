import 'dart:math' as math;
import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/theme_controller.dart';
import '../../canvas_engine/models/pen_config.dart';
import '../../canvas_engine/widgets/page_background.dart';
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

class _NoteEditorPageState extends State<NoteEditorPage> {
  final _repo = NoteRepository();
  final _canvas = SnoteCanvasController();
  final _quill = QuillController.basic();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final _title = TextEditingController();
  final _lock = const NoteLockService();
  final _settings = SnoteSettings.instance;

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
  int _sides = 6;
  Color? _fillColor;
  bool _shapePanel = false;
  String? _sticker;
  int _selected = 0;
  Timer? _saveTimer;
  bool _savePending = false;
  bool _saveInFlight = false;

  Map<String, Object?> get pageData => _pages[_page];
  PenConfig get pen => PenConfig(
        type: _tool.penType,
        color: _penColor,
        size: _penSize,
        opacity: _tool == CanvasTool.highlighter ? _opacity.clamp(.08, .55) : _opacity,
        pressureSensitivity: _pressureSensitivity,
        velocitySensitivity: _velocitySensitivity,
      );

  @override
  void initState() {
    super.initState();
    _title.text = widget.note.title;
    _quill.addListener(_scheduleSave);
    _prepare();
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
    return p;
  }

  Map<String, Object?> _newPage() => {
        'id': DateTime.now().microsecondsSinceEpoch.toString(),
        'template': PageTemplate.dotted.name,
        'paperColor': 0xffffffff,
        'lineColor': 0xffd8dee8,
        'lineOpacity': .85,
        'spacing': 28.0,
        'cornellAssist': false,
        'orientation': 'vertical',
        'strokes': <Object?>[],
      };

  void _restoreToolbar() {
    final x = pageData['toolbarX'];
    final y = pageData['toolbarY'];
    final dock = pageData['toolbarDock']?.toString();
    if (x is num) _toolbarX = x.toDouble();
    if (y is num) _toolbarY = y.toDouble();
    _toolbarOffset.value = Offset(_toolbarX, _toolbarY);
    if (dock != null && dock != 'free') {
      _docked = true;
      _dockSide = dock;
    }
  }

  void _scheduleSave() {
    if (_loading || (_locked && !_unlocked)) return;
    _savePending = true;
    _saveTimer?.cancel();
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
    setState(() {
      _page = value;
      _selected = 0;
    });