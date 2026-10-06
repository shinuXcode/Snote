import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../algorithms/bezier_smoother.dart';
import '../input/palm_rejection.dart';
import '../models/pen_config.dart';
import '../models/stroke.dart';
import '../painters/canvas_painter.dart';

class SnoteCanvas extends StatefulWidget {
  final PenConfig pen;

  const SnoteCanvas({
    super.key,
    required this.pen,
  });

  @override
  State<SnoteCanvas> createState() => _SnoteCanvasState();
}

class _SnoteCanvasState extends State<SnoteCanvas> {
  final _uuid = const Uuid();
  final _palmRejection = PalmRejection();
  final _smoother = BezierSmoother();

  final List<Stroke> _strokes = [];
  Stroke? _activeStroke;

  @override
  Widget build(BuildContext context) {
    return Listener(
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
    );
  }

  void _pointerDown(PointerDownEvent event) {
    if (!_palmRejection.accepts(event)) return;

    _smoother.reset();
    _smoother.add(event.localPosition);

    final point = StrokePoint(
      position: event.localPosition,
      pressure: event.pressure,
      timestamp: event.timeStamp.inMicroseconds / 1000,
    );

    setState(() {
      _activeStroke = Stroke(
        id: _uuid.v4(),
        points: [point],
        pen: widget.pen,
      );
    });
  }

  void _pointerMove(PointerMoveEvent event) {
    final current = _activeStroke;
    if (current == null) return;

    _smoother.add(event.localPosition);

    final point = StrokePoint(
      position: event.localPosition,
      pressure: event.pressure,
      timestamp: event.timeStamp.inMicroseconds / 1000,
    );

    setState(() {
      _activeStroke = Stroke(
        id: current.id,
        points: [...current.points, point],
        pen: current.pen,
      );
    });
  }

  void _pointerUp(PointerUpEvent event) {
    final current = _activeStroke;
    if (current == null) return;

    setState(() {
      _strokes.add(current);
      _activeStroke = null;
    });
    _smoother.reset();
  }

  void _pointerCancel(PointerCancelEvent event) {
    setState(() => _activeStroke = null);
    _smoother.reset();
  }
}
