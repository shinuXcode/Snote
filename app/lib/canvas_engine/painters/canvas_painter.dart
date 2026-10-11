import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../ink_renderer.dart';
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

    if (drawActive &&
        activePoints.isNotEmpty &&
        activePen != null &&
        activeTool != null) {
      if (activeTool!.isShape) {
        _drawShape(
          canvas,
          Stroke(
            id: 'active',
            points: activePoints,
            pen: activePen!,
            shape: activeTool!.name,
            fill: activeFill,
            customSides: activeCustomSides,
            stickerText: activeStickerText,
          ),
          false,
        );
      } else if (activeStickerText != null) {
        _drawSticker(
          canvas,
          activePoints.first.position,
          activeStickerText!,
        );
      } else {
        InkRenderer.drawInk(canvas, activePoints, activePen!);
      }
    }

    if (showEraserMark &&
        eraserPoint != null &&
        eraserRadius > 0) {
      final eraserPaint = Paint()
        ..color = const Color(0xff4f6df6).withValues(alpha: .55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4;
      canvas.drawCircle(
        eraserPoint!,
        eraserRadius,
        eraserPaint,
      );
    }

    if (drawActive && lassoPath.length > 1) {
      final p = Paint()
        ..color = const Color(0xff4f6df6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round;
      for (var i = 1; i < lassoPath.length; i++) {
        canvas.drawLine(
          lassoPath[i - 1],
          lassoPath[i],
          p,
        );
      }
    }
  }

  void _drawStroke(
    Canvas canvas,
    Stroke stroke,
    bool selected,
  ) {
    if (stroke.stickerText != null) {
      _drawSticker(
        canvas,
        stroke.points.first.position,
        stroke.stickerText!,
      );
      return;
    }

    final points = stroke.points;
    if (points.isEmpty) return;

    if (selected) {
      final bounds = _bounds(points);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          bounds.inflate(9),
          const Radius.circular(9),
        ),
        Paint()
          ..color =
              const Color(0xff4f6df6).withValues(alpha: .16),
      );
    }

    if (stroke.shape != null) {
      _drawShape(canvas, stroke, false);
      return;
    }

    InkRenderer.drawInk(canvas, points, stroke.pen);
  }

  void _drawShape(
    Canvas canvas,
    Stroke stroke,
    bool selected,
  ) {
    if (stroke.points.length < 2) return;
    final a = stroke.points.first.position;
    final b = stroke.points.last.position;
    final rect = Rect.fromPoints(a, b);

    final paint = Paint()
      ..color = stroke.pen.color.withValues(
        alpha: stroke.pen.opacity.clamp(0, 1).toDouble(),
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke.pen.size
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    if (selected) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          rect.inflate(9),
          const Radius.circular(9),
        ),
        Paint()
          ..color =
              const Color(0xff4f6df6).withValues(alpha: .16),
      );
    }

    if (stroke.fill) {
      final fill = Paint()
        ..color = (stroke.fillColor ?? stroke.pen.color)
            .withValues(
          alpha: stroke.fillOpacity.clamp(0, 1),
        )
        ..style = PaintingStyle.fill
        ..isAntiAlias = true;
      _drawShapePath(canvas, stroke, fill, rect);
    }

    if (stroke.dashed) {
      _drawDashedShape(canvas, stroke, paint, rect);
    } else {
      _drawShapePath(canvas, stroke, paint, rect);
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
          RRect.fromRectAndRadius(
            rect,
            const Radius.circular(12),
          ),
        );
        break;
      case 'ellipse':
      case 'circle':
        final size =
            math.min(rect.width.abs(), rect.height.abs());
        final square = Rect.fromCenter(
          center: rect.center,
          width: size,
          height: size,
        );
        path.addOval(
          stroke.shape == 'circle' ? square : rect,
        );
        break;
      default:
        _drawShapePath(canvas, stroke, paint, rect);
        return;
    }

    for (final metric in path.computeMetrics()) {
      for (double d = 0; d < metric.length; d += 14) {
        final end = math.min(d + 8, metric.length);
        canvas.drawPath(
          metric.extractPath(d, end),
          paint,
        );
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
          canvas.drawLine(
            b,
            tip + normal * 7,
            paint,
          );
          canvas.drawLine(
            b,
            tip - normal * 7,
            paint,
          );
        }
        break;
      case 'rectangle':
        canvas.drawRect(rect, paint);
        break;
      case 'roundedRectangle':
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            rect,
            const Radius.circular(12),
          ),
          paint,
        );
        break;
      case 'ellipse':
      case 'circle':
        final size =
            math.min(rect.width.abs(), rect.height.abs());
        final square = Rect.fromCenter(
          center: center,
          width: size,
          height: size,
        );
        canvas.drawOval(
          stroke.shape == 'circle' ? square : rect,
          paint,
        );
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
      case 'mathCoordinateAxes':
        _drawCoordinateAxes(canvas, rect, paint);
        break;
      case 'mathParabola':
        _drawParabola(canvas, rect, paint);
        break;
      case 'mathSineWave':
        _drawSineWave(canvas, rect, paint);
        break;
      case 'mathAngle':
        _drawAngle(canvas, rect, paint, rightAngle: false);
        break;
      case 'mathRightAngle':
        _drawAngle(canvas, rect, paint, rightAngle: true);
        break;
      case 'physicsVector':
        _drawArrow(canvas, rect, paint);
        break;
      case 'physicsResistor':
        _drawResistor(canvas, rect, paint);
        break;
      case 'physicsCapacitor':
        _drawCapacitor(canvas, rect, paint, battery: false);
        break;
      case 'physicsBattery':
        _drawCapacitor(canvas, rect, paint, battery: true);
        break;
      case 'physicsDiode':
        _drawDiode(canvas, rect, paint);
        break;
      case 'physicsConvexLens':
        _drawLens(canvas, rect, paint);
        break;
      case 'chemistryBenzene':
        _drawBenzene(canvas, rect, paint);
        break;
      case 'chemistryMolecule':
        _drawMolecule(canvas, rect, paint);
        break;
      case 'chemistryAtom':
        _drawAtom(canvas, rect, paint);
        break;
      case 'chemistryOrbital':
        _drawOrbital(canvas, rect, paint);
        break;
      case 'chemistryFlask':
        _drawFlask(canvas, rect, paint);
        break;
      case 'chemistryBeaker':
        _drawBeaker(canvas, rect, paint);
        break;
      case 'biologyCell':
        _drawCell(canvas, rect, paint);
        break;
      case 'biologyMitochondrion':
        _drawMitochondrion(canvas, rect, paint);
        break;
      case 'biologyDna':
        _drawDna(canvas, rect, paint);
        break;
      case 'biologyLeaf':
        _drawLeaf(canvas, rect, paint);
        break;
      case 'biologyNeuron':
        _drawNeuron(canvas, rect, paint);
        break;
    }
  }

  void _drawArrow(Canvas canvas, Rect rect, Paint paint) {
    final a = Offset(rect.left, rect.bottom);
    final b = Offset(rect.right, rect.top);
    canvas.drawLine(a, b, paint);
    final direction = b - a;
    if (direction.distance < 1) return;
    final unit = direction / direction.distance;
    final normal = Offset(-unit.dy, unit.dx);
    final tip = b - unit * math.min(16, direction.distance * .35);
    canvas.drawLine(b, tip + normal * 6, paint);
    canvas.drawLine(b, tip - normal * 6, paint);
  }

  void _drawCoordinateAxes(Canvas canvas, Rect r, Paint p) {
    final origin = Offset(r.left + r.width * .12, r.bottom - r.height * .12);
    final xEnd = Offset(r.right - r.width * .05, origin.dy);
    final yEnd = Offset(origin.dx, r.top + r.height * .05);
    canvas.drawLine(origin, xEnd, p);
    canvas.drawLine(origin, yEnd, p);
    final arrow = math.min(10.0, math.min(r.width, r.height) * .18);
    canvas.drawLine(xEnd, xEnd - Offset(arrow, arrow * .45), p);
    canvas.drawLine(xEnd, xEnd - Offset(arrow, -arrow * .45), p);
    canvas.drawLine(yEnd, yEnd + Offset(-arrow * .45, arrow), p);
    canvas.drawLine(yEnd, yEnd + Offset(arrow * .45, arrow), p);
  }

  void _drawParabola(Canvas canvas, Rect r, Paint p) {
    final path = Path();
    final count = 60;
    for (var i = 0; i <= count; i++) {
      final t = i / count;
      final x = r.left + t * r.width;
      final y = r.top + r.height * (.08 + .86 * 4 * (t - .5) * (t - .5));
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, p);
  }

  void _drawSineWave(Canvas canvas, Rect r, Paint p) {
    final path = Path();
    for (var i = 0; i <= 80; i++) {
      final t = i / 80;
      final x = r.left + t * r.width;
      final y = r.center.dy - math.sin(t * math.pi * 2) * r.height * .42;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, p);
  }

  void _drawAngle(Canvas canvas, Rect r, Paint p, {required bool rightAngle}) {
    final origin = Offset(r.left + r.width * .12, r.bottom - r.height * .12);
    final endA = Offset(r.right - r.width * .08, origin.dy);
    final endB = Offset(r.left + r.width * .12, r.top + r.height * .08);
    canvas.drawLine(origin, endA, p);
    canvas.drawLine(origin, endB, p);
    if (rightAngle) {
      final side = math.min(r.width, r.height) * .18;
      final path = Path()
        ..moveTo(origin.dx + side, origin.dy)
        ..lineTo(origin.dx + side, origin.dy - side)
        ..lineTo(origin.dx, origin.dy - side);
      canvas.drawPath(path, p);
    } else {
      final radius = math.min(r.width, r.height) * .22;
      canvas.drawArc(
        Rect.fromCircle(center: origin, radius: radius),
        -math.pi / 2,
        math.pi / 3,
        false,
        p,
      );
    }
  }

  void _drawResistor(Canvas canvas, Rect r, Paint p) {
    final y = r.center.dy;
    final lead = r.width * .16;
    final left = r.left + lead;
    final right = r.right - lead;
    final segments = 8;
    final path = Path()
      ..moveTo(r.left, y)
      ..lineTo(left, y);
    for (var i = 0; i <= segments; i++) {
      final x = left + (right - left) * i / segments;
      final offset = i == 0 || i == segments ? 0.0 : (i.isOdd ? -1.0 : 1.0) * r.height * .25;
      path.lineTo(x, y + offset);
    }
    path..lineTo(r.right, y);
    canvas.drawPath(path, p);
  }

  void _drawCapacitor(Canvas canvas, Rect r, Paint p, {required bool battery}) {
    final center = r.center.dx;
    final y1 = r.top + r.height * .2;
    final y2 = r.bottom - r.height * .2;
    final gap = battery ? r.width * .1 : r.width * .045;
    canvas.drawLine(Offset(r.left, r.center.dy), Offset(center - gap, r.center.dy), p);
    canvas.drawLine(Offset(center + gap, r.center.dy), Offset(r.right, r.center.dy), p);
    canvas.drawLine(Offset(center - gap, y1), Offset(center - gap, y2), p);
    canvas.drawLine(
      Offset(center + gap * (battery ? 1.8 : 1), battery ? r.center.dy - r.height * .17 : y1),
      Offset(center + gap * (battery ? 1.8 : 1), battery ? r.center.dy + r.height * .17 : y2),
      p,
    );
  }

  void _drawDiode(Canvas canvas, Rect r, Paint p) {
    final y = r.center.dy;
    final centerX = r.center.dx;
    final halfWidth = r.width * .16;
    final halfHeight = r.height * .28;
    canvas.drawLine(Offset(r.left, y), Offset(centerX - halfWidth, y), p);
    final triangle = Path()
      ..moveTo(centerX - halfWidth, y - halfHeight)
      ..lineTo(centerX + halfWidth, y)
      ..lineTo(centerX - halfWidth, y + halfHeight)
      ..close();
    canvas.drawPath(triangle, p);
    canvas.drawLine(Offset(centerX + halfWidth, y - halfHeight), Offset(centerX + halfWidth, y + halfHeight), p);
    canvas.drawLine(Offset(centerX + halfWidth, y), Offset(r.right, y), p);
  }

  void _drawLens(Canvas canvas, Rect r, Paint p) {
    final path = Path()
      ..moveTo(r.center.dx, r.top)
      ..cubicTo(r.left - r.width * .15, r.top + r.height * .25, r.left - r.width * .15, r.bottom - r.height * .25, r.center.dx, r.bottom)
      ..cubicTo(r.right + r.width * .15, r.bottom - r.height * .25, r.right + r.width * .15, r.top + r.height * .25, r.center.dx, r.top);
    canvas.drawPath(path, p);
  }

  void _drawBenzene(Canvas canvas, Rect r, Paint p) {
    final radius = math.min(r.width, r.height) * .44;
    canvas.drawPath(_regularPolygon(r.center, radius, 6, -math.pi / 6), p);
    canvas.drawCircle(r.center, radius * .52, p);
  }

  void _drawMolecule(Canvas canvas, Rect r, Paint p) {
    final nodes = <Offset>[
      Offset(r.left + r.width * .18, r.center.dy),
      Offset(r.left + r.width * .43, r.top + r.height * .2),
      Offset(r.left + r.width * .67, r.center.dy),
      Offset(r.left + r.width * .86, r.top + r.height * .25),
      Offset(r.left + r.width * .76, r.bottom - r.height * .2),
    ];
    for (var i = 1; i < nodes.length; i++) {
      canvas.drawLine(nodes[i - 1], nodes[i], p);
    }
    final radius = math.min(r.width, r.height) * .08;
    final atomPaint = Paint()
      ..color = p.color
      ..style = PaintingStyle.fill;
    for (final node in nodes) {
      canvas.drawCircle(node, radius, atomPaint);
    }
  }

  void _drawAtom(Canvas canvas, Rect r, Paint p) {
    canvas.drawOval(Rect.fromCenter(center: r.center, width: r.width * .9, height: r.height * .42), p);
    canvas.save();
    canvas.translate(r.center.dx, r.center.dy);
    canvas.rotate(math.pi / 3);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: r.width * .9, height: r.height * .42), p);
    canvas.restore();
    canvas.save();
    canvas.translate(r.center.dx, r.center.dy);
    canvas.rotate(-math.pi / 3);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: r.width * .9, height: r.height * .42), p);
    canvas.restore();
    final nucleus = Paint()..color = p.color..style = PaintingStyle.fill;
    canvas.drawCircle(r.center, math.min(r.width, r.height) * .07, nucleus);
  }

  void _drawOrbital(Canvas canvas, Rect r, Paint p) {
    final w = r.width * .35;
    final h = r.height * .20;
    for (final x in [-1.0, 1.0]) {
      canvas.drawOval(Rect.fromCenter(center: Offset(r.center.dx + x * r.width * .18, r.center.dy), width: w, height: h), p);
    }
    canvas.drawCircle(r.center, math.min(r.width, r.height) * .06, Paint()..color = p.color..style = PaintingStyle.fill);
  }

  void _drawFlask(Canvas canvas, Rect r, Paint p) {
    final path = Path()
      ..moveTo(r.center.dx - r.width * .09, r.top + r.height * .04)
      ..lineTo(r.center.dx + r.width * .09, r.top + r.height * .04)
      ..lineTo(r.center.dx + r.width * .09, r.top + r.height * .42)
      ..lineTo(r.right - r.width * .12, r.bottom - r.height * .14)
      ..quadraticBezierTo(r.center.dx, r.bottom + r.height * .05, r.left + r.width * .12, r.bottom - r.height * .14)
      ..lineTo(r.center.dx - r.width * .09, r.top + r.height * .42)
      ..close();
    canvas.drawPath(path, p);
    canvas.drawLine(Offset(r.center.dx - r.width * .1, r.top + r.height * .42), Offset(r.center.dx + r.width * .1, r.top + r.height * .42), p);
  }

  void _drawBeaker(Canvas canvas, Rect r, Paint p) {
    final path = Path()
      ..moveTo(r.left + r.width * .2, r.top + r.height * .05)
      ..lineTo(r.left + r.width * .78, r.top + r.height * .05)
      ..moveTo(r.left + r.width * .14, r.top + r.height * .16)
      ..lineTo(r.left + r.width * .23, r.bottom - r.height * .12)
      ..lineTo(r.left + r.width * .77, r.bottom - r.height * .12)
      ..lineTo(r.right - r.width * .14, r.top + r.height * .16);
    canvas.drawPath(path, p);
    canvas.drawLine(Offset(r.left + r.width * .24, r.center.dy), Offset(r.right - r.width * .24, r.center.dy), p);
  }

  void _drawCell(Canvas canvas, Rect r, Paint p) {
    canvas.drawOval(r.deflate(math.min(r.width, r.height) * .04), p);
    final nucleus = Rect.fromCenter(center: Offset(r.center.dx + r.width * .06, r.center.dy), width: r.width * .24, height: r.height * .3);
    canvas.drawOval(nucleus, p);
    for (var i = 0; i < 5; i++) {
      final angle = i * math.pi * 2 / 5;
      canvas.drawCircle(
        Offset(r.center.dx + math.cos(angle) * r.width * .28, r.center.dy + math.sin(angle) * r.height * .27),
        math.min(r.width, r.height) * .035,
        p,
      );
    }
  }

  void _drawMitochondrion(Canvas canvas, Rect r, Paint p) {
    canvas.drawOval(r.deflate(math.min(r.width, r.height) * .1), p);
    final path = Path();
    for (var i = 0; i <= 36; i++) {
      final t = i / 36;
      final x = r.left + r.width * (.12 + .76 * t);
      final y = r.center.dy + math.sin(t * math.pi * 8) * r.height * .2;
      if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
    }
    canvas.drawPath(path, p);
  }

  void _drawDna(Canvas canvas, Rect r, Paint p) {
    final left = Path();
    final right = Path();
    const count = 56;
    for (var i = 0; i <= count; i++) {
      final t = i / count;
      final y = r.top + t * r.height;
      final wave = math.sin(t * math.pi * 4);
      final x1 = r.center.dx - wave * r.width * .34;
      final x2 = r.center.dx + wave * r.width * .34;
      if (i == 0) {
        left.moveTo(x1, y);
        right.moveTo(x2, y);
      } else {
        left.lineTo(x1, y);
        right.lineTo(x2, y);
      }
    }
    canvas.drawPath(left, p);
    canvas.drawPath(right, p);
    for (var i = 0; i <= 14; i++) {
      final t = i / 14;
      final y = r.top + t * r.height;
      final wave = math.sin(t * math.pi * 4);
      canvas.drawLine(
        Offset(r.center.dx - wave * r.width * .32, y),
        Offset(r.center.dx + wave * r.width * .32, y),
        p..strokeWidth = math.max(.6, p.strokeWidth * .55),
      );
    }
  }

  void _drawLeaf(Canvas canvas, Rect r, Paint p) {
    final path = Path()
      ..moveTo(r.left + r.width * .08, r.bottom - r.height * .08)
      ..cubicTo(r.left + r.width * .1, r.top + r.height * .18, r.right - r.width * .1, r.top + r.height * .05, r.right - r.width * .08, r.top + r.height * .05)
      ..cubicTo(r.right - r.width * .18, r.bottom - r.height * .06, r.left + r.width * .25, r.bottom - r.height * .02, r.left + r.width * .08, r.bottom - r.height * .08)
      ..close();
    canvas.drawPath(path, p);
    canvas.drawLine(Offset(r.left + r.width * .08, r.bottom - r.height * .08), Offset(r.right - r.width * .09, r.top + r.height * .08), p);
    for (var i = 1; i <= 4; i++) {
      final t = i / 5;
      final x = r.left + r.width * t;
      final y = r.bottom - r.height * t;
      canvas.drawLine(Offset(x, y), Offset(x + r.width * .12, y - r.height * .13), p);
    }
  }

  void _drawNeuron(Canvas canvas, Rect r, Paint p) {
    final soma = Offset(r.left + r.width * .35, r.center.dy);
    canvas.drawCircle(soma, math.min(r.width, r.height) * .12, p);
    canvas.drawCircle(soma, math.min(r.width, r.height) * .035, Paint()..color = p.color..style = PaintingStyle.fill);
    final axonStart = Offset(soma.dx + r.width * .12, soma.dy);
    final axonEnd = Offset(r.right - r.width * .04, soma.dy);
    canvas.drawLine(axonStart, axonEnd, p);
    for (var i = 0; i < 4; i++) {
      final t = i / 4;
      final x = r.left + r.width * (.18 + t * .15);
      canvas.drawLine(Offset(x, soma.dy), Offset(x - r.width * .12, r.top + r.height * (.12 + i * .12)), p);
      canvas.drawLine(Offset(x, soma.dy), Offset(x - r.width * .12, r.bottom - r.height * (.12 + i * .12)), p);
    }
    for (var i = 0; i < 3; i++) {
      final x = axonEnd - Offset(i * r.width * .08, 0);
      canvas.drawLine(x, x + Offset(r.width * .08, -r.height * .1), p);
      canvas.drawLine(x, x + Offset(r.width * .08, r.height * .1), p);
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
      final angle =
          rotation + (math.pi * 2 * i / sides);
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
      final angle =
          -math.pi / 2 + math.pi * i / points;
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
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(fontSize: 42),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      position - Offset(tp.width / 2, tp.height / 2),
    );
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
  bool shouldRepaint(
    covariant SnoteCanvasPainter oldDelegate,
  ) {
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
        oldDelegate.eraserPoint != eraserPoint ||
        oldDelegate.eraserRadius != eraserRadius ||
        oldDelegate.drawStrokes != drawStrokes ||
        oldDelegate.drawActive != drawActive;
  }
}
