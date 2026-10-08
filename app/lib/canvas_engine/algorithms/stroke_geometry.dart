import 'dart:ui';
import '../models/stroke.dart';

class StrokeGeometry {
  static Path buildPath(List<StrokePoint> points) {
    final path = Path();
    if (points.isEmpty) return path;
    path.moveTo(points.first.position.dx, points.first.position.dy);
    if (points.length == 1) return path;
    if (points.length == 2) {
      path.lineTo(points.last.position.dx, points.last.position.dy);
      return path;
    }

    for (var i = 1; i < points.length - 1; i++) {
      final current = points[i].position;
      final next = points[i + 1].position;
      final midpoint = Offset(
        (current.dx + next.dx) * .5,
        (current.dy + next.dy) * .5,
      );
      path.quadraticBezierTo(current.dx, current.dy, midpoint.dx, midpoint.dy);
    }

    final last = points.last.position;
    path.quadraticBezierTo(last.dx, last.dy, last.dx, last.dy);
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

    final firstMid = Offset(
      (points[0].position.dx + points[1].position.dx) * .5,
      (points[0].position.dy + points[1].position.dy) * .5,
    );
    final initial = Path()
      ..moveTo(points.first.position.dx, points.first.position.dy)
      ..lineTo(firstMid.dx, firstMid.dy);
    paint.strokeWidth = widthForSegment(points.first, points[1]);
    canvas.drawPath(initial, paint);

    for (var i = 1; i < points.length - 1; i++) {
      final start = Offset(
        (points[i - 1].position.dx + points[i].position.dx) * .5,
        (points[i - 1].position.dy + points[i].position.dy) * .5,
      );
      final end = Offset(
        (points[i].position.dx + points[i + 1].position.dx) * .5,
        (points[i].position.dy + points[i + 1].position.dy) * .5,
      );
      final segment = Path()
        ..moveTo(start.dx, start.dy)
        ..quadraticBezierTo(
          points[i].position.dx,
          points[i].position.dy,
          end.dx,
          end.dy,
        );
      paint.strokeWidth = widthForSegment(points[i], points[i + 1]);
      canvas.drawPath(segment, paint);
    }

    final lastMid = Offset(
      (points[points.length - 2].position.dx + points.last.position.dx) * .5,
      (points[points.length - 2].position.dy + points.last.position.dy) * .5,
    );
    final finalPath = Path()
      ..moveTo(lastMid.dx, lastMid.dy)
      ..lineTo(points.last.position.dx, points.last.position.dy);
    paint.strokeWidth = widthForSegment(points[points.length - 2], points.last);
    canvas.drawPath(finalPath, paint);
  }
}
