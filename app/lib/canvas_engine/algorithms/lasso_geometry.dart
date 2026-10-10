import 'dart:math' as math;
import 'dart:ui';

import '../models/stroke.dart';

/// Geometric hit-testing shared by lasso selection and future selection tools.
class LassoGeometry {
  const LassoGeometry._();

  static bool pointInPolygon(Offset point, List<Offset> polygon) {
    if (polygon.length < 3) return false;

    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final a = polygon[j];
      final b = polygon[i];
      if (_pointOnSegment(point, a, b)) return true;

      final crossesScanline = (a.dy > point.dy) != (b.dy > point.dy);
      if (!crossesScanline) continue;
      final intersectionX =
          a.dx + (point.dy - a.dy) * (b.dx - a.dx) / (b.dy - a.dy);
      if (point.dx < intersectionX) inside = !inside;
    }
    return inside;
  }

  /// Selects when a sample is inside the lasso or when a stroke segment crosses
  /// a polygon edge. This prevents misses for sparse stylus samples.
  static bool strokeIntersectsPolygon(
    List<StrokePoint> points,
    List<Offset> polygon,
  ) {
    if (points.isEmpty || polygon.length < 3) return false;
    for (final point in points) {
      if (pointInPolygon(point.position, polygon)) return true;
    }

    for (var i = 1; i < points.length; i++) {
      final start = points[i - 1].position;
      final end = points[i].position;
      for (var edge = 0; edge < polygon.length; edge++) {
        if (_segmentsIntersect(
          start,
          end,
          polygon[edge],
          polygon[(edge + 1) % polygon.length],
        )) {
          return true;
        }
      }
    }
    return false;
  }

  static bool _segmentsIntersect(Offset a, Offset b, Offset c, Offset d) {
    const epsilon = 1e-7;
    final abC = _orientation(a, b, c);
    final abD = _orientation(a, b, d);
    final cdA = _orientation(c, d, a);
    final cdB = _orientation(c, d, b);
    final abCross = (abC > epsilon && abD < -epsilon) ||
        (abC < -epsilon && abD > epsilon);
    final cdCross = (cdA > epsilon && cdB < -epsilon) ||
        (cdA < -epsilon && cdB > epsilon);
    if (abCross && cdCross) return true;

    return (abC.abs() <= epsilon && _pointOnSegment(c, a, b)) ||
        (abD.abs() <= epsilon && _pointOnSegment(d, a, b)) ||
        (cdA.abs() <= epsilon && _pointOnSegment(a, c, d)) ||
        (cdB.abs() <= epsilon && _pointOnSegment(b, c, d));
  }

  static double _orientation(Offset a, Offset b, Offset c) =>
      (b.dx - a.dx) * (c.dy - a.dy) -
      (b.dy - a.dy) * (c.dx - a.dx);

  static bool _pointOnSegment(Offset point, Offset a, Offset b) {
    const epsilon = 1e-6;
    final cross = _orientation(a, b, point);
    final length = (b - a).distance;
    if (cross.abs() > epsilon * math.max(1, length)) return false;
    final dot = (point.dx - a.dx) * (b.dx - a.dx) +
        (point.dy - a.dy) * (b.dy - a.dy);
    return dot >= -epsilon && dot <= length * length + epsilon;
  }
}
