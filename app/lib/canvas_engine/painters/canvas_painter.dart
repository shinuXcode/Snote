import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../ink_renderer.dart';
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
        ? activePen!.opacity.clamp(.08, .55).toDouble()
        : activePen!.opacity.clamp(.05, 1).toDouble();
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

    // Freehand live and committed strokes share exactly one geometry and
    // pressure/velocity/tilt implementation, preventing a visual jump on
    // pointer-up.
    InkRenderer.drawInk(canvas, points, stroke.pen);
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

    if (stroke.fill && !_isScienceShape(stroke.shape)) {
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
      default:
        _drawScienceShape(canvas, stroke.shape!, rect, paint);
        break;
    }
  }

  bool _isScienceShape(String? shape) => const {
        'coordinateAxes', 'parabola', 'sineWave', 'angle', 'vectorArrow',
        'projectilePath', 'rayDiagram', 'convexLens', 'concaveLens',
        'planeMirror', 'forceDiagram', 'pulley', 'circuitResistor',
        'circuitBattery', 'capacitor', 'circuitSwitch', 'circuitLamp',
        'atom', 'molecule', 'benzeneRing', 'beaker', 'testTube',
        'conicalFlask', 'orbital', 'animalCell', 'plantCell',
        'dnaHelix', 'neuron', 'leaf', 'microscope',
      }.contains(shape);

  void _drawScienceShape(Canvas canvas, String shape, Rect rect, Paint source) {
    final p = Paint()
      ..color = source.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = source.strokeWidth.clamp(0.7, 8).toDouble()
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    final w = math.max(rect.width.abs(), 24.0);
    final h = math.max(rect.height.abs(), 24.0);
    final left = rect.center.dx - w / 2;
    final top = rect.center.dy - h / 2;
    Offset at(double x, double y) => Offset(left + w * x, top + h * y);
    void line(double x1, double y1, double x2, double y2) =>
        canvas.drawLine(at(x1, y1), at(x2, y2), p);
    void circle(double x, double y, double radius, {Paint? paint}) =>
        canvas.drawCircle(at(x, y), math.max(1.0, math.min(w, h) * radius), paint ?? p);
    void arrow(double x1, double y1, double x2, double y2) {
      final a = at(x1, y1);
      final b = at(x2, y2);
      canvas.drawLine(a, b, p);
      final delta = b - a;
      if (delta.distance < 1) return;
      final unit = delta / delta.distance;
      final normal = Offset(-unit.dy, unit.dx);
      final tip = b - unit * math.min(12, delta.distance * .25);
      canvas.drawLine(b, tip + normal * 4.5, p);
      canvas.drawLine(b, tip - normal * 4.5, p);
    }
    void drawOval(double cx, double cy, double rx, double ry, {double rotate = 0}) {
      final ovalRect = Rect.fromCenter(
        center: at(cx, cy),
        width: w * rx * 2,
        height: h * ry * 2,
      );
      canvas.save();
      canvas.translate(ovalRect.center.dx, ovalRect.center.dy);
      canvas.rotate(rotate);
      canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: ovalRect.width, height: ovalRect.height), p);
      canvas.restore();
    }
    void drawLabel(String text, double x, double y) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: TextStyle(color: p.color, fontSize: math.max(9, p.strokeWidth * 3), fontWeight: FontWeight.w700)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, at(x, y));
    }

    switch (shape) {
      case 'coordinateAxes':
        arrow(.12, .85, .9, .85);
        arrow(.15, .9, .15, .08);
        for (var i = 1; i <= 6; i++) {
          final x = .15 + i * .1;
          line(x, .83, x, .87);
          final y = .85 - i * .11;
          line(.13, y, .17, y);
        }
        break;
      case 'parabola':
        line(.08, .82, .93, .82);
        line(.18, .92, .18, .08);
        final path = Path()..moveTo(left + w * .28, top + h * .18);
        for (var i = 0; i <= 28; i++) {
          final x = -.72 + i * 1.44 / 28;
          final y = .14 + x * x * 1.25;
          path.lineTo(left + w * (.5 + x * .52), top + h * y);
        }
        canvas.drawPath(path, p);
        break;
      case 'sineWave':
        final path = Path()..moveTo(left + w * .05, top + h * .5);
        for (var i = 1; i <= 64; i++) {
          final x = i / 64;
          path.lineTo(left + w * (.05 + .9 * x), top + h * (.5 - .3 * math.sin(x * math.pi * 2)));
        }
        canvas.drawPath(path, p);
        break;
      case 'angle':
        line(.14, .82, .85, .82);
        line(.14, .82, .64, .17);
        drawLabel('θ', .36, .63);
        break;
      case 'vectorArrow':
        arrow(.16, .8, .82, .22);
        line(.16, .8, .83, .8);
        line(.82, .22, .82, .8);
        break;
      case 'projectilePath':
        final path = Path()
          ..moveTo(left + w * .08, top + h * .82)
          ..cubicTo(left + w * .38, top - h * .05, left + w * .64, top - h * .03, left + w * .9, top + h * .82);
        canvas.drawPath(path, p);
        arrow(.7, .49, .83, .68);
        line(.05, .83, .96, .83);
        break;
      case 'rayDiagram':
        line(.05, .5, .95, .5);
        line(.56, .1, .56, .9);
        arrow(.08, .25, .56, .25);
        arrow(.56, .25, .9, .72);
        line(.56, .25, .9, .25);
        break;
      case 'convexLens':
        final path = Path()
          ..moveTo(left + w * .5, top + h * .08)
          ..cubicTo(left + w * .15, top + h * .25, left + w * .15, top + h * .75, left + w * .5, top + h * .92)
          ..cubicTo(left + w * .85, top + h * .75, left + w * .85, top + h * .25, left + w * .5, top + h * .08);
        canvas.drawPath(path, p);
        break;
      case 'concaveLens':
        final path = Path()
          ..moveTo(left + w * .25, top + h * .08)
          ..quadraticBezierTo(left + w * .53, top + h * .5, left + w * .25, top + h * .92)
          ..lineTo(left + w * .75, top + h * .92)
          ..quadraticBezierTo(left + w * .47, top + h * .5, left + w * .75, top + h * .08)
          ..close();
        canvas.drawPath(path, p);
        break;
      case 'planeMirror':
        line(.7, .08, .7, .92);
        for (var i = 0; i < 8; i++) {
          final y = .12 + i * .1;
          line(.7, y, .82, y + .08);
        }
        arrow(.08, .25, .7, .25);
        arrow(.7, .25, .18, .82);
        break;
      case 'forceDiagram':
        canvas.drawRect(Rect.fromCenter(center: at(.5, .55), width: w * .28, height: h * .24), p);
        arrow(.5, .55, .5, .06);
        arrow(.5, .55, .5, .98);
        arrow(.5, .55, .94, .55);
        arrow(.5, .55, .12, .55);
        drawLabel('N', .53, .08);
        drawLabel('mg', .53, .84);
        break;
      case 'pulley':
        drawOval(.5, .33, .23, .23);
        line(.5, .1, .5, .03);
        line(.27, .33, .27, .9);
        line(.73, .33, .73, .9);
        line(.27, .9, .42, .9);
        line(.73, .9, .58, .9);
        break;
      case 'circuitResistor':
        line(.03, .5, .2, .5);
        final path = Path()..moveTo(left + w * .2, top + h * .5);
        for (var i = 0; i < 6; i++) {
          path.lineTo(left + w * (.25 + i * .1), top + h * (i.isEven ? .32 : .68));
        }
        path.lineTo(left + w * .8, top + h * .5);
        canvas.drawPath(path, p);
        line(.8, .5, .97, .5);
        break;
      case 'circuitBattery':
        line(.04, .5, .38, .5);
        line(.62, .5, .96, .5);
        line(.42, .25, .42, .75);
        line(.57, .12, .57, .88);
        break;
      case 'capacitor':
        line(.03, .5, .43, .5);
        line(.43, .22, .43, .78);
        line(.57, .22, .57, .78);
        line(.57, .5, .97, .5);
        break;
      case 'circuitSwitch':
        line(.03, .5, .38, .5);
        circle(.38, .5, .025);
        circle(.69, .5, .025);
        line(.38, .5, .64, .29);
        line(.69, .5, .97, .5);
        break;
      case 'circuitLamp':
        line(.02, .5, .27, .5);
        line(.73, .5, .98, .5);
        circle(.5, .5, .23);
        line(.35, .35, .65, .65);
        line(.35, .65, .65, .35);
        break;
      case 'atom':
        drawOval(.5, .5, .38, .18, rotate: .6);
        drawOval(.5, .5, .38, .18, rotate: -.6);
        drawOval(.5, .5, .38, .18, rotate: math.pi / 2);
        circle(.5, .5, .06);
        for (final point in [at(.25, .35), at(.73, .32), at(.5, .15), at(.72, .72)]) {
          canvas.drawCircle(point, math.max(2, p.strokeWidth * 1.8), p);
        }
        break;
      case 'molecule':
        line(.25, .5, .5, .28);
        line(.5, .28, .76, .5);
        circle(.25, .5, .11);
        circle(.5, .28, .14);
        circle(.76, .5, .11);
        break;
      case 'benzeneRing':
        canvas.drawPath(_regularPolygon(at(.5, .5), math.min(w, h) * .34, 6, math.pi / 6), p);
        circle(.5, .5, .16);
        break;
      case 'beaker':
        line(.32, .1, .68, .1);
        line(.36, .1, .36, .28);
        line(.64, .1, .64, .28);
        line(.36, .28, .2, .84);
        line(.64, .28, .8, .84);
        line(.2, .84, .8, .84);
        line(.28, .58, .72, .58);
        break;
      case 'testTube':
        line(.32, .08, .32, .72);
        line(.68, .08, .68, .72);
        final tube = Path()
          ..moveTo(left + w * .32, top + h * .72)
          ..quadraticBezierTo(left + w * .5, top + h * .99, left + w * .68, top + h * .72);
        canvas.drawPath(tube, p);
        line(.32, .08, .68, .08);
        line(.35, .6, .65, .6);
        break;
      case 'conicalFlask':
        line(.43, .08, .57, .08);
        line(.43, .08, .43, .34);
        line(.57, .08, .57, .34);
        line(.43, .34, .18, .82);
        line(.57, .34, .82, .82);
        line(.18, .82, .82, .82);
        line(.3, .62, .7, .62);
        break;
      case 'orbital':
        drawOval(.5, .5, .37, .17);
        drawOval(.5, .5, .17, .37);
        circle(.5, .5, .06);
        break;
      case 'animalCell':
        drawOval(.5, .5, .42, .36);
        drawOval(.45, .48, .14, .13);
        circle(.7, .36, .045);
        circle(.29, .63, .04);
        circle(.65, .69, .035);
        break;
      case 'plantCell':
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(left + w * .08, top + h * .12, w * .84, h * .76), const Radius.circular(5)), p);
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(left + w * .16, top + h * .2, w * .68, h * .6), const Radius.circular(4)), p);
        drawOval(.4, .43, .1, .11);
        canvas.drawRect(Rect.fromLTWH(left + w * .52, top + h * .32, w * .2, h * .34), p);
        break;
      case 'dnaHelix':
        final a = Path()..moveTo(left + w * .2, top + h * .04);
        final b = Path()..moveTo(left + w * .8, top + h * .04);
        for (var i = 1; i <= 48; i++) {
          final y = i / 48;
          a.lineTo(left + w * (.5 + .28 * math.sin(y * math.pi * 4)), top + h * y);
          b.lineTo(left + w * (.5 - .28 * math.sin(y * math.pi * 4)), top + h * y);
        }
        canvas.drawPath(a, p);
        canvas.drawPath(b, p);
        for (var i = 0; i <= 9; i++) {
          final y = .05 + i * .1;
          final x1 = .5 + .28 * math.sin(y * math.pi * 4);
          final x2 = .5 - .28 * math.sin(y * math.pi * 4);
          line(x1, y, x2, y);
        }
        break;
      case 'neuron':
        drawOval(.3, .5, .16, .2);
        circle(.3, .5, .04);
        line(.16, .36, .04, .22);
        line(.17, .5, .03, .5);
        line(.17, .64, .04, .79);
        line(.42, .5, .95, .5);
        for (var i = 0; i < 4; i++) {
          final x = .76 + i * .05;
          line(x, .5, x + .08, .36 + (i % 2) * .28);
        }
        break;
      case 'leaf':
        final leaf = Path()
          ..moveTo(left + w * .12, top + h * .78)
          ..quadraticBezierTo(left + w * .12, top + h * .1, left + w * .88, top + h * .18)
          ..quadraticBezierTo(left + w * .9, top + h * .9, left + w * .12, top + h * .78)
          ..close();
        canvas.drawPath(leaf, p);
        line(.14, .77, .82, .22);
        for (var i = 0; i < 5; i++) {
          final t = .25 + i * .12;
          line(t, .77 - t * .58, t - .1, .53 - t * .3);
        }
        break;
      case 'microscope':
        line(.38, .1, .62, .1);
        line(.44, .1, .44, .31);
        line(.62, .1, .62, .28);
        line(.44, .31, .65, .48);
        line(.65, .48, .64, .66);
        line(.33, .66, .78, .66);
        line(.54, .66, .54, .83);
        line(.25, .84, .82, .84);
        drawOval(.52, .55, .13, .08);
        break;
      default:
        // Unknown future science tools still render as their bounding box
        // rather than silently becoming invisible.
        canvas.drawRect(rect, p);
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
