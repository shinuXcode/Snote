import 'dart:math' as math;
import 'dart:ui';

import '../models/stroke.dart';

/// Geometry tests for erasing and lasso selection. These routines work on
/// vector samples rather than assuming every segment contains a sample inside
/// the hit area.
class InkHitTesting {
  const InkHitTesting._();

  static double distanceToSegment(Offset point, Offset a, Offset b) {
    final segment = b - a;
    final lengthSquared = segment.distanceSquared;
    if (lengthSquared <= 1e-12) return (point - a).distance;

    final relative = point - a;
    final t = ((relative.dx * segment.dx + relative.dy * segment.dy) /
            lengthSquared)
        .clamp(0.0, 1.0)
        .toDouble();
    return (point - (a + segment * t)).distance;
  }

  static bool polylineTouchesCircle(
    List<StrokePoint> points,
    Offset center,
    double radius,
  ) {
    if (points.isEmpty || !radius.isFinite || radius < 0) return false;
    if (points.length == 1) {
      return (points.first.position - center).distance <= radius;
    }
    for (var i = 1; i < points.length; i++) {
      if (distanceToSegment(center, points[i - 1].position, points[i].position) <=
          radius) {
        return true;
      }
    }
    return false;
  }

  /// Returns the surviving portions of [points] after subtracting a circular
  /// eraser from each line segment. Boundary intersections are interpolated,
  /// so sparse input samples cannot leave a bridge through the erased area.
  static List<List<StrokePoint>> subtractCircle(
    List<StrokePoint> points,
    Offset center,
    double radius,
  ) {
    if (points.isEmpty) return <List<StrokePoint>>[];
    if (!radius.isFinite || radius <= 0) {
      return <List<StrokePoint>>[List<StrokePoint>.of(points)];
    }
    final radiusSquared = radius * radius;
    if (points.length == 1) {
      return (points.first.position - center).distanceSquared <= radiusSquared
          ? <List<StrokePoint>>[]
          : <List<StrokePoint>>[List<StrokePoint>.of(points)];
    }

    final pieces = <List<StrokePoint>>[];
    var current = <StrokePoint>[];

    void appendDistinct(StrokePoint point) {
      if (current.isEmpty ||
          current.last.position != point.position ||
          current.last.pressure != point.pressure) {
        current.add(point);
      }
    }

    void finishCurrent() {
      if (current.isNotEmpty) {
        pieces.add(current);
        current = <StrokePoint>[];
      }
    }

    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1];
      final b = points[i];
      final delta = b.position - a.position;
      final lengthSquared = delta.distanceSquared;

      if (lengthSquared <= 1e-12) {
        if ((a.position - center).distanceSquared <= radiusSquared) {
          finishCurrent();
        } else {
          appendDistinct(a);
          appendDistinct(b);
        }
        continue;
      }

      final relative = center - a.position;
      final projection = (relative.dx * delta.dx + relative.dy * delta.dy) /
          lengthSquared;
      final closestOnInfiniteLine = a.position + delta * projection;
      final distanceSquared =
          (center - closestOnInfiniteLine).distanceSquared;
      final halfInterval = math.sqrt(
        math.max(0.0, (radiusSquared - distanceSquared) / lengthSquared),
      );
      final rawEnter = projection - halfInterval;
      final rawExit = projection + halfInterval;

      // The circle can intersect the infinite line but not this finite segment.
      // Tangencies have no erased area and should not create zero-width breaks.
      if (distanceSquared >= radiusSquared ||
          rawExit <= 0 ||
          rawEnter >= 1) {
        appendDistinct(a);
        appendDistinct(b);
        continue;
      }

      final enter = rawEnter.clamp(0.0, 1.0).toDouble();
      final exit = rawExit.clamp(0.0, 1.0).toDouble();

      if (enter > 0) {
        appendDistinct(a);
        appendDistinct(_interpolate(a, b, enter));
        finishCurrent();
      } else {
        // The segment starts inside the disk, so any earlier piece ends before
        // this point and must not bridge through the erased region.
        finishCurrent();
      }

      if (exit < 1) {
        appendDistinct(_interpolate(a, b, exit));
        appendDistinct(b);
      } else {
        finishCurrent();
      }
    }

    finishCurrent();
    return pieces;
  }

  /// True when any painted stroke segment touches a rectangular eraser footprint.
  static bool polylineTouchesRect(
    List<StrokePoint> points,
    Rect rect, {
    double padding = 0,
  }) {
    if (points.isEmpty || !rect.isFinite) return false;
    final target = padding > 0 ? rect.inflate(padding) : rect;
    if (points.length == 1) return target.contains(points.first.position);
    for (var i = 1; i < points.length; i++) {
      if (_clipSegmentToRect(
            points[i - 1].position,
            points[i].position,
            target,
          ) !=
          null) {
        return true;
      }
    }
    return false;
  }

  /// Removes portions of a vector polyline covered by [rect], preserving the
  /// unaffected geometry on either side of each intersection.
  static List<List<StrokePoint>> subtractRect(
    List<StrokePoint> points,
    Rect rect,
  ) {
    if (points.isEmpty) return <List<StrokePoint>>[];
    if (!rect.isFinite) return <List<StrokePoint>>[List<StrokePoint>.of(points)];
    if (points.length == 1) {
      return rect.contains(points.first.position)
          ? <List<StrokePoint>>[]
          : <List<StrokePoint>>[List<StrokePoint>.of(points)];
    }

    final pieces = <List<StrokePoint>>[];
    var current = <StrokePoint>[];

    void appendDistinct(StrokePoint point) {
      if (current.isEmpty ||
          current.last.position != point.position ||
          current.last.pressure != point.pressure) {
        current.add(point);
      }
    }

    void finishCurrent() {
      if (current.isNotEmpty) {
        pieces.add(current);
        current = <StrokePoint>[];
      }
    }

    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1];
      final b = points[i];
      final clipped = _clipSegmentToRect(a.position, b.position, rect);
      if (clipped == null ||
          (clipped[1] - clipped[0]).abs() <= 1e-8) {
        appendDistinct(a);
        appendDistinct(b);
        continue;
      }

      final enter = clipped[0];
      final exit = clipped[1];
      if (enter > 1e-8) {
        appendDistinct(a);
        appendDistinct(_interpolate(a, b, enter));
        finishCurrent();
      } else {
        finishCurrent();
      }

      if (exit < 1 - 1e-8) {
        appendDistinct(_interpolate(a, b, exit));
        appendDistinct(b);
      } else {
        finishCurrent();
      }
    }

    finishCurrent();
    return pieces;
  }

  /// Returns the clipped parameter interval of segment [a,b] within [rect].
  /// Uses Liang-Barsky clipping, including segments whose endpoints are both
  /// outside but whose interior crosses the eraser.
  static List<double>? _clipSegmentToRect(Offset a, Offset b, Rect rect) {
    final delta = b - a;
    var enter = 0.0;
    var exit = 1.0;
    const epsilon = 1e-10;

    final p = <double>[-delta.dx, delta.dx, -delta.dy, delta.dy];
    final q = <double>[
      a.dx - rect.left,
      rect.right - a.dx,
      a.dy - rect.top,
      rect.bottom - a.dy,
    ];

    for (var i = 0; i < 4; i++) {
      if (p[i].abs() <= epsilon) {
        if (q[i] < 0) return null;
        continue;
      }
      final ratio = q[i] / p[i];
      if (p[i] < 0) {
        if (ratio > exit) return null;
        if (ratio > enter) enter = ratio;
      } else {
        if (ratio < enter) return null;
        if (ratio < exit) exit = ratio;
      }
    }

    if (enter > exit) return null;
    return <double>[enter.clamp(0.0, 1.0).toDouble(), exit.clamp(0.0, 1.0).toDouble()];
  }

  /// Public point-in-polygon test shared by selection and smart fill.
  static bool pointInPolygon(Offset point, List<Offset> polygon) =>
      _pointInPolygon(point, polygon);

  /// Selects a stroke only when most of its painted centreline lies within the
  /// lasso. A single intersection with the polygon edge no longer selects a
  /// long stroke that is mostly outside the user's selection.
  static bool polylineMostlyInsidePolygon(
    List<StrokePoint> points,
    List<Offset> polygon, {
    double minimumInsideFraction = .65,
  }) {
    if (points.isEmpty || polygon.length < 3) return false;
    if (points.length == 1) {
      return _pointInPolygon(points.first.position, polygon);
    }

    var totalLength = 0.0;
    for (var i = 1; i < points.length; i++) {
      totalLength += (points[i].position - points[i - 1].position).distance;
    }
    if (totalLength <= 1e-6) {
      return _pointInPolygon(points.first.position, polygon);
    }

    final sampleStep = math.max(1.5, totalLength / 1024);
    var insideLength = 0.0;
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1].position;
      final b = points[i].position;
      final length = (b - a).distance;
      if (length <= 1e-8) continue;
      final samples = math.max(1, (length / sampleStep).ceil());
      final sampleLength = length / samples;
      for (var sample = 0; sample < samples; sample++) {
        final t = (sample + .5) / samples;
        final point = Offset.lerp(a, b, t)!;
        if (_pointInPolygon(point, polygon)) insideLength += sampleLength;
      }
    }
    return insideLength / totalLength >=
        minimumInsideFraction.clamp(0.0, 1.0);
  }

  static bool polylineIntersectsPolygon(
    List<StrokePoint> points,
    List<Offset> polygon,
  ) {
    if (points.isEmpty || polygon.length < 3) return false;
    if (points.any((point) => _pointInPolygon(point.position, polygon))) {
      return true;
    }
    if (points.length < 2) return false;

    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1].position;
      final b = points[i].position;
      for (var j = 0; j < polygon.length; j++) {
        final c = polygon[j];
        final d = polygon[(j + 1) % polygon.length];
        if (_segmentsIntersect(a, b, c, d)) return true;
      }
    }
    return false;
  }

  static StrokePoint _interpolate(
    StrokePoint a,
    StrokePoint b,
    double t,
  ) {
    double lerp(double x, double y) => x + (y - x) * t;
    return StrokePoint(
      position: Offset.lerp(a.position, b.position, t)!,
      pressure: lerp(a.pressure, b.pressure),
      timestamp: lerp(a.timestamp, b.timestamp),
      tilt: lerp(a.tilt, b.tilt),
      orientation: lerp(a.orientation, b.orientation),
    );
  }

  static bool _pointInPolygon(Offset point, List<Offset> polygon) {
    var inside = false;
    for (var i = 0, j = polygon.length - 1;
        i < polygon.length;
        j = i++) {
      final a = polygon[i];
      final b = polygon[j];
      final crosses = (a.dy > point.dy) != (b.dy > point.dy);
      if (!crosses) continue;
      final x = (b.dx - a.dx) * (point.dy - a.dy) /
              (b.dy - a.dy) +
          a.dx;
      if (point.dx < x) inside = !inside;
    }
    return inside;
  }

  static bool _segmentsIntersect(Offset a, Offset b, Offset c, Offset d) {
    const epsilon = 1e-9;
    double cross(Offset p, Offset q, Offset r) =>
        (q.dx - p.dx) * (r.dy - p.dy) -
        (q.dy - p.dy) * (r.dx - p.dx);

    bool onSegment(Offset p, Offset q, Offset r) =>
        q.dx >= math.min(p.dx, r.dx) - epsilon &&
        q.dx <= math.max(p.dx, r.dx) + epsilon &&
        q.dy >= math.min(p.dy, r.dy) - epsilon &&
        q.dy <= math.max(p.dy, r.dy) + epsilon;

    final abC = cross(a, b, c);
    final abD = cross(a, b, d);
    final cdA = cross(c, d, a);
    final cdB = cross(c, d, b);

    if (((abC > epsilon && abD < -epsilon) ||
            (abC < -epsilon && abD > epsilon)) &&
        ((cdA > epsilon && cdB < -epsilon) ||
            (cdA < -epsilon && cdB > epsilon))) {
      return true;
    }
    if (abC.abs() <= epsilon && onSegment(a, c, b)) return true;
    if (abD.abs() <= epsilon && onSegment(a, d, b)) return true;
    if (cdA.abs() <= epsilon && onSegment(c, a, d)) return true;
    if (cdB.abs() <= epsilon && onSegment(c, b, d)) return true;
    return false;
  }
}
