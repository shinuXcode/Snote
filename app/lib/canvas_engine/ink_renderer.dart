import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'algorithms/stroke_geometry.dart';
import 'algorithms/velocity_calculator.dart';
import 'models/pen_config.dart';
import 'models/stroke.dart';

/// Dedicated ink renderer. It is intentionally independent from widget build
/// and is called from CustomPainter's paint phase.
class InkRenderer {
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
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true
      ..blendMode = pen.type == PenType.highlighter ||
              pen.type == PenType.marker
          ? BlendMode.multiply
          : BlendMode.srcOver;

    final widthMultiplier = switch (pen.type) {
      PenType.pencil => .82,
      PenType.marker => 1.45,
      PenType.brush => 1.12,
      PenType.highlighter => 2.05,
      _ => 1.0,
    };

    double widthFor(StrokePoint a, StrokePoint b) {
      final pressure = curvePressure(
        b.pressure.clamp(0, 1).toDouble(),
        pen,
      );
      var width = pen.size.clamp(.5, 60).toDouble();

      if (pen.type == PenType.fountain) {
        final dt = (b.timestamp - a.timestamp).clamp(.5, 250.0);
        final velocity = (b.position - a.position).distance / dt;
        width = fountainWidth(
          baseWidth: width,
          velocity: velocity * (.55 + pen.velocitySensitivity * 1.45),
          pressure: .45 + pressure * (.55 + pen.pressureSensitivity * .45),
        );
      } else {
        width *= .82 + pressure * (.18 + pen.pressureSensitivity * .34);
      }

      // Tilt changes brush/pencil footprint only; it never moves the centerline.
      if (pen.type == PenType.pencil || pen.type == PenType.brush) {
        width *= 1.0 + (b.tilt.clamp(0, math.pi / 2) / (math.pi / 2)) * .12;
      }

      return (width * widthMultiplier).clamp(.5, 120).toDouble();
    }

    StrokeGeometry.drawVariableWidth(
      canvas,
      points,
      paint,
      widthFor,
    );

    if (points.length == 1) {
      canvas.drawCircle(
        points.first.position,
        math.max(.6, paint.strokeWidth * .5),
        Paint()..color = paint.color,
      );
    }
  }
}
