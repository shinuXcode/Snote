import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../input/palm_rejection.dart';
import '../models/pen_config.dart';
import '../models/stroke.dart';
import '../models/stroke_codec.dart';
import '../painters/canvas_painter.dart';
import 'snote_canvas_controller.dart';

class SnoteCanvas extends StatefulWidget {
  final PenConfig pen;
  final CanvasTool tool;
  final ValueChanged<Map<String, Object?>>? onChanged;
  final ValueChanged<int>? onSelectionChanged;
  final Map<String, Object?>? initialDocument;
  final SnoteCanvasController? controller;
  final Color backgroundColor;
  final bool shapeFill;
  final int customShapeSides;
  final String? stickerText;
  final VoidCallback? onStylusDoubleTap;

  const SnoteCanvas({
    super.key,
    required this.pen,
    this.tool = CanvasTool.ballpoint,
    this.onChanged,
    this.onSelectionChanged,
    this.initialDocument,
    this.controller,
    this.backgroundColor = Colors.white,
    this.shapeFill = false,
    this.customShapeSides = 6,
    this.stickerText,
    this.onStylusDoubleTap,
  });

  @override
  State<SnoteCanvas> createState() => _SnoteCanvasState();
}

class _SnoteCanvasState extends State<SnoteCanvas> {
  final _uuid = const Uuid();
  final _palmRejection = PalmRejection();
  final _repaint = ChangeNotifier();
  final List<Stroke> _strokes = [];
  final List<List<Stroke>> _history = [];
  final List<List<Stroke>> _redo = [];
  final Set<String> _selected = <String>{};
  final List<Offset> _lassoPath = <Offset>[];
  final List<StrokePoint> _activePoints = <StrokePoint>[];

  Stroke? _activeStroke;
  PenConfig? _activePen;
  CanvasTool? _activeTool;
  String? _activeSticker;
  int _activePointer = -1;
  bool _ignorePointer = false;
  DateTime? _lastStylusTap;
  Offset? _lastStylusPosition;

  @override
  void initState() {
    super.initState();
    _replaceDocument(widget.initialDocument);
    _bindController();
  }

  @override
  void didUpdateWidget(covariant SnoteCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.unbind();
      _bindController();
    }
    if (!identical(oldWidget.initialDocument, widget.initialDocument)) {
      _replaceDocument(widget.initialDocument, clearHistory: false);
    }
  }

  @override
  void dispose() {
    widget.controller?.unbind();
    _repaint.dispose();
    super.dispose();
  }

  void _replaceDocument(Map<String, Object?>? document, {bool clearHistory = true}) {
    _strokes
      ..clear()
      ..addAll(StrokeCodec.documentToStrokes(document));
    _selected.clear();
    _lassoPath.clear();
    if (clearHistory) {
      _history.clear();
      _redo.clear();
    }
    if (mounted) setState(() {});
    _notifySelection();
  }

  void _bindController() => widget.controller?.bind(
    undo: undo,
    redo: redo,
    clear: clear,
    deleteSelection: deleteSelection,
    duplicateSelection: duplicateSelection,
    moveSelection: moveSelection,
    selectAll: selectAll,
    clearSelection: clearSelection,
    canUndo: _history.isNotEmpty,
    canRedo: _redo.isNotEmpty,
    selectionCount: _selected.length,
  );

  void _snapshot() {
    _history.add(List<Stroke>.of(_strokes));
    if (_history.length > 80) _history.removeAt(0);
    _redo.clear();
  }

  void undo() {
    if (_history.isEmpty) return;
    _redo.add(List<Stroke>.of(_strokes));
    _strokes..clear()..addAll(_history.removeLast());
    _selected.clear();
    _notifyAndRefresh();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _history.add(List<Stroke>.of(_strokes));
    _strokes..clear()..addAll(_redo.removeLast());
    _selected.clear();
    _notifyAndRefresh();
  }

  void clear() {
    if (_strokes.isEmpty) return;
    _snapshot();
    _strokes.clear();
    _selected.clear();
    _notifyAndRefresh();
  }

  void deleteSelection() {
    if (_selected.isEmpty) return;
    _snapshot();
    _strokes.removeWhere((s) => _selected.contains(s.id));
    _selected.clear();
    _notifyAndRefresh();
  }

  void duplicateSelection() {
    if (_selected.isEmpty) return;
    _snapshot();
    final copies = <Stroke>[];
    for (final s in _strokes) {
      if (!_selected.contains(s.id)) continue;
      copies.add(s.copyWith(
        id: _uuid.v4(),
        points: s.points.map((p) => StrokePoint(
          position: p.position + const Offset(18, 18),
          pressure: p.pressure,
          timestamp: p.timestamp,
        )).toList(),
      ));
    }
    _strokes.addAll(copies);
    _selected..clear()..addAll(copies.map((s) => s.id));
    _notifyAndRefresh();
  }

  void moveSelection(double dx, double dy) {
    if (_selected.isEmpty) return;
    _snapshot();
    for (var i = 0; i < _strokes.length; i++) {
      final s = _strokes[i];
      if (!_selected.contains(s.id)) continue;
      _strokes[i] = s.copyWith(
        points: s.points.map((p) => StrokePoint(
          position: p.position + Offset(dx, dy),
          pressure: p.pressure,
          timestamp: p.timestamp,
        )).toList(),
      );
    }
    _notifyAndRefresh();
  }

  void selectAll() {
    _selected..clear()..addAll(_strokes.map((s) => s.id));
    _notifySelection();
  }

  void clearSelection() {
    _selected.clear();
    _notifySelection();
  }

  void _notifySelection() {
    if (mounted) setState(() {});
    _bindController();
    widget.onSelectionChanged?.call(_selected.length);
  }

  void _notifyAndRefresh() {
    if (!mounted) return;
    setState(() {});
    _bindController();
    widget.onChanged?.call(StrokeCodec.strokesToDocument(_strokes));
    widget.onSelectionChanged?.call(_selected.length);
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: widget.backgroundColor,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _pointerDown,
        onPointerMove: _pointerMove,
        onPointerUp: _pointerUp,
        onPointerCancel: _pointerCancel,
        child: CustomPaint(
          painter: SnoteCanvasPainter(
            strokes: _strokes,
            activeStroke: _activeStroke,
            activePoints: _activePoints,
            activePen: _activePen,
            activeTool: _activeTool,
            activeFill: widget.shapeFill,
            activeCustomSides: widget.customShapeSides,
            activeStickerText: _activeSticker,
            selectedIds: _selected,
            lassoPath: _lassoPath,
            repaint: _repaint,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  bool _accept(PointerEvent event) => _palmRejection.accepts(event);

  void _pointerDown(PointerDownEvent event) {
    if (!_accept(event) || _activePointer != -1) return;
    _ignorePointer = false;

    if (event.kind == PointerDeviceKind.stylus &&
        widget.onStylusDoubleTap != null &&
        widget.tool == CanvasTool.ballpoint) {
      final now = DateTime.now();
      if (_lastStylusTap != null &&
          now.difference(_lastStylusTap!) < const Duration(milliseconds: 270) &&
          _lastStylusPosition != null &&
          (event.localPosition - _lastStylusPosition!).distance < 30) {
        _ignorePointer = true;
        _lastStylusTap = null;
        widget.onStylusDoubleTap!();
        return;
      }
    }

    _activePointer = event.pointer;
    final point = event.localPosition;

    if (widget.tool == CanvasTool.lasso) {
      _lassoPath..clear()..add(point);
      _repaint.notifyListeners();
      return;
    }

    if (widget.tool == CanvasTool.eraser) {
      _eraseAt(point);
      return;
    }

    _activeTool = widget.tool;
    _activePen = widget.pen;
    _activeSticker = widget.tool == CanvasTool.sticker ? widget.stickerText : null;
    _activePoints
      ..clear()
      ..add(_sample(point, event.pressure, event.timeStamp));
    if (widget.tool == CanvasTool.sticker) {
      _commitActive();
    } else {
      _repaint.notifyListeners();
    }
  }

  StrokePoint _sample(Offset position, double pressure, Duration timeStamp) {
    return StrokePoint(
      position: position,
      pressure: pressure.isNaN ? 1 : pressure.clamp(0, 1),
      timestamp: timeStamp.inMicroseconds / 1000,
    );
  }

  void _pointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer || _ignorePointer) return;

    if (widget.tool == CanvasTool.eraser) {
      _eraseAt(event.localPosition);
      return;
    }
    if (widget.tool == CanvasTool.lasso) {
      _lassoPath.add(event.localPosition);
      _repaint.notifyListeners();
      return;
    }
    if (_activePen == null || _activeTool == null) return;

    final position = event.localPosition;
    if (_activePoints.isNotEmpty &&
        (position - _activePoints.last.position).distance < .7) {
      return;
    }

    _activePoints.add(_sample(position, event.pressure, event.timeStamp));
    _repaint.notifyListeners();
  }

  void _pointerUp(PointerUpEvent event) {
    if (event.pointer != _activePointer) return;

    if (_ignorePointer) {
      _ignorePointer = false;
      _activePointer = -1;
      return;
    }

    if (widget.tool == CanvasTool.lasso) {
      _finishLasso();
    } else if (widget.tool != CanvasTool.eraser && widget.tool != CanvasTool.sticker) {
      if (_activePoints.isNotEmpty) _commitActive();
    }

    if (event.kind == PointerDeviceKind.stylus) {
      _lastStylusTap = DateTime.now();
      _lastStylusPosition = event.localPosition;
    }
    _activePointer = -1;
  }

  void _pointerCancel(PointerCancelEvent event) {
    if (event.pointer != _activePointer) return;
    _cancelActive();
    _activePointer = -1;
  }

  void _cancelActive() {
    _activeStroke = null;
    _activePen = null;
    _activeTool = null;
    _activeSticker = null;
    _activePoints.clear();
    _lassoPath.clear();
    _repaint.notifyListeners();
  }

  void _commitActive() {
    if (_activePoints.isEmpty || _activePen == null || _activeTool == null) {
      _cancelActive();
      return;
    }

    _snapshot();
    final stroke = Stroke(
      id: _uuid.v4(),
      points: List<StrokePoint>.of(_activePoints),
      pen: _activePen!,
      shape: _activeTool!.isShape ? _activeTool!.name : null,
      fill: widget.shapeFill && _activeTool!.isShape,
      customSides: widget.customShapeSides,
      stickerText: _activeSticker,
    );
    _strokes.add(stroke);
    _activeStroke = null;
    _activePoints.clear();
    _activePen = null;
    _activeTool = null;
    _activeSticker = null;
    _notifyAndRefresh();
  }

  void _eraseAt(Offset point) {
    final radius = (widget.pen.size * 3.3).clamp(16, 44);
    final hit = _strokes.indexWhere((s) {
      for (final p in s.points) {
        if ((p.position - point).distance <= radius) return true;
      }
      return false;
    });
    if (hit < 0) return;
    _snapshot();
    _strokes.removeAt(hit);
    _selected.removeWhere((id) => !_strokes.any((s) => s.id == id));
    _notifyAndRefresh();
  }

  void _finishLasso() {
    if (_lassoPath.length < 3) {
      _lassoPath.clear();
      _repaint.notifyListeners();
      _notifySelection();
      return;
    }
    final polygon = List<Offset>.of(_lassoPath);
    _selected.clear();
    for (final stroke in _strokes) {
      if (stroke.points.any((p) => _pointInPolygon(p.position, polygon))) {
        _selected.add(stroke.id);
      }
    }
    _lassoPath.clear();
    _notifySelection();
  }

  bool _pointInPolygon(Offset point, List<Offset> polygon) {
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final a = polygon[i];
      final b = polygon[j];
      final intersects = ((a.dy > point.dy) != (b.dy > point.dy)) &&
          point.dx < (b.dx - a.dx) * (point.dy - a.dy) /
              ((b.dy - a.dy).abs() < .0001 ? .0001 : (b.dy - a.dy)) +
              a.dx;
      if (intersects) inside = !inside;
    }
    return inside;
  }
}
