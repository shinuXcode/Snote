import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:uuid/uuid.dart';

import '../input/ink_input_pipeline.dart';
import '../input/palm_rejection.dart';
import '../models/pen_config.dart';
import '../models/stroke.dart';
import '../models/stroke_codec.dart';
import '../painters/canvas_painter.dart';
import '../performance/writing_performance.dart';
import 'snote_canvas_controller.dart';

class _CanvasRepaint extends ChangeNotifier {
  void repaint() => notifyListeners();
}

class SnoteCanvas extends StatefulWidget {
  final PenConfig pen;
  final CanvasTool tool;
  final ValueChanged<Map<String, Object?>>? onChanged;
  final ValueChanged<int>? onSelectionChanged;
  final VoidCallback? onEraserMiss;
  final bool autoRecognition;
  final Map<String, Object?>? initialDocument;
  final SnoteCanvasController? controller;
  final Color backgroundColor;
  final bool shapeFill;
  final int customShapeSides;
  final String? stickerText;
  final VoidCallback? onStylusDoubleTap;
  final bool pressureErase;
  final bool pressureEraseArea;
  final double pressureEraseThreshold;
  final bool eraseWithStylusButton;
  final bool eraseMark;
  final bool dashed;
  final Color? fillColor;
  final double smoothing;
  final bool showPerformanceOverlay;

  const SnoteCanvas({
    super.key,
    required this.pen,
    this.tool = CanvasTool.ballpoint,
    this.onChanged,
    this.onSelectionChanged,
    this.onEraserMiss,
    this.autoRecognition = true,
    this.initialDocument,
    this.controller,
    this.backgroundColor = Colors.white,
    this.shapeFill = false,
    this.customShapeSides = 6,
    this.stickerText,
    this.onStylusDoubleTap,
    this.pressureErase = true,
    this.pressureEraseArea = true,
    this.pressureEraseThreshold = .35,
    this.eraseWithStylusButton = true,
    this.eraseMark = true,
    this.dashed = false,
    this.fillColor,
    this.smoothing = .72,
    this.showPerformanceOverlay = false,
  });

  @override
  State<SnoteCanvas> createState() => _SnoteCanvasState();
}

class _SnoteCanvasState extends State<SnoteCanvas> {
  final _uuid = const Uuid();
  final _palmRejection = PalmRejection();
  final _repaint = _CanvasRepaint();
  final _performance = WritingPerformanceStats(
    enabled: const bool.fromEnvironment('SNOTE_PERF'),
  );
  final List<Stroke> _strokes = [];
  final List<List<Stroke>> _history = [];
  final List<List<Stroke>> _redo = [];
  final Set<String> _selected = <String>{};
  final List<Offset> _lassoPath = <Offset>[];

  List<StrokePoint> _activeRealPoints = const <StrokePoint>[];
  List<StrokePoint> _activeLivePoints = const <StrokePoint>[];

  InkInputPipeline? _input;
  Offset? _eraserPoint;
  double _eraserRadius = 0;
  bool _temporaryEraser = false;
  CanvasTool? _activeTool;
  PenConfig? _activePen;
  String? _activeSticker;
  int _activePointer = -1;
  bool _ignorePointer = false;
  bool _eraseSnapshotTaken = false;
  bool _latencyCallbackScheduled = false;
  DateTime? _lastStylusTap;
  Offset? _lastStylusPosition;
  DateTime? _lastInputWallClock;

  bool get _perfEnabled => _performance.enabled;

  @override
  void initState() {
    super.initState();
    _input = InkInputPipeline(smoothing: widget.smoothing);
    _replaceDocument(widget.initialDocument);
    _bindController();
    _performance.attachScheduler();
  }

  @override
  void didUpdateWidget(covariant SnoteCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.unbind();
      _bindController();
    }
    if (oldWidget.smoothing != widget.smoothing) {
      _input = InkInputPipeline(smoothing: widget.smoothing);
    }
    if (!identical(oldWidget.initialDocument, widget.initialDocument)) {
      _replaceDocument(widget.initialDocument, clearHistory: false);
    }
  }

  @override
  void dispose() {
    _performance.detachScheduler();
    widget.controller?.unbind();
    _repaint.dispose();
    _performance.dispose();
    super.dispose();
  }

  void _replaceDocument(
    Map<String, Object?>? document, {
    bool clearHistory = true,
  }) {
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
    _performance.setDocumentStats(
      strokes: _strokes.length,
      visible: _strokes.length,
    );
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
    _strokes
      ..clear()
      ..addAll(_history.removeLast());
    _selected.clear();
    _notifyAndRefresh();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _history.add(List<Stroke>.of(_strokes));
    _strokes
      ..clear()
      ..addAll(_redo.removeLast());
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
      copies.add(
        s.copyWith(
          id: _uuid.v4(),
          points: s.points
              .map(
                (p) => p.copyWith(
                  position: p.position + const Offset(18, 18),
                ),
              )
              .toList(),
        ),
      );
    }
    _strokes.addAll(copies);
    _selected
      ..clear()
      ..addAll(copies.map((s) => s.id));
    _notifyAndRefresh();
  }

  void moveSelection(double dx, double dy) {
    if (_selected.isEmpty) return;
    _snapshot();
    for (var i = 0; i < _strokes.length; i++) {
      final s = _strokes[i];
      if (!_selected.contains(s.id)) continue;
      _strokes[i] = s.copyWith(
        points: s.points
            .map((p) => p.copyWith(position: p.position + Offset(dx, dy)))
            .toList(),
      );
    }
    _notifyAndRefresh();
  }

  void selectAll() {
    _selected
      ..clear()
      ..addAll(_strokes.map((s) => s.id));
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
    _performance.setDocumentStats(
      strokes: _strokes.length,
      visible: _strokes.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: widget.backgroundColor,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _pointerDown,
            onPointerMove: _pointerMove,
            onPointerUp: _pointerUp,
            onPointerCancel: _pointerCancel,
            onPointerHover: _pointerHover,
            child: Stack(
              fit: StackFit.expand,
              children: [
                RepaintBoundary(
                  child: CustomPaint(
                    painter: SnoteCanvasPainter(
                      strokes: List<Stroke>.unmodifiable(_strokes),
                      activeStroke: null,
                      activePoints: const <StrokePoint>[],
                      activePen: null,
                      activeTool: null,
                      activeFill: false,
                      activeCustomSides: widget.customShapeSides,
                      activeStickerText: null,
                      selectedIds:
                          Set<String>.unmodifiable(_selected),
                      lassoPath: const <Offset>[],
                      drawStrokes: true,
                      drawActive: false,
                    ),
                  ),
                ),
                CustomPaint(
                  painter: SnoteCanvasPainter(
                    strokes: const <Stroke>[],
                    activeStroke: null,
                    activePoints: _activeLivePoints,
                    activePen: _activePen,
                    activeTool: _activeTool,
                    activeFill: widget.shapeFill,
                    activeCustomSides: widget.customShapeSides,
                    activeStickerText: _activeSticker,
                    selectedIds: const <String>{},
                    lassoPath: _lassoPath,
                    eraserPoint: _eraserPoint,
                    eraserRadius: _eraserRadius,
                    showEraserMark: widget.eraseMark,
                    drawStrokes: false,
                    drawActive: true,
                    repaint: _repaint,
                  ),
                ),
              ],
            ),
          ),
          if (widget.showPerformanceOverlay && _perfEnabled)
            WritingPerformanceOverlay(stats: _performance),
        ],
      ),
    );
  }

  bool _accept(PointerEvent event) =>
      _palmRejection.accepts(event);

  void _recordInput() {
    if (!_perfEnabled) return;
    _performance.pointerEvent();
    _lastInputWallClock = DateTime.now();
    if (_latencyCallbackScheduled) return;
    _latencyCallbackScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _latencyCallbackScheduled = false;
      final inputAt = _lastInputWallClock;
      if (mounted && inputAt != null) {
        _performance.setLatency(inputAt);
      }
    });
  }

  void _pointerDown(PointerDownEvent event) {
    _recordInput();
    if (!_accept(event) || _activePointer != -1) return;
    _ignorePointer = false;

    final stylusButtonErase =
        (event.buttons & kSecondaryStylusButton) != 0;
    _temporaryEraser =
        widget.eraseWithStylusButton &&
        (event.kind == PointerDeviceKind.invertedStylus ||
            (event.kind == PointerDeviceKind.stylus &&
                stylusButtonErase));

    if (event.kind == PointerDeviceKind.stylus &&
        widget.onStylusDoubleTap != null &&
        widget.tool == CanvasTool.ballpoint) {
      final now = DateTime.now();
      if (_lastStylusTap != null &&
          now.difference(_lastStylusTap!) <
              const Duration(milliseconds: 270) &&
          _lastStylusPosition != null &&
          (event.localPosition - _lastStylusPosition!).distance < 30) {
        _ignorePointer = true;
        _lastStylusTap = null;
        widget.onStylusDoubleTap!();
        return;
      }
    }

    _activePointer = event.pointer;

    if (_temporaryEraser ||
        widget.tool == CanvasTool.eraser ||
        widget.tool == CanvasTool.pixelEraser) {
      _activeTool = widget.tool == CanvasTool.pixelEraser
          ? CanvasTool.pixelEraser
          : CanvasTool.eraser;
      _activePen = widget.pen;
      _eraserPoint = event.localPosition;
      _eraserRadius = _eraseRadius(event.pressure);
      if (!_eraseSnapshotTaken) {
        _snapshot();
        _eraseSnapshotTaken = true;
      }
      if (_activeTool == CanvasTool.pixelEraser) {
        _erasePixelAt(
          event.localPosition,
          pressure: event.pressure,
          snapshotAlreadyTaken: true,
        );
      } else {
        _eraseAt(
          event.localPosition,
          pressure: event.pressure,
          snapshotAlreadyTaken: true,
        );
      }
      _repaint.repaint();
      return;
    }

    if (widget.tool == CanvasTool.lasso) {
      _lassoPath
        ..clear()
        ..add(event.localPosition);
      _repaint.repaint();
      return;
    }

    _activeTool = widget.tool;
    _activePen = widget.pen;
    _activeSticker =
        widget.tool == CanvasTool.sticker
            ? widget.stickerText
            : null;

    final frame = _input!.begin(event);
    _activeRealPoints = frame.realPoints;
    _activeLivePoints = frame.livePoints;

    if (widget.tool == CanvasTool.sticker) {
      _commitActive();
    } else {
      _repaint.repaint();
    }
  }

  void _pointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer ||
        _ignorePointer) {
      return;
    }
    _recordInput();

    if (_activeTool == CanvasTool.eraser ||
        _activeTool == CanvasTool.pixelEraser ||
        _temporaryEraser) {
      _eraserPoint = event.localPosition;
      _eraserRadius = _eraseRadius(event.pressure);
      if (_activeTool == CanvasTool.pixelEraser) {
        _erasePixelAt(
          event.localPosition,
          pressure: event.pressure,
          snapshotAlreadyTaken: _eraseSnapshotTaken,
        );
      } else {
        _eraseAt(
          event.localPosition,
          pressure: event.pressure,
          snapshotAlreadyTaken: _eraseSnapshotTaken,
        );
      }
      _repaint.repaint();
      return;
    }

    if (widget.tool == CanvasTool.lasso) {
      _lassoPath.add(event.localPosition);
      _repaint.repaint();
      return;
    }

    if (_activePen == null || _activeTool == null) return;

    final frame = _input!.update(event);
    _activeRealPoints = frame.realPoints;
    _activeLivePoints = frame.livePoints;

    if (_perfEnabled) {
      _performance.rendered(_activeLivePoints.length);
      _performance.setPredictionHorizon(
        frame.predictionHorizonMs,
      );
    }
    _repaint.repaint();
  }

  void _pointerUp(PointerUpEvent event) {
    if (event.pointer != _activePointer) return;

    if (_ignorePointer) {
      _ignorePointer = false;
      _activePointer = -1;
      return;
    }

    _recordInput();

    if (_temporaryEraser) {
      _eraseSnapshotTaken = false;
      _temporaryEraser = false;
      _eraserPoint = null;
      _eraserRadius = 0;
      _cancelActive();
    } else if (widget.tool == CanvasTool.lasso) {
      _finishLasso();
    } else if (_activeTool == CanvasTool.eraser ||
        _activeTool == CanvasTool.pixelEraser) {
      _eraseSnapshotTaken = false;
      _eraserPoint = null;
      _eraserRadius = 0;
      _cancelActive();
    } else if (widget.tool != CanvasTool.sticker) {
      _activeRealPoints = _input!.finish(event);
      _activeLivePoints = _activeRealPoints;
      if (_activeRealPoints.isNotEmpty) {
        _commitActive();
      }
    }

    if (event.kind == PointerDeviceKind.stylus) {
      _lastStylusTap = DateTime.now();
      _lastStylusPosition = event.localPosition;
    }
    _activePointer = -1;
  }

  void _pointerCancel(PointerCancelEvent event) {
    if (event.pointer != _activePointer) return;
    if (_activeTool == CanvasTool.eraser ||
        _activeTool == CanvasTool.pixelEraser ||
        _temporaryEraser) {
      _eraseSnapshotTaken = false;
      _temporaryEraser = false;
      _eraserPoint = null;
      _eraserRadius = 0;
    }
    _cancelActive();
    _input?.reset();
    _activePointer = -1;
  }

  void _cancelActive() {
    _activePen = null;
    _activeTool = null;
    _activeSticker = null;
    _activeRealPoints = const <StrokePoint>[];
    _activeLivePoints = const <StrokePoint>[];
    _lassoPath.clear();
    _repaint.repaint();
  }

  void _commitActive() {
    if (_activeRealPoints.isEmpty ||
        _activePen == null ||
        _activeTool == null) {
      _cancelActive();
      return;
    }

    _snapshot();
    final recognizedShape = _activeTool!.isShape
        ? _activeTool!.name
        : (widget.autoRecognition
              ? _recognizeShape(_activeRealPoints)
              : null);

    final stroke = Stroke(
      id: _uuid.v4(),
      points: List<StrokePoint>.of(_activeRealPoints),
      pen: _activePen!,
      shape: recognizedShape,
      fill: widget.shapeFill && recognizedShape != null,
      customSides: widget.customShapeSides,
      stickerText: _activeSticker,
      dashed: widget.dashed,
      fillColor: widget.fillColor,
    );
    _strokes.add(stroke);
    _activePen = null;
    _activeTool = null;
    _activeSticker = null;
    _activeRealPoints = const <StrokePoint>[];
    _activeLivePoints = const <StrokePoint>[];
    _input?.reset();
    _repaint.repaint();
    _notifyAndRefresh();
  }

  String? _recognizeShape(List<StrokePoint> points) {
    if (points.length < 4) return null;
    final first = points.first.position;
    final last = points.last.position;
    final closed = (last - first).distance < 28;
    var left = first.dx;
    var right = first.dx;
    var top = first.dy;
    var bottom = first.dy;

    for (final p in points.skip(1)) {
      left = math.min(left, p.position.dx);
      right = math.max(right, p.position.dx);
      top = math.min(top, p.position.dy);
      bottom = math.max(bottom, p.position.dy);
    }

    final width = right - left;
    final height = bottom - top;
    if (width < 20 || height < 20) {
      final line = last - first;
      if (line.distance < 20) return null;
      var maxDistance = 0.0;
      for (final p in points) {
        final distance =
            ((p.position.dx - first.dx) * line.dy -
                    (p.position.dy - first.dy) * line.dx)
                .abs() /
            line.distance;
        maxDistance = math.max(maxDistance, distance);
      }
      return maxDistance < 12 ? 'line' : null;
    }

    if (!closed) return null;
    final ratio = width / height;
    if (ratio > .72 && ratio < 1.38) return 'rectangle';
    return 'ellipse';
  }

  double _eraseRadius(double pressure) {
    final p =
        pressure.isNaN ? 1.0 : pressure.clamp(0, 1).toDouble();
    final base =
        (widget.pen.size * 3.3).clamp(16, 44).toDouble();
    return widget.pressureErase && widget.pressureEraseArea
        ? base * (.65 + p * .75)
        : base;
  }

  void _pointerHover(PointerHoverEvent event) {
    if (!_accept(event) ||
        event.kind != PointerDeviceKind.stylus) {
      return;
    }
    _eraserPoint = event.localPosition;
    _eraserRadius = _eraseRadius(event.pressure);
    _repaint.repaint();
  }

  void _erasePixelAt(
    Offset point, {
    double pressure = 1,
    bool snapshotAlreadyTaken = false,
  }) {
    final normalizedPressure =
        pressure.isNaN ? 1.0 : pressure.clamp(0, 1).toDouble();
    if (widget.pressureErase &&
        normalizedPressure < widget.pressureEraseThreshold) {
      return;
    }

    final baseRadius =
        (widget.pen.size * 3.3).clamp(16, 44).toDouble();
    final radius = widget.pressureErase &&
            widget.pressureEraseArea
        ? baseRadius * (.65 + normalizedPressure * .75)
        : baseRadius;

    var changed = false;
    for (var i = _strokes.length - 1; i >= 0; i--) {
      final stroke = _strokes[i];
      if (stroke.shape != null || stroke.stickerText != null) {
        if (stroke.points.any(
          (p) => (p.position - point).distance <= radius,
        )) {
          if (!snapshotAlreadyTaken && !changed) _snapshot();
          _strokes.removeAt(i);
          changed = true;
        }
        continue;
      }

      final pieces = <List<StrokePoint>>[];
      var current = <StrokePoint>[];
      var hit = false;
      for (var p = 0; p < stroke.points.length; p++) {
        final currentPoint = stroke.points[p];
        final pointHit =
            (currentPoint.position - point).distance <= radius;
        final segmentHit = p > 0 &&
            _distanceToSegment(
                  point,
                  stroke.points[p - 1].position,
                  currentPoint.position,
                ) <=
                radius;
        if (pointHit || segmentHit) {
          hit = true;
          if (current.isNotEmpty) pieces.add(current);
          current = <StrokePoint>[];
        } else {
          current.add(currentPoint);
        }
      }
      if (current.isNotEmpty) pieces.add(current);

      if (!hit) continue;
      if (!snapshotAlreadyTaken && !changed) _snapshot();
      _strokes.removeAt(i);
      for (var p = pieces.length - 1; p >= 0; p--) {
        final piece = pieces[p];
        if (piece.isEmpty) continue;
        _strokes.insert(
          i,
          stroke.copyWith(
            id: p == 0 ? stroke.id : _uuid.v4(),
            points: piece,
          ),
        );
      }
      changed = true;
    }

    if (!changed) {
      widget.onEraserMiss?.call();
      return;
    }
    _notifyAndRefresh();
  }

  double _distanceToSegment(
    Offset point,
    Offset a,
    Offset b,
  ) {
    final vector = b - a;
    final lengthSquared =
        vector.dx * vector.dx + vector.dy * vector.dy;
    if (lengthSquared <= .0001) {
      return (point - a).distance;
    }
    final projection = ((point.dx - a.dx) * vector.dx +
            (point.dy - a.dy) * vector.dy) /
        lengthSquared;
    final t = projection.clamp(0, 1).toDouble();
    final closest = Offset(
      a.dx + vector.dx * t,
      a.dy + vector.dy * t,
    );
    return (point - closest).distance;
  }

  void _eraseAt(
    Offset point, {
    double pressure = 1,
    bool snapshotAlreadyTaken = false,
  }) {
    final normalizedPressure =
        pressure.isNaN ? 1.0 : pressure.clamp(0, 1).toDouble();
    if (widget.pressureErase &&
        normalizedPressure < widget.pressureEraseThreshold) {
      return;
    }

    final baseRadius =
        (widget.pen.size * 3.3).clamp(16, 44).toDouble();
    final radius = widget.pressureErase &&
            widget.pressureEraseArea
        ? baseRadius * (.65 + normalizedPressure * .75)
        : baseRadius;

    final hit = _strokes.indexWhere((s) {
      for (final p in s.points) {
        if ((p.position - point).distance <= radius) {
          return true;
        }
      }
      return false;
    });

    if (hit < 0) {
      widget.onEraserMiss?.call();
      return;
    }

    if (!snapshotAlreadyTaken) _snapshot();
    _strokes.removeAt(hit);
    _selected.removeWhere(
      (id) => !_strokes.any((s) => s.id == id),
    );
    _notifyAndRefresh();
  }

  void _finishLasso() {
    if (_lassoPath.length < 3) {
      _lassoPath.clear();
      _repaint.repaint();
      _notifySelection();
      return;
    }

    final polygon = List<Offset>.of(_lassoPath);
    _selected.clear();

    for (final stroke in _strokes) {
      if (stroke.points
          .any((p) => _pointInPolygon(p.position, polygon))) {
        _selected.add(stroke.id);
      }
    }

    _lassoPath.clear();
    _notifySelection();
    _repaint.repaint();
  }

  bool _pointInPolygon(
    Offset point,
    List<Offset> polygon,
  ) {
    var inside = false;
    for (
      var i = 0, j = polygon.length - 1;
      i < polygon.length;
      j = i++
    ) {
      final a = polygon[i];
      final b = polygon[j];
      final intersects =
          ((a.dy > point.dy) != (b.dy > point.dy)) &&
          point.dx <
              (b.dx - a.dx) *
                      (point.dy - a.dy) /
                      ((b.dy - a.dy).abs() < .0001
                          ? .0001
                          : (b.dy - a.dy)) +
                  a.dx;
      if (intersects) inside = !inside;
    }
    return inside;
  }
}
