import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../algorithms/velocity_calculator.dart';
import '../models/pen_config.dart';
import '../models/stroke.dart';

class SnoteCanvasPainter extends CustomPainter {
  final List<Stroke> strokes;
  final Stroke? activeStroke;
  final List<StrokePoint> activePoints;
  final PenConfig? activePen;
  final CanvasTool? activeTool;
  final bool activeFill;
  final int activeCustomSides;
  final String? activeStickerText;
  final Set<String> selectedIds;
  final List<Offset> lassoPath;
  final Path? activePath;
  final Offset? eraserPoint;
  final double eraserRadius;
  final bool showEraserMark;
  final bool drawStrokes;
  final bool drawActive;

  SnoteCanvasPainter({
    required this.strokes,
    required this.activeStroke,
    required this.activePoints,
    required this.activePen,
    required this.activeTool,
    required this.activeFill,
    required this.activeCustomSides,
    required this.activeStickerText,
    required this.selectedIds,
    required this.lassoPath,
    this.activePath,
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
      ..strokeWidth = (activePen!.type == PenType.highlighter
              ? activePen!.size * 2.05
              : activePen!.size)
          .clamp(.5, 60)
          .toDouble()
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true
      ..blendMode = activePen!.type == PenType.highlighter
          ? BlendMode.multiply
          : BlendMode.srcOver;
    canvas.drawPath(activePath!, paint);
    if (activePoints.isNotEmpty) {
      final last = activePoints.last.position;
      canvas.drawCircle(
        last,
        math.max(.6, paint.strokeWidth / 2),
        Paint()..color = paint.color,
      );
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

    if (points.length == 1) {
      canvas.drawCircle(points.first.position, math.max(1, stroke.pen.size / 2), Paint()..color = color);
      return;
    }

    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1];
      final b = points[i];
      var width = stroke.pen.size.clamp(.5, 60).toDouble();
      if (stroke.pen.type == PenType.fountain) {
        final dt = (b.timestamp - a.timestamp).clamp(.5, 250.0);
        final velocity = (b.position - a.position).distance / dt;
        width = fountainWidth(
          baseWidth: width,
          velocity: velocity * (.55 + stroke.pen.velocitySensitivity * 1.45),
          pressure: .45 + b.pressure * (.55 + stroke.pen.pressureSensitivity * .45),
        );
      } else if (stroke.pen.type == PenType.pencil) {
        width *= .78 + b.pressure.clamp(0, 1) * (.22 + stroke.pen.pressureSensitivity * .32);
      } else {
        width *= .82 + b.pressure.clamp(0, 1) * (.12 + stroke.pen.pressureSensitivity * .22);
      }

      paint.strokeWidth = stroke.pen.type == PenType.highlighter ? width * 2.05 : width;
      paint.blendMode = stroke.pen.type == PenType.highlighter ? BlendMode.multiply : BlendMode.srcOver;

      canvas.drawLine(a.position, b.position, paint);
    }
  }

  void _drawShape(Canvas canvas, Stroke stroke, Paint paint) {
    if (stroke.points.length < 2) return;
    final a = stroke.points.first.position;
    final b = stroke.points.last.position;
    final rect = Rect.fromPoints(a, b);
    final shapePaint = Paint()
      ..color = paint.color
      ..style = paint.style
      ..strokeWidth = paint.strokeWidth
      ..strokeCap = paint.strokeCap
      ..strokeJoin = paint.strokeJoin
      ..isAntiAlias = true;

    if (stroke.fill) {
      final fill = Paint()
        ..color = (stroke.fillColor ?? stroke.pen.color).withValues(alpha: stroke.fillOpacity.clamp(0, 1))
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

  void _drawDashedShape(Canvas canvas, Stroke stroke, Paint paint, Rect rect) {
    final path = Path();
    final a = stroke.points.first.position;
    final b = stroke.points.last.position;
    switch (stroke.shape) {
      case 'line':
      case 'arrow':
        path.moveTo(a.dx, a.dy);
        path.lineTo(b.dx, b.dy);
        break;
      case 'rectangle':
        path.addRect(rect);
        break;
      case 'roundedRectangle':
        path.addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(12)));
        break;
      case 'ellipse':
      case 'circle':
        final size = math.min(rect.width.abs(), rect.height.abs());
        final square = Rect.fromCenter(center: rect.center, width: size, height: size);
        path.addOval(stroke.shape == 'circle' ? square : rect);
        break;
      default:
        _drawShapePath(canvas, stroke, paint, rect);
        return;
    }
    for (final metric in path.computeMetrics()) {
      for (double d = 0; d < metric.length; d += 14) {
        final end = math.min(d + 8, metric.length);
        canvas.drawPath(metric.extractPath(d, end), paint);
      }
    }
  }

  void _drawShapePath(Canvas canvas, Stroke stroke, Paint paint, Rect rect) {
    final a = stroke.points.first.position;
    final b = stroke.points.last.position;
    final center = rect.center;
    switch (stroke.shape) {
      case 'line':
        canvas.drawLine(a, b, paint);
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
      case 'rectangle':
        canvas.drawRect(rect, paint);
      case 'roundedRectangle':
        canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(12)), paint);
      case 'ellipse':
      case 'circle':
        final size = math.min(rect.width.abs(), rect.height.abs());
        final square = Rect.fromCenter(center: center, width: size, height: size);
        canvas.drawOval(stroke.shape == 'circle' ? square : rect, paint);
      case 'triangle':
        canvas.drawPath(_regularPolygon(center, rect.width.abs().clamp(1, double.infinity).toDouble(), 3, -math.pi / 2), paint);
      case 'diamond':
        final path = Path()
          ..moveTo(center.dx, rect.top)
          ..lineTo(rect.right, center.dy)
          ..lineTo(center.dx, rect.bottom)
          ..lineTo(rect.left, center.dy)
          ..close();
        canvas.drawPath(path, paint);
      case 'hexagon':
        canvas.drawPath(_regularPolygon(center, math.min(rect.width.abs(), rect.height.abs()) / 2, 6, math.pi / 6), paint);
      case 'star':
        canvas.drawPath(_star(center, math.min(rect.width.abs(), rect.height.abs()) / 2, 5), paint);
      case 'customPolygon':
        canvas.drawPath(_regularPolygon(center, math.min(rect.width.abs(), rect.height.abs()) / 2, stroke.customSides, -math.pi / 2), paint);
    }
  }

  Path _regularPolygon(Offset center, double radius, int sides, double rotation) {
    final path = Path();
    for (var i = 0; i < sides; i++) {
      final angle = rotation + (math.pi * 2 * i / sides);
      final point = Offset(center.dx + math.cos(angle) * radius, center.dy + math.sin(angle) * radius);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    return path;
  }

  Path _star(Offset center, double radius, int points) {
    final path = Path();
    final inner = radius * .44;
    for (var i = 0; i < points * 2; i++) {
      final r = i.isEven ? radius : inner;
      final angle = -math.pi / 2 + math.pi * i / points;
      final point = Offset(center.dx + math.cos(angle) * r, center.dy + math.sin(angle) * r);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    return path;
  }

  void _drawSticker(Canvas canvas, Offset position, String text) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: const TextStyle(fontSize: 42)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, position - Offset(tp.width / 2, tp.height / 2));
  }

  Rect _bounds(List<StrokePoint> points) {
    var left = points.first.position.dx;
    var right = left;
    var top = points.first.position.dy;
    var bottom = top;
    for (final p in points.skip(1)) {
      left = left < p.position.dx ? left : p.position.dx;
      right = right > p.position.dx ? right : p.position.dx;
      top = top < p.position.dy ? top : p.position.dy;
      bottom = bottom > p.position.dy ? bottom : p.position.dy;
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  @override
  bool shouldRepaint(covariant SnoteCanvasPainter oldDelegate) {
    return !identical(oldDelegate.strokes, strokes) ||
        !identical(oldDelegate.activePoints, activePoints) ||
        oldDelegate.activeStroke != activeStroke ||
        oldDelegate.activePen != activePen ||
        oldDelegate.activeTool != activeTool ||
        oldDelegate.activeFill != activeFill ||
        oldDelegate.activeCustomSides != activeCustomSides ||
        oldDelegate.activeStickerText != activeStickerText ||
        !identical(oldDelegate.selectedIds, selectedIds) ||
        !identical(oldDelegate.lassoPath, lassoPath) ||
        oldDelegate.drawStrokes != drawStrokes ||
        oldDelegate.drawActive != drawActive;
  }
}