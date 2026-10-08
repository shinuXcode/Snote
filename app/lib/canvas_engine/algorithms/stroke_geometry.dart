import 'dart:math' as math;
import 'dart:ui';

import '../models/stroke.dart';

/// Geometry shared by live and committed ink.
///
/// A stroke is represented as one continuous ribbon instead of independent
/// variable-width line segments. This avoids visible seams/flicker at joins.
class StrokeGeometry {
  const StrokeGeometry._();

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
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    return path;
  }

  static Path buildRibbonPath(
    List<StrokePoint> points,
    double Function(StrokePoint point, int index) radiusFor,
  ) {
    final path = Path();
    if (points.isEmpty) return path;
    if (points.length == 1) {
      final r = radiusFor(points.first, 0).abs().clamp(.25, 60).toDouble();
      path.addOval(Rect.fromCircle(center: points.first.position, radius: r));
      return path;
    }

    final left = <Offset>[];
    final right = <Offset>[];
    final radii = <double>[];

    for (var i = 0; i < points.length; i++) {
      final previous = points[i == 0 ? i : i - 1].position;
      final next = points[i + 1 < points.length ? i + 1 : i].position;
      var tangent = next - previous;
      if (tangent.distanceSquared < .0001 && i > 0) {
        tangent = points[i].position - points[i - 1].position;
      }
      if (tangent.distanceSquared < .0001) {
        tangent = const Offset(1, 0);
      } else {
        tangent = tangent / tangent.distance;
      }

      final normal = Offset(-tangent.dy, tangent.dx);
      final radius = radiusFor(points[i], i).abs().clamp(.25, 60).toDouble();
      radii.add(radius);
      left.add(points[i].position + normal * radius);
      right.add(points[i].position - normal * radius);
    }

    path.moveTo(left.first.dx, left.first.dy);
    for (var i = 1; i < left.length; i++) {
      final previous = left[i - 1];
      final current = left[i];
      final middle = Offset(
        (previous.dx + current.dx) * .5,
        (previous.dy + current.dy) * .5,
      );
      path.quadraticBezierTo(
        previous.dx,
        previous.dy,
        middle.dx,
        middle.dy,
      );
    }
    path.lineTo(left.last.dx, left.last.dy);

    _roundCap(
      path,
      points.last.position,
      left.last,
      right.last,
      radii.last,
    );

    for (var i = right.length - 1; i > 0; i--) {
      final previous = right[i];
      final current = right[i - 1];
      final middle = Offset(
        (previous.dx + current.dx) * .5,
        (previous.dy + current.dy) * .5,
      );
      path.quadraticBezierTo(
        previous.dx,
        previous.dy,
        middle.dx,
        middle.dy,
      );
    }
    path.lineTo(right.first.dx, right.first.dy);

    _roundCap(
      path,
      points.first.position,
      right.first,
      left.first,
      radii.first,
    );

    path.close();
    return path;
  }

  static void _roundCap(
    Path path,
    Offset center,
    Offset from,
    Offset to,
    double radius,
  ) {
    final startAngle = math.atan2(
      from.dy - center.dy,
      from.dx - center.dx,
    );
    final endAngle = math.atan2(
      to.dy - center.dy,
      to.dx - center.dx,
    );

    var sweep = endAngle - startAngle;
    while (sweep <= -math.pi) sweep += math.pi * 2;
    while (sweep > math.pi) sweep -= math.pi * 2;

    path.arcTo(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweep,
      false,
    );
  }
}