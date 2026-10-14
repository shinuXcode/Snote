import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'algorithms/stroke_geometry.dart';
import 'algorithms/velocity_calculator.dart';
import 'models/pen_config.dart';
import 'models/stroke.dart';

/// Sample alpha for fountain ink. Faster strokes carry less ink; higher
/// pressure increases ink density. Speed uses logical pixels per 16 ms frame.
double fountainOpacityForSample({
  required double pressure,
  required double speed,
  required PenConfig pen,
}) {
  final pressureAmount = curvePressure(pressure.clamp(0, 1).toDouble(), pen);
  final normalizedSpeed = (speed / 20).clamp(0.0, 1.0).toDouble();
  final feed = 1 -
      normalizedSpeed *
          (.30 + pen.velocitySensitivity.clamp(0, 1).toDouble() * .38);
  return (pen.opacity.clamp(.05, 1).toDouble() *
          (.42 + pressureAmount * .58) * feed)
      .clamp(.08, 1)
      .toDouble();
}

/// Snote's retained-mode ink compositor.
///
/// All tools share the same centerline/ribbon renderer so live and finalized
/// ink have identical geometry. The document layer is cached separately from
/// the active stroke layer by SnoteCanvas.
class InkRenderer {
  const InkRenderer._();

  static void drawInk(
    Canvas canvas,
    List<StrokePoint> points,
    PenConfig pen,
  ) {
    if (points.isEmpty) return;
    if (pen.type == PenType.fountain) {
      _drawFountainSegments(canvas, points, pen);
      return;
    }

    final opacity = (pen.type == PenType.highlighter
            ? pen.opacity.clamp(.08, .55)
            : pen.opacity.clamp(.05, 1))
        .toDouble();

    final paint = Paint()
      ..color = pen.color.withValues(alpha: opacity)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true
      ..blendMode = pen.type == PenType.highlighter
          ? BlendMode.multiply
          : pen.type == PenType.marker
              ? BlendMode.multiply
              : BlendMode.srcOver;

    final path = StrokeGeometry.buildRibbonPath(
      points,
      (point, index) => _radiusFor(points, index, pen),
    );
    canvas.drawPath(path, paint);

    // A narrow center pass makes tiny handwriting strokes read crisply at
    // fractional device-pixel positions without changing the stored geometry.
    if (pen.size <= 2.2 && points.length > 1) {
      final centerPaint = Paint()
        ..color = pen.color.withValues(alpha: opacity * .16)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = (pen.size * .28).clamp(.25, .8)
        ..isAntiAlias = true;
      canvas.drawPath(StrokeGeometry.buildPath(points), centerPaint);
    }
  }

  static void _drawFountainSegments(
    Canvas canvas,
    List<StrokePoint> points,
    PenConfig pen,
  ) {
    if (points.isEmpty) return;
    if (points.length == 1) {
      final point = points.single;
      final radius = _radiusFor(points, 0, pen);
      canvas.drawCircle(
        point.position,
        math.max(.25, radius),
        Paint()
          ..color = pen.color.withValues(
            alpha: fountainOpacityForSample(
              pressure: point.pressure,
              speed: 0,
              pen: pen,
            ),
          )
          ..isAntiAlias = true,
      );
      return;
    }

    // Subdivide each input segment with a Catmull-Rom curve. This keeps the
    // stored samples untouched while removing angular joins from the rendered
    // nib outline. Two substeps per sample pair keep the active-stroke cost low.
    final samples = _smoothFountainSamples(points);
    if (samples.length < 2) return;

    final leftEdge = <Offset>[];
    final rightEdge = <Offset>[];
    var opacityTotal = 0.0;
    var opacitySamples = 0;

    // Gradual start/end taper produces a flexible nib rather than a sequence
    // of round-ended ballpoint segments.
    final taperSteps = math.min(5, math.max(2, samples.length ~/ 6));
    for (var i = 0; i < samples.length; i++) {
      final point = samples[i];
      final before = samples[i == 0 ? 0 : i - 1];
      final after = samples[i == samples.length - 1 ? i : i + 1];
      final tangent = after.position - before.position;
      final length = math.max(.001, tangent.distance);
      final normal = Offset(-tangent.dy / length, tangent.dx / length);

      var taper = math.min(
        1.0,
        (i + 1) / taperSteps,
      );
      taper = math.min(taper, math.min(1.0, (samples.length - i) / taperSteps));

      final radius = _radiusFor(samples, i, pen) * taper;
      leftEdge.add(point.position + normal * radius);
      rightEdge.add(point.position - normal * radius);

      final dt = (after.timestamp - before.timestamp).abs().clamp(.5, 250.0);
      final localSpeed = (after.position - before.position).distance / dt * 16;
      opacityTotal += fountainOpacityForSample(
        pressure: point.pressure,
        speed: localSpeed,
        pen: pen,
      );
      opacitySamples++;
    }

    // Fill the entire variable-width outline at once. The previous one-draw-
    // call-per-sample implementation both looked like a ballpoint pen and
    // spent more raster work on overlapping round caps.
    final ribbon = Path()..moveTo(leftEdge.first.dx, leftEdge.first.dy);
    for (final point in leftEdge.skip(1)) {
      ribbon.lineTo(point.dx, point.dy);
    }
    for (final point in rightEdge.reversed) {
      ribbon.lineTo(point.dx, point.dy);
    }
    ribbon.close();

    final alpha = (opacityTotal / math.max(1, opacitySamples)).clamp(.05, 1.0).toDouble();
    canvas.drawPath(
      ribbon,
      Paint()
        ..color = pen.color.withValues(alpha: alpha)
        ..style = PaintingStyle.fill
        ..isAntiAlias = true
        ..strokeJoin = StrokeJoin.round,
    );
  }

  static List<StrokePoint> _smoothFountainSamples(List<StrokePoint> points) {
    if (points.length < 2) return List<StrokePoint>.of(points);
    final result = <StrokePoint>[];

    double catmull(double p0, double p1, double p2, double p3, double t) {
      final t2 = t * t;
      final t3 = t2 * t;
      return .5 *
          ((2 * p1) +
              (-p0 + p2) * t +
              (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 +
              (-p0 + 3 * p1 - 3 * p2 + p3) * t3);
    }

    double lerp(double a, double b, double t) => a + (b - a) * t;
    for (var i = 0; i < points.length - 1; i++) {
      final p0 = points[i == 0 ? i : i - 1];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = points[i + 2 < points.length ? i + 2 : i + 1];
      for (var step = 0; step < 2; step++) {
        final t = step / 2;
        result.add(StrokePoint(
          position: Offset(
            catmull(p0.position.dx, p1.position.dx, p2.position.dx, p3.position.dx, t),
            catmull(p0.position.dy, p1.position.dy, p2.position.dy, p3.position.dy, t),
          ),
          pressure: lerp(p1.pressure, p2.pressure, t),
          timestamp: lerp(p1.timestamp, p2.timestamp, t),
          tilt: lerp(p1.tilt, p2.tilt, t),
          orientation: lerp(p1.orientation, p2.orientation, t),
        ));
      }
    }
    result.add(points.last);
    return result;
  }

  static double _radiusFor(
    List<StrokePoint> points,
    int index,
    PenConfig pen,
  ) {
    final point = points[index];
    final pressure = curvePressure(
      point.pressure.clamp(0, 1).toDouble(),
      pen,
    );
    var width = pen.size.clamp(.5, 60).toDouble();

    if (pen.type == PenType.fountain && points.length > 1) {
      // Use the nearest segment even for the first sample so both ends of the
      // ribbon use the same pressure/velocity/nib model.
      final segmentIndex = index == 0 ? 0 : index - 1;
      final a = points[segmentIndex];
      final b = points[segmentIndex + 1];
      final dt = (b.timestamp - a.timestamp).abs().clamp(.5, 250.0);
      final velocity = (b.position - a.position).distance / dt;
      width = fountainWidth(
        baseWidth: width,
        velocity: velocity * 16 * (.55 + pen.velocitySensitivity.clamp(0, 1) * 1.45),
        pressure: (.15 + pressure * (.65 + pen.pressureSensitivity.clamp(0, 1) * .20))
            .clamp(0.0, 1.0)
            .toDouble(),
      );
      final tangentAngle = math.atan2(
        b.position.dy - a.position.dy,
        b.position.dx - a.position.dx,
      );
      final reportedOrientation = point.orientation;
      // Devices without orientation report zero. Use a consistent slanted nib
      // as a fallback, while respecting actual orientation when available.
      final nibAngle = reportedOrientation.abs() < .02 && point.tilt.abs() < .02
          ? -math.pi / 4
          : reportedOrientation;
      final nibAcrossStroke = math.sin(tangentAngle - nibAngle).abs();
      width *= .18 + nibAcrossStroke * 1.12;
    } else if (index > 0) {
      final previous = points[index - 1];
      final dt = (point.timestamp - previous.timestamp).abs().clamp(.5, 250.0);
      final velocity = (point.position - previous.position).distance / dt;
      final velocityFactor = 1 -
          (velocity / 3.2).clamp(0, 1).toDouble() *
          pen.velocitySensitivity *
          .22;
      width *= velocityFactor;
      width *= .82 + pressure * (.18 + pen.pressureSensitivity * .34);
    } else {
      width *= .82 + pressure * (.18 + pen.pressureSensitivity * .34);
    }

    final multiplier = switch (pen.type) {
      PenType.pencil => .82,
      PenType.marker => 1.45,
      PenType.brush => 1.16,
      PenType.highlighter => 2.05,
      _ => 1.0,
    };
    width *= multiplier;

    if (pen.type == PenType.pencil || pen.type == PenType.brush) {
      final tilt = point.tilt.clamp(0, math.pi / 2).toDouble();
      width *= 1 + (tilt / (math.pi / 2)) * .14;
    }

    return (width * .5).clamp(.25, 60).toDouble();
  }
}