import 'dart:math' as math;
import 'dart:ui';

import '../models/stroke.dart';

/// Conservative shape recognition that keeps original samples intact and
/// returns a vector-rendering hint for the committed stroke.
class ShapeRecognizer {
  const ShapeRecognizer._();

  static String? recognize(List<StrokePoint> points) {
    if (points.length < 5) return null;

    final start = points.first.position;
    final end = points.last.position;
    final chord = (end - start).distance;
    if (chord >= 20) {
      var maximumDeviation = 0.0;
      final dx = end.dx - start.dx;
      final dy = end.dy - start.dy;
      for (final sample in points) {
        final relative = sample.position - start;
        final deviation = (relative.dx * dy - relative.dy * dx).abs() / chord;
        maximumDeviation = math.max(maximumDeviation, deviation);
      }
      if (maximumDeviation <= math.max(3.5, chord * .035)) return 'line';
    }

    final bounds = _bounds(points);
    if (bounds.width < 18 || bounds.height < 18) return null;

    var pathLength = 0.0;
    for (var i = 1; i < points.length; i++) {
      pathLength += (points[i].position - points[i - 1].position).distance;
    }
    final smallerSide = math.min(bounds.width, bounds.height);
    final closure = (end - start).distance;
    final expectedPerimeter = 2 * (bounds.width + bounds.height);
    final perimeterRatio = pathLength / math.max(1, expectedPerimeter);

    if (closure > math.max(14, smallerSide * .22)) return null;

    // Rectangles keep most samples close to one of their four bounding edges.
    // A perimeter ratio alone misclassifies triangles and irregular polygons.
    final edgeTolerance = math.max(3, smallerSide * .08);
    var edgeSamples = 0;
    for (final sample in points) {
      final point = sample.position;
      final nearHorizontalEdge =
          (point.dy - bounds.top).abs() <= edgeTolerance ||
          (point.dy - bounds.bottom).abs() <= edgeTolerance;
      final nearVerticalEdge =
          (point.dx - bounds.left).abs() <= edgeTolerance ||
          (point.dx - bounds.right).abs() <= edgeTolerance;
      if (nearHorizontalEdge || nearVerticalEdge) edgeSamples++;
    }
    final edgeRatio = edgeSamples / points.length;
    if (perimeterRatio >= .82 &&
        perimeterRatio <= 1.4 &&
        edgeRatio >= .68) {
      return 'rectangle';
    }

    // Ellipse samples stay close to unit radius after normalizing around the
    // bounding box. This avoids snapping triangular/irregular loops to ovals.
    var radialError = 0.0;
    final center = bounds.center;
    final radiusX = bounds.width / 2;
    final radiusY = bounds.height / 2;
    for (final sample in points) {
      final dx = (sample.position.dx - center.dx) / radiusX;
      final dy = (sample.position.dy - center.dy) / radiusY;
      radialError += (math.sqrt(dx * dx + dy * dy) - 1).abs();
    }
    radialError /= points.length;

    if (perimeterRatio >= .62 &&
        perimeterRatio <= .92 &&
        radialError <= .18) {
      return 'ellipse';
    }
    return null;
  }

  static Rect _bounds(List<StrokePoint> points) {
    var left = points.first.position.dx;
    var right = left;
    var top = points.first.position.dy;
    var bottom = top;
    for (final sample in points.skip(1)) {
      left = math.min(left, sample.position.dx);
      right = math.max(right, sample.position.dx);
      top = math.min(top, sample.position.dy);
      bottom = math.max(bottom, sample.position.dy);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }
}
