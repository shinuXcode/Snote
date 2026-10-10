import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:uuid/uuid.dart';

import '../algorithms/lasso_geometry.dart';
import '../algorithms/shape_recognizer.dart';
import '../input/ink_gesture_policy.dart';
import '../input/ink_input_pipeline.dart';
import '../input/palm_rejection.dart';
import '../input/stylus_gesture_lock.dart';
import '../persistence/ink_commit_queue.dart';
import '../models/pen_config.dart';
import '../models/stroke.dart';
import '../models/stroke_codec.dart';
import '../ink_renderer.dart';
import '../painters/canvas_painter.dart';
import '../performance/stroke_spatial_index.dart';
import '../performance/writing_performance.dart';
import 'snote_canvas_controller.dart';

class _CanvasRepaint extends ChangeNotifier {
  List<StrokePoint> livePoints = const <StrokePoint>[];
  PenConfig? pen;
  CanvasTool? tool;
  bool fill = false;
  int customSides = 6;
  String? sticker;
  List<Offset> lassoPath = const <Offset>[];
  Offset? eraserPoint;
  double eraserRadius = 0;
  bool showEraser = false;
  Color? fillColor;

  /// Keep all transient drawing state in the repaint source. Pointer events
  /// mutate state without rebuilding the widget tree, so painter delegates
  /// must not capture stale copies of the active pen/tool/sample references.
  void updateLiveState({
    required List<StrokePoint> livePoints,
    required PenConfig? pen,
    required CanvasTool? tool,
    required bool fill,
    required int customSides,
    required String? sticker,
    required List<Offset> lassoPath,
    required Offset? eraserPoint,
    required double eraserRadius,
    required bool showEraser,
    required Color? fillColor,
  }) {
    this.livePoints = livePoints;
    this.pen = pen;
    this.tool = tool;
    this.fill = fill;
    this.customSides = customSides;
    this.sticker = sticker;
    this.lassoPath = lassoPath;
    this.eraserPoint = eraserPoint;
    this.eraserRadius = eraserRadius;
    this.showEraser = showEraser;
    this.fillColor = fillColor;
    notifyListeners();
  }

}

/// Cached immutable document layer. It is rebuilt only after a logical
/// document mutation (stroke commit, erase, move, undo/redo, ...).
class _PicturePainter extends CustomPainter {
  final ui.Picture? picture;

  const _PicturePainter(this.picture);

  @override
  void paint(Canvas canvas, Size size) {
    final p = picture;
    if (p != null) canvas.drawPicture(p);
  }

  @override
  bool shouldRepaint(covariant _PicturePainter oldDelegate) =>
      !identical(oldDelegate.picture, picture);
}

/// High-frequency active layer. The painter is driven by a Listenable instead
/// of widget-tree rebuilds, so pointer moves invalidate paint only.
class _LiveInkPainter extends CustomPainter {
  final _CanvasRepaint liveState;

  const _LiveInkPainter({
    required this.liveState,
  }) : super(repaint: liveState);

  @override
  void paint(Canvas canvas, Size size) {
    // Read all transient state at paint time. Captured pen/tool fields were
    // null in the initial delegate and remained null until pen-up triggered
    // a widget rebuild, despite pointer-move repaint notifications.
    final points = liveState.livePoints;
    final pen = liveState.pen;
    final tool = liveState.tool;
    final fill = liveState.fill;
    final customSides = liveState.customSides;
    final sticker = liveState.sticker;
    final lassoPath = liveState.lassoPath;
    final eraserPoint = liveState.eraserPoint;
    final eraserRadius = liveState.eraserRadius;
    final showEraser = liveState.showEraser;
    final fillColor = liveState.fillColor;
    if (points.isNotEmpty && pen != null && tool != null) {
      final currentTool = tool;

      // Freehand ink goes through the same renderer while the pointer is down
      // and after commit. Do not route every live frame through a second
      // temporary painter: that used to duplicate work and could make the
      // live layer visually lag the finalized document layer.
      if (!currentTool.isShape && currentTool != CanvasTool.sticker) {
        InkRenderer.drawInk(canvas, points, pen);
      } else {
        final synthetic = Stroke(
          id: 'live',
          points: points,
          pen: pen,
          shape: currentTool.isShape ? currentTool.name : null,
          fill: fill,
          customSides: customSides,
          stickerText: sticker,
          fillColor: fillColor,
        );

        SnoteCanvasPainter(
          strokes: const <Stroke>[],
          activeStroke: synthetic,
          activePoints: points,
          activePen: pen,
          activeTool: tool,
          activeFill: fill,
          activeCustomSides: customSides,
          activeStickerText: sticker,
          selectedIds: const <String>{},
          lassoPath: const <Offset>[],
          eraserPoint: null,
          eraserRadius: 0,
          showEraserMark: false,
          drawStrokes: false,
          drawActive: true,
        ).paint(canvas, size);
      }
    }

    if (lassoPath.length > 1) {
      final path = Path()..moveTo(lassoPath.first.dx, lassoPath.first.dy);
      for (final point in lassoPath.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xff4f6df6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true,
      );
    }

    if (showEraser && eraserPoint != null && eraserRadius > 0) {
      canvas.drawCircle(
        eraserPoint,
        eraserRadius,
        Paint()
          ..color = const Color(0xff4f6df6).withValues(alpha: .55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
    }
  }
  @override
  bool shouldRepaint(covariant _LiveInkPainter oldDelegate) => false;
}

class _SelectionOverlayPainter extends CustomPainter {
  final Rect? bounds;

  const _SelectionOverlayPainter({required this.bounds});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = bounds;
    if (rect == null) return;
    final outline = Paint()
      ..color = const Color(0xff4f6df6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawRect(rect, outline);

    final handles = <Offset>[
      rect.topLeft,
      Offset(rect.center.dx, rect.top),
      rect.topRight,
      Offset(rect.right, rect.center.dy),
      rect.bottomRight,
      Offset(rect.center.dx, rect.bottom),
      rect.bottomLeft,
      Offset(rect.left, rect.center.dy),
    ];
    final fill = Paint()..color = Colors.white;
    final border = Paint()
      ..color = const Color(0xff4f6df6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    for (final point in handles) {
      canvas.drawCircle(point, 4.5, fill);
      canvas.drawCircle(point, 4.5, border);
    }
  }

  @override
  bool shouldRepaint(covariant _SelectionOverlayPainter oldDelegate) =>
      oldDelegate.bounds != bounds;
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
  final InkGesturePolicy gesturePolicy;

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
    this.gesturePolicy = const InkGesturePolicy(),
  });

  @override
  State<SnoteCanvas> createState() => _SnoteCanvasState();
}

class _SnoteCanvasState extends State<SnoteCanvas> {
  final _uuid = const Uuid();
  final _palm = PalmRejection();
  final _lock = StylusGestureLock();
  final _spatial = StrokeSpatialIndex();
  final _repaint = _CanvasRepaint();
  final _perf = WritingPerformanceStats(
    enabled: const bool.fromEnvironment('SNOTE_PERF'),
  );
  final _strokes = <Stroke>[];
  final _history = <List<Stroke>>[];
  final _redo = <List<Stroke>>[];
  final _selected = <String>{};
  final _lasso = <Offset>[];

  InkInputPipeline? _input;
  InkCommitQueue<Map<String, Object?>>? _commitQueue;

  List<StrokePoint> _real = const <StrokePoint>[];
  List<StrokePoint> _live = const <StrokePoint>[];
  PenConfig? _activePen;
  CanvasTool? _activeTool;
  String? _activeSticker;

  ui.Picture? _documentPicture;

  Offset? _eraserPoint;
  double _eraserRadius = 0;
  int _activePointer = -1;
  String? _selectionTransformMode;
  Offset? _selectionTransformStart;
  Offset? _selectionTransformAnchor;
  Offset? _selectionTransformStartHandle;
  Rect? _selectionTransformStartBounds;
  List<Stroke> _selectionTransformOriginals = const <Stroke>[];
  bool _selectionTransformX = false;
  bool _selectionTransformY = false;
  bool _selectionTransformChanged = false;
  bool _selectionPaintScheduled = false;
  int _selectionTransformGeneration = 0;
  bool _ignorePointer = false;
  bool _temporaryEraser = false;
  bool _eraseSnapshotTaken = false;
  bool _latencyScheduled = false;
  DateTime? _lastInputWallClock;
  DateTime? _lastStylusTap;
  Offset? _lastStylusPosition;

  bool get _perfEnabled => _perf.enabled;

  @override
  void initState() {
    super.initState();
    _createPipeline();
    _commitQueue = InkCommitQueue<Map<String, Object?>>(
      onCommit: (document) => widget.onChanged?.call(document),
    );
    _replaceDocument(widget.initialDocument);
    _bindController();
    _perf.attachScheduler();
  }

  void _createPipeline() {
    _input = InkInputPipeline(
      smoothing: widget.smoothing,
      maxSamples: 16384,
    );
  }

  @override
  void didUpdateWidget(covariant SnoteCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.unbind();
      _bindController();
    }
    if (oldWidget.smoothing != widget.smoothing) {
      _createPipeline();
    }
    if (!identical(oldWidget.initialDocument, widget.initialDocument)) {
      _replaceDocument(widget.initialDocument, clearHistory: false);
    }
  }

  @override
  void dispose() {
    _perf.detachScheduler();
    _commitQueue?.dispose();
    _input?.reset();
    _lock.reset();
    widget.controller?.unbind();
    _documentPicture?.dispose();
    _repaint.dispose();
    _perf.dispose();
    super.dispose();
  }

  void _replaceDocument(
    Map<String, Object?>? document, {
    bool clearHistory = true,
  }) {
    _strokes
      ..clear()
      ..addAll(StrokeCodec.documentToStrokes(document));
    _spatial.rebuild(_strokes);
    _selected.clear();
    _lasso.clear();
    if (clearHistory) {
      _history.clear();
      _redo.clear();
    }
    _recordDocumentPicture();
    _perf.setDocumentStats(
      strokes: _strokes.length,
      visible: _strokes.length,
    );
    if (mounted) {
      setState(() {});
    }
    _notifySelection();
  }

  void _recordDocumentPicture() {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    SnoteCanvasPainter(
      strokes: List<Stroke>.unmodifiable(_strokes),
      activeStroke: null,
      activePoints: const <StrokePoint>[],
      activePen: null,
      activeTool: null,
      activeFill: false,
      activeCustomSides: 6,
      activeStickerText: null,
      selectedIds: Set<String>.unmodifiable(_selected),
      lassoPath: const <Offset>[],
      drawStrokes: true,
      drawActive: false,
    ).paint(canvas, Size.zero);

    final next = recorder.endRecording();
    _documentPicture?.dispose();
    _documentPicture = next;
  }

  void _bindController() {
    widget.controller?.bind(
      undo: undo,
      redo: redo,
      clear: clear,
      deleteSelection: deleteSelection,
      duplicateSelection: duplicateSelection,
      moveSelection: moveSelection,
      scaleSelection: scaleSelection,
      selectAll: selectAll,
      clearSelection: clearSelection,
      canUndo: _history.isNotEmpty,
      canRedo: _redo.isNotEmpty,
      selectionCount: _selected.length,
      changeColor: changeSelectedColor,
      changeSize: changeSelectedSize,
      toggleFill: toggleSelectedFill,
      bringToFront: bringSelectionToFront,
      sendToBack: sendSelectionToBack,
    );
  }

  void _snapshot() {
    _history.add(List<Stroke>.of(_strokes));
    if (_history.length > 80) {
      _history.removeAt(0);
    }
    _redo.clear();
  }

  void undo() {
    if (_history.isEmpty) return;
    _redo.add(List<Stroke>.of(_strokes));
    _strokes
      ..clear()
      ..addAll(_history.removeLast());
    _finishDocumentMutation();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _history.add(List<Stroke>.of(_strokes));
    _strokes
      ..clear()
      ..addAll(_redo.removeLast());
    _finishDocumentMutation();
  }

  void clear() {
    if (_strokes.isEmpty) return;
    _snapshot();
    _strokes.clear();
    _selected.clear();
    _finishDocumentMutation();
    _notifySelection();
  }

  void deleteSelection() {
    if (_selected.isEmpty) return;
    _snapshot();
    _strokes.removeWhere((stroke) => _selected.contains(stroke.id));
    _selected.clear();
    _finishDocumentMutation();
    _notifySelection();
  }

  void duplicateSelection() {
    if (_selected.isEmpty) return;
    _snapshot();
    final copies = <Stroke>[];
    for (final stroke in _strokes) {
      if (!_selected.contains(stroke.id)) continue;
      copies.add(
        stroke.copyWith(
          id: _uuid.v4(),
          points: stroke.points
              .map(
                (point) => point.copyWith(
                  position: point.position + const Offset(18, 18),
                ),
              )
              .toList(),
        ),
      );
    }
    _strokes.addAll(copies);
    _selected
      ..clear()
      ..addAll(copies.map((stroke) => stroke.id));
    _finishDocumentMutation();
    _notifySelection();
  }

  void moveSelection(double dx, double dy) {
    if (_selected.isEmpty) return;
    _snapshot();
    for (var i = 0; i < _strokes.length; i++) {
      final stroke = _strokes[i];
      if (!_selected.contains(stroke.id)) continue;
      _strokes[i] = stroke.copyWith(
        points: stroke.points
            .map((point) => point.copyWith(
                  position: point.position + Offset(dx, dy),
                ))
            .toList(),
      );
    }
    _finishDocumentMutation();
  }

  void scaleSelection(double factor) {
    if (_selected.isEmpty || !factor.isFinite || factor <= 0) return;
    final points = _strokes
        .where((stroke) => _selected.contains(stroke.id))
        .expand((stroke) => stroke.points)
        .toList();
    if (points.isEmpty) return;

    var minX = points.first.position.dx;
    var maxX = minX;
    var minY = points.first.position.dy;
    var maxY = minY;
    for (final point in points.skip(1)) {
      minX = math.min(minX, point.position.dx);
      maxX = math.max(maxX, point.position.dx);
      minY = math.min(minY, point.position.dy);
      maxY = math.max(maxY, point.position.dy);
    }
    final center = Offset((minX + maxX) / 2, (minY + maxY) / 2);
    final scale = factor.clamp(.1, 10).toDouble();

    _snapshot();
    for (var i = 0; i < _strokes.length; i++) {
      final stroke = _strokes[i];
      if (!_selected.contains(stroke.id)) continue;
      _strokes[i] = stroke.copyWith(
        points: stroke.points
            .map((point) => point.copyWith(
                  position: center + (point.position - center) * scale,
                ))
            .toList(),
        pen: stroke.pen.copyWith(
          size: (stroke.pen.size * scale).clamp(.5, 60).toDouble(),
        ),
      );
    }
    _finishDocumentMutation();
  }

  void changeSelectedColor(Color color) {
    if (_selected.isEmpty) return;
    _snapshot();
    for (var i = 0; i < _strokes.length; i++) {
      final stroke = _strokes[i];
      if (_selected.contains(stroke.id)) {
        _strokes[i] = stroke.copyWith(
          pen: stroke.pen.copyWith(color: color),
          fillColor: color,
        );
      }
    }
    _finishDocumentMutation();
  }

  void changeSelectedSize(double size) {
    if (_selected.isEmpty) return;
    _snapshot();
    for (var i = 0; i < _strokes.length; i++) {
      final stroke = _strokes[i];
      if (_selected.contains(stroke.id)) {
        _strokes[i] = stroke.copyWith(
          pen: stroke.pen.copyWith(size: size.clamp(.5, 60).toDouble()),
        );
      }
    }
    _finishDocumentMutation();
  }

  void toggleSelectedFill() {
    if (_selected.isEmpty) return;
    _snapshot();
    for (var i = 0; i < _strokes.length; i++) {
      final stroke = _strokes[i];
      if (_selected.contains(stroke.id) && stroke.shape != null) {
        _strokes[i] = stroke.copyWith(fill: !stroke.fill);
      }
    }
    _finishDocumentMutation();
  }

  void bringSelectionToFront() {
    if (_selected.isEmpty) return;
    _snapshot();
    final chosen = _strokes.where((s) => _selected.contains(s.id)).toList();
    _strokes.removeWhere((s) => _selected.contains(s.id));
    _strokes.addAll(chosen);
    _finishDocumentMutation();
  }

  void sendSelectionToBack() {
    if (_selected.isEmpty) return;
    _snapshot();
    final chosen = _strokes.where((s) => _selected.contains(s.id)).toList();
    _strokes.removeWhere((s) => _selected.contains(s.id));
    _strokes.insertAll(0, chosen);
    _finishDocumentMutation();
  }

  void selectAll() {
    _selected
      ..clear()
      ..addAll(_strokes.map((stroke) => stroke.id));
    _recordDocumentPicture();
    _notifySelection();
  }

  void clearSelection() {
    _selected.clear();
    _recordDocumentPicture();
    _notifySelection();
  }

  void _syncLivePainter() {
    _repaint.updateLiveState(
      livePoints: _live,
      pen: _activePen,
      tool: _activeTool,
      fill: widget.shapeFill,
      customSides: widget.customShapeSides,
      sticker: _activeSticker,
      lassoPath: _lasso,
      eraserPoint: _eraserPoint,
      eraserRadius: _eraserRadius,
      showEraser: widget.eraseMark &&
          (_activeTool == CanvasTool.eraser ||
              _activeTool == CanvasTool.pixelEraser ||
              _temporaryEraser),
      fillColor: widget.fillColor,
    );
  }

  void _notifySelection() {
    widget.onSelectionChanged?.call(_selected.length);
    _bindController();
    if (mounted) setState(() {});
  }

  void _finishDocumentMutation() {
    _spatial.rebuild(_strokes);
    _recordDocumentPicture();
    _perf.setDocumentStats(
      strokes: _strokes.length,
      visible: _strokes.length,
    );
    if (mounted) {
      setState(() {});
    }
    _commitQueue?.enqueue(StrokeCodec.strokesToDocument(_strokes));
  }

  void _recordInput() {
    if (!_perfEnabled) return;
    _perf.pointerEvent();
    final now = DateTime.now();
    _lastInputWallClock = now;
    if (_latencyScheduled) return;
    _latencyScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _latencyScheduled = false;
      final input = _lastInputWallClock;
      if (input != null) _perf.setLatency(input);
    });
  }

  bool _accept(PointerEvent event) {
    if (!_palm.accepts(event)) return false;
    if (event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus) {
      return widget.gesturePolicy.isStylus(event.kind);
    }
    return event.kind == PointerDeviceKind.mouse;
  }

  void _pointerDown(PointerDownEvent event) {
    // A completed lasso selection can be moved/resized directly with a
    // finger or stylus. Only a down inside the selection or its handles is
    // intercepted; all other stylus input remains available for writing.
    final canTransformWithPointer = event.kind == PointerDeviceKind.touch ||
        event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus ||
        event.kind == PointerDeviceKind.mouse;
    if (canTransformWithPointer &&
        _activePointer == -1 &&
        _selected.isNotEmpty &&
        _beginSelectionTransform(event)) {
      return;
    }
    _recordInput();
    if (!_accept(event) || _activePointer != -1) return;

    _ignorePointer = false;
    final isStylus = widget.gesturePolicy.isStylus(event.kind);

    if (isStylus && !_lock.begin(event)) return;

    if (isStylus && _isStylusDoubleTap(event)) {
      _ignorePointer = true;
      widget.onStylusDoubleTap?.call();
      return;
    }

    _activePointer = event.pointer;
    _temporaryEraser = widget.eraseWithStylusButton &&
        (event.kind == PointerDeviceKind.invertedStylus ||
            (event.kind == PointerDeviceKind.stylus &&
                (event.buttons & kSecondaryStylusButton) != 0));

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
      _syncLivePainter();
      return;
    }

    if (widget.tool == CanvasTool.lasso) {
      _activeTool = CanvasTool.lasso;
      _activePen = widget.pen;
      _lasso
        ..clear()
        ..add(event.localPosition);
      _syncLivePainter();
      return;
    }

    _activeTool = widget.tool;
    _activePen = widget.pen;
    _activeSticker =
        widget.tool == CanvasTool.sticker ? widget.stickerText : null;

    final frame = _input!.begin(event);
    _real = frame.realPoints;
    _live = frame.livePoints;
    _syncLivePainter();

    if (widget.tool == CanvasTool.sticker) {
      _commitActive();
    }
  }

  bool _isStylusDoubleTap(PointerDownEvent event) {
    if (_lastStylusTap == null || _lastStylusPosition == null) return false;
    final elapsed = DateTime.now().difference(_lastStylusTap!);
    return elapsed <= const Duration(milliseconds: 350) &&
        (_lastStylusPosition! - event.localPosition).distance <= 28;
  }

  void _pointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer || _ignorePointer) return;
    if (_selectionTransformMode != null) {
      _updateSelectionTransform(event.localPosition);
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
      _syncLivePainter();
      return;
    }

    if (_activeTool == CanvasTool.lasso) {
      if (_lasso.isEmpty ||
          (_lasso.last - event.localPosition).distanceSquared > .35) {
        _lasso.add(event.localPosition);
      }
      _syncLivePainter();
      return;
    }

    if (_activePen == null || _activeTool == null) return;
    final frame = _input!.update(event);
    _real = frame.realPoints;
    _live = frame.livePoints;
    if (_perfEnabled) {
      _perf.rendered(_live.length);
      _perf.setPredictionHorizon(frame.predictionHorizonMs);
    }
    _syncLivePainter();
  }

  void _pointerUp(PointerUpEvent event) {
    if (event.pointer != _activePointer) return;

    if (_selectionTransformMode != null) {
      _finishSelectionTransform();
      _activePointer = -1;
      return;
    }

    if (_ignorePointer) {
      _ignorePointer = false;
      _lock.end(event);
      _activePointer = -1;
      return;
    }

    _recordInput();

    if (_temporaryEraser) {
      _eraseSnapshotTaken = false;
      _temporaryEraser = false;
      _clearActiveState();
    } else if (_activeTool == CanvasTool.lasso) {
      _finishLasso();
    } else if (_activeTool == CanvasTool.eraser ||
        _activeTool == CanvasTool.pixelEraser) {
      _eraseSnapshotTaken = false;
      _clearActiveState();
    } else if (_activeTool != CanvasTool.sticker) {
      _real = _input!.finish(event);
      _live = _real;
      _syncLivePainter();
      if (_real.isNotEmpty) _commitActive();
    }

    if (event.kind == PointerDeviceKind.stylus) {
      _lastStylusTap = DateTime.now();
      _lastStylusPosition = event.localPosition;
    }
    _lock.end(event);
    _activePointer = -1;
  }

  void _pointerCancel(PointerCancelEvent event) {
    if (event.pointer != _activePointer) return;
    if (_selectionTransformMode != null) {
      _finishSelectionTransform();
      _activePointer = -1;
      return;
    }
    _eraseSnapshotTaken = false;
    _temporaryEraser = false;
    _clearActiveState();
    _input?.reset();
    _lock.end(event);
    _activePointer = -1;
  }

  void _clearActiveState() {
    _activePen = null;
    _activeTool = null;
    _activeSticker = null;
    _real = const <StrokePoint>[];
    _live = const <StrokePoint>[];
    _eraserPoint = null;
    _eraserRadius = 0;
    _lasso.clear();
    _input?.reset();
    _syncLivePainter();
  }

  void _commitActive() {
    if (_real.isEmpty || _activePen == null || _activeTool == null) {
      _clearActiveState();
      return;
    }

    _snapshot();
    final shape = _activeTool!.isShape
        ? _activeTool!.name
        : (widget.autoRecognition ? _recognizeShape(_real) : null);

    final stroke = Stroke(
      id: _uuid.v4(),
      points: List<StrokePoint>.of(_real),
      pen: _activePen!,
      shape: shape,
      fill: widget.shapeFill && shape != null,
      customSides: widget.customShapeSides,
      stickerText: _activeSticker,
      dashed: widget.dashed,
      fillColor: widget.fillColor,
    );

    _strokes.add(stroke);
    _real = const <StrokePoint>[];
    _live = const <StrokePoint>[];
    _activePen = null;
    _activeTool = null;
    _activeSticker = null;
    _input?.reset();
    _syncLivePainter();
    _finishDocumentMutation();
  }

  String? _recognizeShape(List<StrokePoint> points) =>
      ShapeRecognizer.recognize(points);

  double _eraseRadius(double pressure) {
    final normalized =
        pressure.isNaN ? 1.0 : pressure.clamp(0, 1).toDouble();
    final base = (widget.pen.size * 3.3).clamp(16, 44).toDouble();
    if (widget.pressureErase && widget.pressureEraseArea) {
      return base *
          (0.65 + normalized.clamp(widget.pressureEraseThreshold, 1) * .75);
    }
    return base;
  }

  void _eraseAt(
    Offset point, {
    double pressure = 1,
    bool snapshotAlreadyTaken = false,
  }) {
    if (widget.pressureErase &&
        pressure.isFinite &&
        pressure < widget.pressureEraseThreshold) {
      return;
    }

    final radius = _eraseRadius(pressure);
    final candidates = _spatial.candidates(point, radius);
    for (final index in candidates) {
      if (index < 0 || index >= _strokes.length) continue;
      final stroke = _strokes[index];
      if (_polylineTouchesCircle(stroke.points, point, radius)) {
        if (!snapshotAlreadyTaken && !_eraseSnapshotTaken) {
          _snapshot();
          _eraseSnapshotTaken = true;
        }
        _strokes.removeAt(index);
        _finishDocumentMutation();
        return;
      }
    }
    widget.onEraserMiss?.call();
  }

  void _erasePixelAt(
    Offset point, {
    double pressure = 1,
    bool snapshotAlreadyTaken = false,
  }) {
    if (widget.pressureErase &&
        pressure.isFinite &&
        pressure < widget.pressureEraseThreshold) {
      return;
    }

    final radius = _eraseRadius(pressure);
    final candidates = _spatial.candidates(point, radius);
    final sorted = candidates.toList()..sort((a, b) => b.compareTo(a));

    for (final index in sorted) {
      if (index < 0 || index >= _strokes.length) continue;
      final stroke = _strokes[index];
      if (stroke.shape != null || stroke.stickerText != null) {
        if (stroke.points.any(
          (p) => (p.position - point).distance <= radius,
        )) {
          if (!snapshotAlreadyTaken && !_eraseSnapshotTaken) {
            _snapshot();
            _eraseSnapshotTaken = true;
          }
          _strokes.removeAt(index);
          _finishDocumentMutation();
          return;
        }
        continue;
      }

      final pieces = _subtractCircle(stroke.points, point, radius);

      if (pieces.length == 1 &&
          pieces.first.length == stroke.points.length) {
        continue;
      }

      if (!snapshotAlreadyTaken && !_eraseSnapshotTaken) {
        _snapshot();
        _eraseSnapshotTaken = true;
      }
      _strokes.removeAt(index);

      for (var part = pieces.length - 1; part >= 0; part--) {
        final segment = pieces[part];
        if (segment.isEmpty) continue;
        _strokes.insert(
          index,
          stroke.copyWith(
            id: part == 0 ? stroke.id : _uuid.v4(),
            points: segment,
          ),
        );
      }
      _finishDocumentMutation();
      return;
    }

    widget.onEraserMiss?.call();
  }

  Rect? get _selectionBounds {
    final points = _strokes
        .where((stroke) => _selected.contains(stroke.id))
        .expand((stroke) => stroke.points)
        .toList();
    if (points.isEmpty) return null;
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
    // A minimum visible selection target makes narrow lines practical to move.
    return Rect.fromLTRB(left, top, right, bottom).inflate(8);
  }

  List<MapEntry<String, Offset>> _selectionHandles(Rect bounds) => [
        MapEntry('tl', bounds.topLeft),
        MapEntry('tm', Offset(bounds.center.dx, bounds.top)),
        MapEntry('tr', bounds.topRight),
        MapEntry('rm', Offset(bounds.right, bounds.center.dy)),
        MapEntry('br', bounds.bottomRight),
        MapEntry('bm', Offset(bounds.center.dx, bounds.bottom)),
        MapEntry('bl', bounds.bottomLeft),
        MapEntry('lm', Offset(bounds.left, bounds.center.dy)),
      ];

  bool _beginSelectionTransform(PointerDownEvent event) {
    final bounds = _selectionBounds;
    if (bounds == null || !bounds.inflate(16).contains(event.localPosition)) {
      return false;
    }
    String? handle;
    Offset? handlePoint;
    var nearest = 18.0;
    for (final candidate in _selectionHandles(bounds)) {
      final distance = (candidate.value - event.localPosition).distance;
      if (distance <= nearest) {
        nearest = distance;
        handle = candidate.key;
        handlePoint = candidate.value;
      }
    }
    final isResize = handle != null;
    if (!isResize && !bounds.contains(event.localPosition)) return false;

    _selectionTransformMode = isResize ? 'resize' : 'move';
    _selectionTransformStart = event.localPosition;
    _selectionTransformStartHandle = handlePoint;
    _selectionTransformStartBounds = bounds;
    _selectionTransformOriginals = _strokes
        .where((stroke) => _selected.contains(stroke.id))
        .toList(growable: false);
    if (_selectionTransformOriginals.isEmpty) {
      _clearSelectionTransformState();
      return false;
    }

    final h = handle;
    _selectionTransformX = h == 'tl' || h == 'tm' || h == 'tr' ||
        h == 'rm' || h == 'br' || h == 'bm' || h == 'bl' || h == 'lm';
    _selectionTransformY = _selectionTransformX;
    if (h == 'tm' || h == 'bm') _selectionTransformX = false;
    if (h == 'lm' || h == 'rm') _selectionTransformY = false;

    if (h == 'tl') _selectionTransformAnchor = bounds.bottomRight;
    if (h == 'tm') _selectionTransformAnchor = Offset(bounds.center.dx, bounds.bottom);
    if (h == 'tr') _selectionTransformAnchor = bounds.bottomLeft;
    if (h == 'rm') _selectionTransformAnchor = Offset(bounds.left, bounds.center.dy);
    if (h == 'br') _selectionTransformAnchor = bounds.topLeft;
    if (h == 'bm') _selectionTransformAnchor = Offset(bounds.center.dx, bounds.top);
    if (h == 'bl') _selectionTransformAnchor = bounds.topRight;
    if (h == 'lm') _selectionTransformAnchor = Offset(bounds.right, bounds.center.dy);

    _snapshot();
    _selectionTransformChanged = false;
    _activePointer = event.pointer;
    return true;
  }

  void _updateSelectionTransform(Offset position) {
    final mode = _selectionTransformMode;
    final start = _selectionTransformStart;
    final bounds = _selectionTransformStartBounds;
    if (mode == null || start == null || bounds == null) return;
    final original = _selectionTransformOriginals;
    if (original.isEmpty) return;

    var dx = 0.0;
    var dy = 0.0;
    var sx = 1.0;
    var sy = 1.0;
    if (mode == 'move') {
      dx = position.dx - start.dx;
      dy = position.dy - start.dy;
    } else {
      final anchor = _selectionTransformAnchor;
      final startHandle = _selectionTransformStartHandle;
      if (anchor == null || startHandle == null) return;
      if (_selectionTransformX) {
        final denominator = startHandle.dx - anchor.dx;
        if (denominator.abs() > 1) {
          sx = ((position.dx - anchor.dx) / denominator).clamp(.1, 10).toDouble();
        }
      }
      if (_selectionTransformY) {
        final denominator = startHandle.dy - anchor.dy;
        if (denominator.abs() > 1) {
          sy = ((position.dy - anchor.dy) / denominator).clamp(.1, 10).toDouble();
        }
      }
    }

    final byId = {for (final stroke in original) stroke.id: stroke};
    for (var i = 0; i < _strokes.length; i++) {
      final current = _strokes[i];
      final source = byId[current.id];
      if (source == null) continue;
      final points = source.points.map((point) {
        final Offset next;
        if (mode == 'move') {
          next = point.position + Offset(dx, dy);
        } else {
          final anchor = _selectionTransformAnchor!;
          next = Offset(
            anchor.dx + (point.position.dx - anchor.dx) * sx,
            anchor.dy + (point.position.dy - anchor.dy) * sy,
          );
        }
        return point.copyWith(position: next);
      }).toList(growable: false);
      final widthFactor = math.sqrt(sx * sy);
      _strokes[i] = source.copyWith(
        points: points,
        pen: mode == 'resize'
            ? source.pen.copyWith(
                size: (source.pen.size * widthFactor).clamp(.5, 60).toDouble(),
              )
            : source.pen,
      );
    }
    _selectionTransformChanged = true;
    // Coalesce many move events into one immutable-picture rebuild per frame.
    // Expensive indexing and persistence are deferred until pointer-up.
    if (!_selectionPaintScheduled) {
      _selectionPaintScheduled = true;
      final generation = _selectionTransformGeneration;
      SchedulerBinding.instance.scheduleFrameCallback((_) {
        if (!mounted || generation != _selectionTransformGeneration) return;
        _selectionPaintScheduled = false;
        _recordDocumentPicture();
        _syncLivePainter();
        setState(() {});
      });
    }
  }

  void _finishSelectionTransform() {
    final changed = _selectionTransformChanged;
    _selectionTransformGeneration++;
    _selectionPaintScheduled = false;
    _clearSelectionTransformState();
    if (changed) {
      _spatial.rebuild(_strokes);
      _recordDocumentPicture();
      _commitQueue?.enqueue(StrokeCodec.strokesToDocument(_strokes));
    }
    _notifySelection();
  }

  void _clearSelectionTransformState() {
    _selectionTransformMode = null;
    _selectionTransformStart = null;
    _selectionTransformAnchor = null;
    _selectionTransformStartHandle = null;
    _selectionTransformStartBounds = null;
    _selectionTransformOriginals = const <Stroke>[];
    _selectionTransformX = false;
    _selectionTransformY = false;
    _selectionTransformChanged = false;
  }

  bool _polylineTouchesCircle(
    List<StrokePoint> points,
    Offset center,
    double radius,
  ) {
    if (points.isEmpty) return false;
    if (points.length == 1) return (points.first.position - center).distance <= radius;
    for (var i = 1; i < points.length; i++) {
      if (_distanceToSegment(center, points[i - 1].position, points[i].position) <= radius) {
        return true;
      }
    }
    return false;
  }

  double _distanceToSegment(Offset point, Offset a, Offset b) {
    final segment = b - a;
    final lengthSquared = segment.distanceSquared;
    if (lengthSquared <= 1e-12) return (point - a).distance;
    final relative = point - a;
    final t = ((relative.dx * segment.dx + relative.dy * segment.dy) / lengthSquared)
        .clamp(0.0, 1.0)
        .toDouble();
    return (point - (a + segment * t)).distance;
  }

  List<List<StrokePoint>> _subtractCircle(
    List<StrokePoint> points,
    Offset center,
    double radius,
  ) {
    if (points.isEmpty) return <List<StrokePoint>>[];
    if (!radius.isFinite || radius <= 0) return <List<StrokePoint>>[List.of(points)];
    final radiusSquared = radius * radius;
    if (points.length == 1) {
      return (points.first.position - center).distanceSquared <= radiusSquared
          ? <List<StrokePoint>>[]
          : <List<StrokePoint>>[List.of(points)];
    }

    final pieces = <List<StrokePoint>>[];
    var current = <StrokePoint>[];
    void append(StrokePoint sample) {
      if (current.isEmpty ||
          current.last.position != sample.position ||
          current.last.pressure != sample.pressure) {
        current.add(sample);
      }
    }
    void finish() {
      if (current.isNotEmpty) {
        pieces.add(current);
        current = <StrokePoint>[];
      }
    }

    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1];
      final b = points[i];
      final delta = b.position - a.position;
      final lengthSquared = delta.distanceSquared;
      if (lengthSquared <= 1e-12) {
        if ((a.position - center).distanceSquared <= radiusSquared) {
          finish();
        } else {
          append(a);
          append(b);
        }
        continue;
      }

      final relative = center - a.position;
      final projection = (relative.dx * delta.dx + relative.dy * delta.dy) / lengthSquared;
      final closest = a.position + delta * projection;
      final distanceSquared = (center - closest).distanceSquared;
      final halfInterval = math.sqrt(math.max(0.0, (radiusSquared - distanceSquared) / lengthSquared));
      final rawEnter = projection - halfInterval;
      final rawExit = projection + halfInterval;

      if (distanceSquared >= radiusSquared || rawExit <= 0 || rawEnter >= 1) {
        append(a);
        append(b);
        continue;
      }

      final enter = rawEnter.clamp(0.0, 1.0).toDouble();
      final exit = rawExit.clamp(0.0, 1.0).toDouble();
      if (enter > 0) {
        append(a);
        append(_interpolateStrokePoint(a, b, enter));
        finish();
      } else {
        finish();
      }
      if (exit < 1) {
        append(_interpolateStrokePoint(a, b, exit));
        append(b);
      } else {
        finish();
      }
    }
    finish();
    return pieces;
  }

  StrokePoint _interpolateStrokePoint(StrokePoint a, StrokePoint b, double t) {
    double lerp(double x, double y) => x + (y - x) * t;
    return StrokePoint(
      position: Offset.lerp(a.position, b.position, t)!,
      pressure: lerp(a.pressure, b.pressure),
      timestamp: lerp(a.timestamp, b.timestamp),
      tilt: lerp(a.tilt, b.tilt),
      orientation: lerp(a.orientation, b.orientation),
    );
  }

  void _finishLasso() {
    if (_lasso.length < 3) {
      _clearActiveState();
      return;
    }

    _selected.clear();
    for (final stroke in _strokes) {
      if (LassoGeometry.strokeIntersectsPolygon(stroke.points, _lasso)) {
        _selected.add(stroke.id);
      }
    }

    _recordDocumentPicture();
    _notifySelection();
    _clearActiveState();
    _syncLivePainter();
  }


  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _pointerDown,
      onPointerMove: _pointerMove,
      onPointerUp: _pointerUp,
      onPointerCancel: _pointerCancel,
      onPointerHover: (_) => _recordInput(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: CustomPaint(
              painter: _PicturePainter(_documentPicture),
              child: const SizedBox.expand(),
            ),
          ),
          RepaintBoundary(
            child: CustomPaint(
              painter: _LiveInkPainter(
                liveState: _repaint,
              ),
              child: const SizedBox.expand(),
            ),
          ),
          if (_selected.isNotEmpty)
            CustomPaint(
              painter: _SelectionOverlayPainter(bounds: _selectionBounds),
              child: const SizedBox.expand(),
            ),
          if (widget.showPerformanceOverlay && _perfEnabled)
            WritingPerformanceOverlay(stats: _perf),
        ],
      ),
    );
  }
}