import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../algorithms/velocity_calculator.dart';
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
        width = fountainWidth(baseWidth: width, velocity: velocity, pressure: b.pressure);
      } else if (stroke.pen.type == PenType.pencil) {
        width *= .78 + b.pressure.clamp(0, 1) * .32;
      } else {
        width *= .82 + b.pressure.clamp(0, 1) * .22;
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