import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/stroke.dart';
import '../models/pen_config.dart';
import '../algorithms/velocity_calculator.dart';

class SnoteCanvasPainter extends CustomPainter {
  final List<Stroke> strokes;
  final Stroke? activeStroke;
  final Set<String> selectedIds;
  final List<Offset> lassoPath;

  const SnoteCanvasPainter({
    required this.strokes,
    required this.activeStroke,
    this.selectedIds = const {},
    this.lassoPath = const [],
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      _drawStroke(canvas, stroke, selectedIds.contains(stroke.id));
    }
    if (activeStroke != null) _drawStroke(canvas, activeStroke!, false);

    if (lassoPath.length > 1) {
      final p = Paint()
        ..color = const Color(0xff3f6df6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      final path = Path()..moveTo(lassoPath.first.dx, lassoPath.first.dy);
      for (final point in lassoPath.skip(1)) path.lineTo(point.dx, point.dy);
      canvas.drawPath(path, p);
    }
  }

  void _drawStroke(Canvas canvas, Stroke stroke, bool selected) {
    final points = stroke.points;
    if (points.isEmpty) return;
    final color = stroke.pen.color.withValues(alpha: stroke.pen.opacity);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke.pen.size
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (selected) {
      final bounds = _bounds(points);
      final selectPaint = Paint()
        ..color = const Color(0xff3f6df6).withValues(alpha: .22)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(bounds.inflate(8), const Radius.circular(8)),
        selectPaint,
      );
    }

    if (points.length == 1) {
      canvas.drawCircle(points.first.position, stroke.pen.size / 2, Paint()..color = color);
      return;
    }

    if (stroke.shape != null) {
      _drawShape(canvas, stroke, paint);
      return;
    }

    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1];
      final b = points[i];
      var width = stroke.pen.size;
      if (stroke.pen.type == PenType.fountain) {
        final dt = (b.timestamp - a.timestamp).clamp(0.5, 250.0);
        final velocity = dt <= 0 ? 0.0 : (b.position - a.position).distance / dt;
        width = fountainWidth(baseWidth: stroke.pen.size, velocity: velocity, pressure: b.pressure);
      } else {
        width *= .75 + b.pressure.clamp(0, 1) * .25;
      }
      paint.strokeWidth = stroke.pen.type == PenType.highlighter ? width * 1.8 : width;
      paint.blendMode = stroke.pen.type == PenType.highlighter ? BlendMode.multiply : BlendMode.srcOver;
      final midpoint = Offset((a.position.dx + b.position.dx) / 2, (a.position.dy + b.position.dy) / 2);
      final path = Path()
        ..moveTo(a.position.dx, a.position.dy)
        ..quadraticBezierTo(a.position.dx, a.position.dy, midpoint.dx, midpoint.dy);
      canvas.drawPath(path, paint);
    }
  }

  void _drawShape(Canvas canvas, Stroke stroke, Paint paint) {
    final a = stroke.points.first.position;
    final b = stroke.points.last.position;
    final rect = Rect.fromPoints(a, b);
    switch (stroke.shape) {
      case 'line':
        canvas.drawLine(a, b, paint);
      case 'arrow':
        canvas.drawLine(a, b, paint);
        final direction = b - a;
        if (direction.distance > 1) {
          final unit = direction / direction.distance;
          final normal = Offset(-unit.dy, unit.dx);
          final tip = b - unit * 14;
          final p1 = tip + normal * 6;
          final p2 = tip - normal * 6;
          canvas.drawLine(b, p1, paint);
          canvas.drawLine(b, p2, paint);
        }
      case 'rectangle':
        canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)), paint);
      case 'ellipse':
        canvas.drawOval(rect, paint);
      case 'triangle':
        final top = Offset(rect.center.dx, rect.top);
        final left = Offset(rect.left, rect.bottom);
        final right = Offset(rect.right, rect.bottom);
        canvas.drawPath(Path()..moveTo(top.dx, top.dy)..lineTo(right.dx, right.dy)..lineTo(left.dx, left.dy)..close(), paint);
    }
  }

  Rect _bounds(List<StrokePoint> points) {
    var left = points.first.position.dx;
    var right = left;
    var top = points.first.position.dy;
    var bottom = top;
    for (final p in points.skip(1)) {
      left = left < p.position.dx ? left : p.position.dx;
      right = right > p.position.dx ? right : p.position.dx;
      top = top < p.position.dy ? top : p.position.dy;
      bottom = bottom > p.position.dy ? bottom : p.position.dy;
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  @override
  bool shouldRepaint(covariant SnoteCanvasPainter oldDelegate) =>
      !identical(oldDelegate.strokes, strokes) ||
      oldDelegate.activeStroke != activeStroke ||
      oldDelegate.selectedIds != selectedIds ||
      oldDelegate.lassoPath != lassoPath;
}
