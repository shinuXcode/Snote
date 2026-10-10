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

    if (closure > math.max(14, smallerSide * .22) ||
        perimeterRatio < .62 ||
        perimeterRatio > 1.6) {
      return null;
    }

    final aspect = bounds.width / bounds.height;
    if (aspect >= .72 && aspect <= 1.38 && perimeterRatio < .9) {
      return 'ellipse';
    }
    if (perimeterRatio >= .9 && perimeterRatio <= 1.6) return 'rectangle';
    if (perimeterRatio >= .62 && perimeterRatio < .9) return 'ellipse';
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
