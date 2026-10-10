import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../algorithms/velocity_calculator.dart';
import '../algorithms/stroke_geometry.dart';
import '../models/pen_config.dart';
import '../models/stroke.dart';

class SnoteCanvasPainter extends CustomPainter {
  final List<Stroke> strokes;
  final Stroke? activeStroke;
  final List<StrokePoint> activePoints;
  final Path? activePath;
  final PenConfig? activePen;
  final CanvasTool? activeTool;
  final bool activeFill;
  final int activeCustomSides;
  final String? activeStickerText;
  final Set<String> selectedIds;
  final List<Offset> lassoPath;
  final Offset? eraserPoint;
  final double eraserRadius;
  final bool showEraserMark;
  final bool drawStrokes;
  final bool drawActive;

  SnoteCanvasPainter({
    required this.strokes,
    required this.activeStroke,
    required this.activePoints,
    this.activePath,
    required this.activePen,
    required this.activeTool,
    required this.activeFill,
    required this.activeCustomSides,
    required this.activeStickerText,
    required this.selectedIds,
    required this.lassoPath,
    this.eraserPoint,
    this.eraserRadius = 0,
    this.showEraserMark = false,
    this.drawStrokes = true,
    this.drawActive = true,
    Listenable? repaint,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    if (drawStrokes) {
      for (final stroke in strokes) {
        _drawStroke(canvas, stroke, selectedIds.contains(stroke.id));
      }
    }
    if (drawActive && activeStroke != null) {
      _drawStroke(canvas, activeStroke!, false);
    } else if (drawActive && activePath != null && activePen != null && activeTool != null) {
      _drawLivePath(canvas);
    } else if (drawActive && activePoints.isNotEmpty && activePen != null && activeTool != null) {
      _drawActive(canvas);
    }

    if (showEraserMark && eraserPoint != null && eraserRadius > 0) {
      final eraserPaint = Paint()
        ..color = const Color(0xff4f6df6).withValues(alpha: .55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4;
      canvas.drawCircle(eraserPoint!, eraserRadius, eraserPaint);
    }

    if (drawActive && lassoPath.length > 1) {
      final p = Paint()
        ..color = const Color(0xff4f6df6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round;
      for (var i = 1; i < lassoPath.length; i++) {
        canvas.drawLine(lassoPath[i - 1], lassoPath[i], p);
      }
    }
  }

  void _drawLivePath(Canvas canvas) {
    if (activePath == null || activePen == null || activeTool == null) return;
    final opacity = activePen!.type == PenType.highlighter
        ? activePen!.opacity.clamp(.08, .55)
        : activePen!.opacity.clamp(.05, 1);
    final paint = Paint()
      ..color = activePen!.color.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = (activePen!.type == PenType.highlighter ? activePen!.size * 2.05 : activePen!.size).clamp(.5, 60).toDouble()
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true
      ..blendMode = activePen!.type == PenType.highlighter ? BlendMode.multiply : BlendMode.srcOver;
    canvas.drawPath(activePath!, paint);
    if (activePoints.isNotEmpty) {
      final last = activePoints.last.position;
      canvas.drawCircle(last, math.max(.6, paint.strokeWidth / 2), Paint()..color = paint.color);
    }
  }

  void _drawActive(Canvas canvas) {
    final stroke = Stroke(
      id: 'active',
      points: activePoints,
      pen: activePen!,
      shape: activeTool!.isShape ? activeTool!.name : null,
      fill: activeFill,
      customSides: activeCustomSides,
      stickerText: activeStickerText,
    );
    _drawStroke(canvas, stroke, false);
  }

  void _drawStroke(Canvas canvas, Stroke stroke, bool selected) {
    if (stroke.stickerText != null) {
      _drawSticker(canvas, stroke.points.first.position, stroke.stickerText!);
      return;
    }

    final points = stroke.points;
    if (points.isEmpty) return;
    final color = stroke.pen.color.withValues(alpha: stroke.pen.opacity.clamp(0, 1));

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke.pen.size
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    if (selected) {
      final bounds = _bounds(points);
      canvas.drawRRect(
        RRect.fromRectAndRadius(bounds.inflate(9), const Radius.circular(9)),
        Paint()..color = const Color(0xff4f6df6).withValues(alpha: .16),
      );
    }

    if (stroke.shape != null) {
      _drawShape(canvas, stroke, paint);
      return;
    }

    final inkPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true
      ..blendMode = stroke.pen.type == PenType.highlighter
          ? BlendMode.multiply
          : BlendMode.srcOver;

    // Use one smoothed ribbon path instead of isolated straight line segments.
    // Pressure, velocity, and tilt remain attached to their original samples.
    final ribbon = StrokeGeometry.buildRibbonPath(points, (point, index) {
      final sensitivity =
          stroke.pen.pressureSensitivity.clamp(0, 1).toDouble();
      final pressure = curvePressure(point.pressure, stroke.pen);
      var width = stroke.pen.size *
          ((1 - sensitivity) + sensitivity * (.64 + .72 * pressure));

      if (stroke.pen.type == PenType.fountain && index > 0) {
        final previous = points[index - 1];
        final dt = (point.timestamp - previous.timestamp).clamp(.5, 250.0);
        final velocity = (point.position - previous.position).distance / dt;
        final fountain = fountainWidth(
          baseWidth: stroke.pen.size,
          velocity: velocity,
          pressure: pressure,
        );
        final velocitySensitivity =
            stroke.pen.velocitySensitivity.clamp(0, 1).toDouble();
        width += (fountain - width) * velocitySensitivity;
      } else if (stroke.pen.type == PenType.pencil) {
        width *= .86;
      }

      final tilt = point.tilt.abs().clamp(0, math.pi / 2).toDouble();
      width *= 1 + (tilt / (math.pi / 2)) * .16;
      if (stroke.pen.type == PenType.highlighter) width *= 2.05;
      return width.clamp(.5, 120).toDouble() / 2;
    });

    canvas.drawPath(ribbon, inkPaint);
  }

  void _drawShape(Canvas canvas, Stroke stroke, Paint paint) {
    if (stroke.points.length < 2) return;
    final a = stroke.points.first.position;
    final b = stroke.points.last.position;
    // Auto-recognized circles/rectangles retain their original samples, so
    // use the complete stroke bounds for vector reconstruction. Straight
    // lines and arrows still use their actual endpoints.
    final rect = stroke.shape == 'line' || stroke.shape == 'arrow'
        ? Rect.fromPoints(a, b)
        : _bounds(stroke.points);
    final shapePaint = Paint()
      ..color = paint.color
      ..style = paint.style
      ..strokeWidth = paint.strokeWidth
      ..strokeCap = paint.strokeCap
      ..strokeJoin = paint.strokeJoin
      ..isAntiAlias = true;

    if (stroke.fill) {
      final fill = Paint()
        ..color = stroke.pen.color.withValues(alpha: stroke.fillOpacity.clamp(0, 1))
        ..style = PaintingStyle.fill
        ..isAntiAlias = true;
      _drawShapePath(canvas, stroke, fill, rect);
    }
    if (stroke.dashed) {
      _drawDashedShape(canvas, stroke, shapePaint, rect);
    } else {
      _drawShapePath(canvas, stroke, shapePaint, rect);
    }
  }

  void _drawDashedShape(
    Canvas canvas,
    Stroke stroke,
    Paint paint,
    Rect rect,
  ) {
    final path = Path();
    final a = stroke.points.first.position;
    final b = stroke.points.last.position;

    switch (stroke.shape) {
      case 'line':
      case 'arrow':
        path
          ..moveTo(a.dx, a.dy)
          ..lineTo(b.dx, b.dy);
        break;
      case 'rectangle':
        path.addRect(rect);
        break;
      case 'roundedRectangle':
        path.addRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(12)),
        );
        break;
      case 'ellipse':
      case 'circle':
        final size = math.min(rect.width.abs(), rect.height.abs());
        final square = Rect.fromCenter(
          center: rect.center,
          width: size,
          height: size,
        );
        path.addOval(stroke.shape == 'circle' ? square : rect);
        break;
      default:
        _drawShapePath(canvas, stroke, paint, rect);
        return;
    }

    for (final metric in path.computeMetrics()) {
      for (double distance = 0; distance < metric.length; distance += 14) {
        final end = math.min(distance + 8, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
      }
    }
  }

  void _drawShapePath(
    Canvas canvas,
    Stroke stroke,
    Paint paint,
    Rect rect,
  ) {
    final a = stroke.points.first.position;
    final b = stroke.points.last.position;
    final center = rect.center;

    switch (stroke.shape) {
      case 'line':
        canvas.drawLine(a, b, paint);
        break;
      case 'arrow':
        canvas.drawLine(a, b, paint);
        final direction = b - a;
        if (direction.distance > 1) {
          final unit = direction / direction.distance;
          final normal = Offset(-unit.dy, unit.dx);
          final tip = b - unit * 16;
          canvas.drawLine(b, tip + normal * 7, paint);
          canvas.drawLine(b, tip - normal * 7, paint);
        }
        break;
      case 'rectangle':
        canvas.drawRect(rect, paint);
        break;
      case 'roundedRectangle':
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(12)),
          paint,
        );
        break;
      case 'ellipse':
      case 'circle':
        final size = math.min(rect.width.abs(), rect.height.abs());
        final square = Rect.fromCenter(
          center: center,
          width: size,
          height: size,
        );
        canvas.drawOval(stroke.shape == 'circle' ? square : rect, paint);
        break;
      case 'triangle':
        canvas.drawPath(
          _regularPolygon(
            center,
            rect.width.abs().clamp(1, double.infinity).toDouble(),
            3,
            -math.pi / 2,
          ),
          paint,
        );
        break;
      case 'diamond':
        final path = Path()
          ..moveTo(center.dx, rect.top)
          ..lineTo(rect.right, center.dy)
          ..lineTo(center.dx, rect.bottom)
          ..lineTo(rect.left, center.dy)
          ..close();
        canvas.drawPath(path, paint);
        break;
      case 'hexagon':
        canvas.drawPath(
          _regularPolygon(
            center,
            math.min(rect.width.abs(), rect.height.abs()) / 2,
            6,
            math.pi / 6,
          ),
          paint,
        );
        break;
      case 'star':
        canvas.drawPath(
          _star(
            center,
            math.min(rect.width.abs(), rect.height.abs()) / 2,
            5,
          ),
          paint,
        );
        break;
      case 'customPolygon':
        canvas.drawPath(
          _regularPolygon(
            center,
            math.min(rect.width.abs(), rect.height.abs()) / 2,
            stroke.customSides,
            -math.pi / 2,
          ),
          paint,
        );
        break;
    }
  }

  Path _regularPolygon(
    Offset center,
    double radius,
    int sides,
    double rotation,
  ) {
    final path = Path();
    for (var i = 0; i < sides; i++) {
      final angle = rotation + math.pi * 2 * i / sides;
      final point = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    return path;
  }

  Path _star(
    Offset center,
    double radius,
    int points,
  ) {
    final path = Path();
    final inner = radius * .44;
    for (var i = 0; i < points * 2; i++) {
      final r = i.isEven ? radius : inner;
      final angle = -math.pi / 2 + math.pi * i / points;
      final point = Offset(
        center.dx + math.cos(angle) * r,
        center.dy + math.sin(angle) * r,
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    return path;
  }

  void _drawSticker(
    Canvas canvas,
    Offset position,
    String text,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(fontSize: 42),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      position - Offset(painter.width / 2, painter.height / 2),
    );
  }

  Rect _bounds(List<StrokePoint> points) {
    var left = points.first.position.dx;
    var right = left;
    var top = points.first.position.dy;
    var bottom = top;

    for (final point in points.skip(1)) {
      left = math.min(left, point.position.dx);
      right = math.max(right, point.position.dx);
      top = math.min(top, point.position.dy);
      bottom = math.max(bottom, point.position.dy);
    }

    return Rect.fromLTRB(left, top, right, bottom);
  }

  @override
  bool shouldRepaint(covariant SnoteCanvasPainter oldDelegate) {
    return !identical(oldDelegate.strokes, strokes) ||
        !identical(oldDelegate.activePoints, activePoints) ||
        oldDelegate.activeStroke != activeStroke ||
        oldDelegate.activePath != activePath ||
        oldDelegate.activePen != activePen ||
        oldDelegate.activeTool != activeTool ||
        oldDelegate.activeFill != activeFill ||
        oldDelegate.activeCustomSides != activeCustomSides ||
        oldDelegate.activeStickerText != activeStickerText ||
        !identical(oldDelegate.selectedIds, selectedIds) ||
        !identical(oldDelegate.lassoPath, lassoPath) ||
        oldDelegate.eraserPoint != eraserPoint ||
        oldDelegate.eraserRadius != eraserRadius ||
        oldDelegate.showEraserMark != showEraserMark ||
        oldDelegate.drawStrokes != drawStrokes ||
        oldDelegate.drawActive != drawActive;
  }
}
