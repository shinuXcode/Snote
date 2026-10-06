import 'package:flutter/material.dart';
import '../models/pen_config.dart';
import '../models/stroke.dart';
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
    for (final stroke in strokes) {
      _drawStroke(canvas, stroke);
    }
    if (activeStroke != null) {
      _drawStroke(canvas, activeStroke!);
    }
  }

  void _drawStroke(Canvas canvas, Stroke stroke) {
    final points = stroke.points;
    if (points.isEmpty) return;

    if (points.length == 1) {
      final paint = Paint()
        ..color = stroke.pen.color.withValues(alpha: stroke.pen.opacity)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(points.first.position, stroke.pen.size / 2, paint);
      return;
    }

    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1];
      final b = points[i];

      var width = stroke.pen.size;
      if (stroke.pen.type == PenType.fountain) {
        final dt = (b.timestamp - a.timestamp).clamp(0.5, 250.0);
        final velocity = dt <= 0
            ? 0.0
            : (b.position - a.position).distance / dt;
        width = fountainWidth(
          baseWidth: stroke.pen.size,
          velocity: velocity,
          pressure: b.pressure,
        );
      } else {
        width *= (0.75 + b.pressure.clamp(0, 1) * 0.25);
      }

      final paint = Paint()
        ..color = stroke.pen.color.withValues(
          alpha: stroke.pen.type == PenType.pencil
              ? stroke.pen.opacity * .72
              : stroke.pen.opacity,
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      if (stroke.pen.type == PenType.highlighter) {
        paint
          ..blendMode = BlendMode.multiply
          ..strokeWidth = width * 1.8;
      }

      final midpoint = Offset(
        (a.position.dx + b.position.dx) / 2,
        (a.position.dy + b.position.dy) / 2,
      );

      final path = Path()
        ..moveTo(a.position.dx, a.position.dy)
        ..quadraticBezierTo(
          a.position.dx,
          a.position.dy,
          midpoint.dx,
          midpoint.dy,
        );

      canvas.drawPath(path, paint);

      if (stroke.pen.type == PenType.pencil) {
        final texturePaint = Paint()
          ..color = stroke.pen.color.withValues(alpha: stroke.pen.opacity * .12)
          ..style = PaintingStyle.stroke
          ..strokeWidth = width * .55
          ..strokeCap = StrokeCap.round;

        final offset = Offset(
          ((i % 3) - 1) * .8,
          (((i + 1) % 3) - 1) * .8,
        );
        canvas.drawLine(
          a.position + offset,
          b.position + offset,
          texturePaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant SnoteCanvasPainter oldDelegate) =>
      !identical(oldDelegate.strokes, strokes) ||
      oldDelegate.activeStroke != activeStroke;
}
