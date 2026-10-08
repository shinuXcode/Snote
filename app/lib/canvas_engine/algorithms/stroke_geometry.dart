import 'dart:ui';

import '../models/stroke.dart';

/// Continuous cubic centerline geometry used by both live and final ink.
class StrokeGeometry {
  static Path buildPath(List<StrokePoint> points) {
    final path = Path();
    if (points.isEmpty) return path;
    if (points.length == 1) {
      path.moveTo(points.first.position.dx, points.first.position.dy);
      return path;
    }
    if (points.length == 2) {
      path
        ..moveTo(points.first.position.dx, points.first.position.dy)
        ..lineTo(points.last.position.dx, points.last.position.dy);
      return path;
    }

    path.moveTo(points.first.position.dx, points.first.position.dy);

    for (var i = 0; i < points.length - 1; i++) {
      final p0 = points[i == 0 ? i : i - 1].position;
      final p1 = points[i].position;
      final p2 = points[i + 1].position;
      final p3 = points[i + 2 < points.length ? i + 2 : i + 1].position;

      final c1 = p1 + (p2 - p0) / 6;
      final c2 = p2 - (p3 - p1) / 6;
      path.cubicTo(
        c1.dx,
        c1.dy,
        c2.dx,
        c2.dy,
        p2.dx,
        p2.dy,
      );
    }
    return path;
  }

  static void drawVariableWidth(
    Canvas canvas,
    List<StrokePoint> points,
    Paint paint,
    double Function(StrokePoint a, StrokePoint b) widthForSegment,
  ) {
    if (points.isEmpty) return;

    if (points.length == 1) {
      paint.strokeWidth = widthForSegment(points.first, points.first);
      canvas.drawCircle(
        points.first.position,
        (paint.strokeWidth * .5).clamp(.5, 30),
        paint,
      );
      return;
    }

    if (points.length == 2) {
      paint.strokeWidth = widthForSegment(points.first, points.last);
      canvas.drawLine(points.first.position, points.last.position, paint);
      return;
    }

    for (var i = 0; i < points.length - 1; i++) {
      final p0 = points[i == 0 ? i : i - 1].position;
      final p1 = points[i].position;
      final p2 = points[i + 1].position;
      final p3 = points[i + 2 < points.length ? i + 2 : i + 1].position;

      final c1 = p1 + (p2 - p0) / 6;
      final c2 = p2 - (p3 - p1) / 6;

      paint.strokeWidth = widthForSegment(points[i], points[i + 1]);
      final path = Path()
        ..moveTo(p1.dx, p1.dy)
        ..cubicTo(
          c1.dx,
          c1.dy,
          c2.dx,
          c2.dy,
          p2.dx,
          p2.dy,
        );
      canvas.drawPath(path, paint);
    }
  }
}
