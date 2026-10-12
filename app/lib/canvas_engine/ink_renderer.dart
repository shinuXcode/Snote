import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'algorithms/stroke_geometry.dart';
import 'algorithms/velocity_calculator.dart';
import 'models/pen_config.dart';
import 'models/stroke.dart';

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

    if (index > 0) {
      final previous = points[index - 1];
      final dt = (point.timestamp - previous.timestamp).clamp(.5, 250.0);
      final velocity =
          (point.position - previous.position).distance / dt;
      if (pen.type == PenType.fountain) {
        width = fountainWidth(
          baseWidth: width,
          // Timestamps are milliseconds; convert to a 16 ms frame so ordinary
          // stylus movement has a visible effect on the ink width.
          velocity: velocity * 16 * (.55 + pen.velocitySensitivity * 1.45),
          pressure: .20 + pressure * (.85 + pen.pressureSensitivity * .8),
        );
        final tangentAngle = math.atan2(
          point.position.dy - previous.position.dy,
          point.position.dx - previous.position.dx,
        );
        final reportedOrientation = point.orientation;
        // Some digitizers report zero when orientation is unavailable. A
        // slanted default nib gives those devices recognizable calligraphic ink.
        final nibAngle = reportedOrientation.abs() < .02 && point.tilt.abs() < .02
            ? -math.pi / 4
            : reportedOrientation;
        final nibAcrossStroke = math.sin(tangentAngle - nibAngle).abs();
        width *= .14 + nibAcrossStroke * 1.75;
      } else {
        final velocityFactor = 1 -
            (velocity / 3.2).clamp(0, 1).toDouble() *
            pen.velocitySensitivity *
            .22;
        width *= velocityFactor;
        width *= .82 + pressure * (.18 + pen.pressureSensitivity * .34);
      }
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