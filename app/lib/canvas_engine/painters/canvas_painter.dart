import 'package:flutter/material.dart';
import '../models/stroke.dart';
import '../models/pen_config.dart';
import '../algorithms/velocity_calculator.dart';

class SnoteCanvasPainter extends CustomPainter {
  final List<Stroke> strokes;
  final Stroke? activeStroke;

  const SnoteCanvasPainter({
    required this.strokes,
    required this.activeStroke,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in [
      ...strokes,
      if (activeStroke != null) activeStroke!,
    ]) {
      _paintStroke(canvas, stroke);
    }
  }

  void _paintStroke(Canvas canvas, Stroke stroke) {
    if (stroke.points.isEmpty) return;

    final paint = Paint()
      ..color = stroke.pen.color.withOpacity(stroke.pen.opacity)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (stroke.pen.type == PenType.highlighter) {
      paint.blendMode = BlendMode.multiply;
    }

    final path = Path()
      ..moveTo(
        stroke.points.first.position.dx,
        stroke.points.first.position.dy,
      );

    for (var i = 1; i < stroke.points.length; i++) {
      final p = stroke.points[i];
      final previous = stroke.points[i - 1];

      var width = stroke.pen.size;
      if (stroke.pen.type == PenType.fountain) {
        final dt = (p.timestamp - previous.timestamp).clamp(.1, 1000);
        final velocity = (p.position - previous.position).distance / dt;
        width = fountainWidth(
          baseWidth: stroke.pen.size,
          velocity: velocity,
          pressure: p.pressure,
        );
      }

      paint.strokeWidth = width;
      path.lineTo(p.position.dx, p.position.dy);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant SnoteCanvasPainter oldDelegate) =>
      oldDelegate.strokes != strokes ||
      oldDelegate.activeStroke != activeStroke;
}
