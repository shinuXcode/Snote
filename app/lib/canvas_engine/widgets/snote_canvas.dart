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
  final ValueChanged<Map<String, Object?>>? onChanged;
  final Map<String, Object?>? initialDocument;
  final SnoteCanvasController? controller;
  final Color backgroundColor;

  const SnoteCanvas({
    super.key,
    required this.pen,
    this.onChanged,
    this.initialDocument,
    this.controller,
    this.backgroundColor = Colors.white,
  });

  @override
  State<SnoteCanvas> createState() => _SnoteCanvasState();
}

class _SnoteCanvasState extends State<SnoteCanvas> {
  final _uuid = const Uuid();
  final _palmRejection = PalmRejection();

  final List<Stroke> _strokes = [];
  final List<List<Stroke>> _history = [];
  final List<List<Stroke>> _redo = [];

  Stroke? _activeStroke;
  int _activePointer = -1;

  @override
  void initState() {
    super.initState();
    _strokes.addAll(StrokeCodec.documentToStrokes(widget.initialDocument));
    _bindController();
  }

  @override
  void didUpdateWidget(covariant SnoteCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._unbind();
      _bindController();
    }
  }

  @override
  void dispose() {
    widget.controller?._unbind();
    super.dispose();
  }

  void _bindController() {
    widget.controller?._bind(
      undo: undo,
      redo: redo,
      clear: clear,
      canUndo: _history.isNotEmpty,
      canRedo: _redo.isNotEmpty,
    );
  }

  void _snapshot() {
    _history.add(List<Stroke>.of(_strokes));
    if (_history.length > 100) {
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
    _notifyAndRefresh();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _history.add(List<Stroke>.of(_strokes));
    _strokes
      ..clear()
      ..addAll(_redo.removeLast());
    _notifyAndRefresh();
  }

  void clear() {
    if (_strokes.isEmpty) return;
    _snapshot();
    _strokes.clear();
    _notifyAndRefresh();
  }

  void _notifyAndRefresh() {
    if (!mounted) return;
    setState(() {});
    _bindController();
    widget.onChanged?.call(StrokeCodec.strokesToDocument(_strokes));
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
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  void _pointerDown(PointerDownEvent event) {
    if (!_palmRejection.accepts(event) || _activePointer != -1) return;

    _activePointer = event.pointer;
    final timestamp = event.timeStamp.inMicroseconds / 1000;

    setState(() {
      _activeStroke = Stroke(
        id: _uuid.v4(),
        points: [
          StrokePoint(
            position: event.localPosition,
            pressure: event.pressure,
            timestamp: timestamp,
          ),
        ],
        pen: widget.pen,
      );
    });
  }

  void _pointerMove(PointerMoveEvent event) {
    final current = _activeStroke;
    if (current == null || event.pointer != _activePointer) return;

    final timestamp = event.timeStamp.inMicroseconds / 1000;
    final nextPoint = StrokePoint(
      position: event.localPosition,
      pressure: event.pressure,
      timestamp: timestamp,
    );

    setState(() {
      _activeStroke = Stroke(
        id: current.id,
        points: [...current.points, nextPoint],
        pen: current.pen,
      );
    });
  }

  void _pointerUp(PointerUpEvent event) {
    final current = _activeStroke;
    if (current == null || event.pointer != _activePointer) return;

    _snapshot();
    _strokes.add(current);
    _activeStroke = null;
    _activePointer = -1;
    _notifyAndRefresh();
  }

  void _pointerCancel(PointerCancelEvent event) {
    if (event.pointer != _activePointer) return;
    setState(() {
      _activeStroke = null;
      _activePointer = -1;
    });
  }
}
