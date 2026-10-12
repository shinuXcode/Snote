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
  final double activeFillOpacity;
  final Color? activeFillColor;
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
    this.activeFillOpacity = 1.0,
    this.activeFillColor,
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
      fillOpacity: activeFillOpacity,
      fillColor: activeFillColor,
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
    if (const {'ruler', 'compass', 'protractor', 'divider'}.contains(stroke.shape)) {
      _drawMeasurementGeometry(canvas, stroke, paint);
      return;
    }
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

  void _drawMeasurementGeometry(Canvas canvas, Stroke stroke, Paint sourcePaint) {
    final points = stroke.points;
    final start = points.first.position;
    final end = points.last.position;
    final distance = (end - start).distance;
    final paint = Paint()
      ..color = sourcePaint.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, sourcePaint.strokeWidth)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    if (stroke.shape == 'ruler') {
      // The ruler constrains the gesture to a true straight line; the ruler
      // itself is not painted onto the note.
      canvas.drawLine(start, end, paint);
      return;
    }

    if (stroke.shape == 'compass') {
      // Start at the chosen center and drag to set the compass radius.
      if (distance > 1) canvas.drawCircle(start, distance, paint);
      return;
    }

    if (stroke.shape == 'divider') {
      // Divider marks are two measurement tips plus a dimension baseline,
      // rather than a pictogram of the instrument.
      if (distance <= 1) return;
      final direction = (end - start) / distance;
      final normal = Offset(-direction.dy, direction.dx);
      canvas.drawLine(start, end, paint);
      canvas.drawLine(start - normal * 7, start + normal * 7, paint);
      canvas.drawLine(end - normal * 7, end + normal * 7, paint);
      canvas.drawCircle(start, 2.1, paint);
      canvas.drawCircle(end, 2.1, paint);
      final cm = distance / 37.7952755906;
      final label = TextPainter(
        text: TextSpan(
          text: cm.toStringAsFixed(1) + ' cm',
          style: TextStyle(
            color: sourcePaint.color,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            backgroundColor: const Color(0x00ffffff),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final midpoint = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
      label.paint(canvas, midpoint + normal * 9 - Offset(label.width / 2, label.height / 2));
      return;
    }

    if (stroke.shape == 'protractor') {
      // Gesture order is center -> first ray -> second ray. Draw the angle,
      // its two rays, and a degree label without drawing a protractor body.
      if (points.length < 3) {
        canvas.drawLine(start, end, paint);
        return;
      }
      final center = start;
      final firstRay = points[1].position;
      final lastRay = end;
      final v1 = firstRay - center;
      final v2 = lastRay - center;
      final r1 = v1.distance;
      final r2 = v2.distance;
      if (r1 <= 1 || r2 <= 1) return;
      canvas.drawLine(center, firstRay, paint);
      canvas.drawLine(center, lastRay, paint);
      final startAngle = math.atan2(v1.dy, v1.dx);
      final endAngle = math.atan2(v2.dy, v2.dx);
      var sweep = endAngle - startAngle;
      while (sweep > math.pi) sweep -= math.pi * 2;
      while (sweep < -math.pi) sweep += math.pi * 2;
      final radius = math.min(r1, r2) * .42;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweep,
        false,
        paint,
      );
      final degrees = (sweep.abs() * 180 / math.pi).round();
      final labelPos = center + Offset(
        math.cos(startAngle + sweep / 2) * (radius + 14),
        math.sin(startAngle + sweep / 2) * (radius + 14),
      );
      final label = TextPainter(
        text: TextSpan(
          text: '$degrees°',
          style: TextStyle(color: sourcePaint.color, fontSize: 12, fontWeight: FontWeight.w800),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, labelPos - Offset(label.width / 2, label.height / 2));
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
      case 'dottedLine':
      case 'dashedLine':
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

    final dotted = stroke.shape == 'dottedLine';
    final dashLength = dotted ? 1.5 : 8.0;
    final step = dotted ? 6.0 : 14.0;
    for (final metric in path.computeMetrics()) {
      for (double distance = 0; distance < metric.length; distance += step) {
        final end = math.min(distance + dashLength, metric.length);
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
      case 'dottedLine':
      case 'dashedLine':
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
        'pentagon',
        'parallelogram',
        'trapezoid',
        'cube',
        'cuboid',
        'cylinder',
        'cone',
        'pyramid',
        'triangularPrism',
        'sphere',
        'arc',
        'semicircle',
        'sector',
        'ring',
        'crescent',
        'cross',
        'plus',
        'heart',
        'cloud',
        'speechBubble',
        'callout',
        'curlyBrace',
        'bracket',
        'dimensionLine',
        'numberLine',
        'unitCircle',
        'cubicGraph',
        'exponentialGraph',
        'logarithmicGraph',
        'tangentGraph',
        'ellipseAxes',
        'vectorField',
        'polarGraph',
        'histogram',
        'barChart',
        'pieChart',
        'flowchartTerminator',
        'flowchartProcess',
        'flowchartDecision',
        'flowchartInputOutput',
        'flowchartDocument',
        'flowchartDatabase',
        'flowchartConnector',
        'timeline',
        'tableGrid',
        'checklist',
        'waveform',
        'spring',
        'lever',
        'inclinedPlane',
        'gear',
        'magnet',
        'thermometer',
        'stopwatch',
        'ruler',
        'compass',
        'protractor',
        'divider',
        'dottedLine',
        'dashedLine',
        'cartesianPlane',
      }.contains(shape);

  void _drawScienceShape(Canvas canvas, String shape, Rect rect, Paint source) {
    final p = Paint()
      ..color = source.color
      ..style = source.style
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
    void polygon(List<Offset> points) {
      if (points.length < 2) return;
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) { path.lineTo(point.dx, point.dy); }
      path.close();
      canvas.drawPath(path, p);
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

      case 'cartesianPlane':
        for (var i = 1; i < 10; i++) {
          final t = i / 10;
          line(t, .08, t, .92);
          line(.08, t, .92, t);
        }
        arrow(.08, .5, .94, .5);
        arrow(.5, .92, .5, .06);
        circle(.5, .5, .018);
        break;
      case 'pentagon':
        polygon([at(.5,.08),at(.91,.4),at(.75,.9),at(.25,.9),at(.09,.4)]);
        break;
      case 'parallelogram':
        polygon([at(.3,.15),at(.92,.15),at(.7,.85),at(.08,.85)]);
        break;
      case 'trapezoid':
        polygon([at(.28,.15),at(.72,.15),at(.94,.85),at(.06,.85)]);
        break;
      case 'cube':
        polygon([at(.18,.25),at(.56,.25),at(.56,.7),at(.18,.7)]);
        polygon([at(.18,.25),at(.4,.08),at(.78,.08),at(.56,.25)]);
        polygon([at(.56,.25),at(.78,.08),at(.78,.53),at(.56,.7)]);
        line(.18,.7,.4,.53); line(.4,.53,.78,.53); line(.4,.53,.4,.08);
        break;
      case 'cuboid':
        polygon([at(.12,.32),at(.62,.32),at(.62,.83),at(.12,.83)]);
        polygon([at(.12,.32),at(.32,.12),at(.82,.12),at(.62,.32)]);
        polygon([at(.62,.32),at(.82,.12),at(.82,.63),at(.62,.83)]);
        line(.12,.83,.32,.63); line(.32,.63,.82,.63); line(.32,.63,.32,.12);
        break;
      case 'cylinder':
        drawOval(.5,.22,.34,.12);
        line(.16,.22,.16,.78); line(.84,.22,.84,.78);
        canvas.drawArc(Rect.fromCenter(center:at(.5,.78),width:w*.68,height:h*.24),0,math.pi,false,p);
        canvas.drawArc(Rect.fromCenter(center:at(.5,.78),width:w*.68,height:h*.24),math.pi,math.pi,false,p);
        break;
      case 'cone':
        line(.5,.1,.12,.84); line(.5,.1,.88,.84);
        canvas.drawArc(Rect.fromCenter(center:at(.5,.82),width:w*.76,height:h*.18),0,math.pi,false,p);
        canvas.drawArc(Rect.fromCenter(center:at(.5,.82),width:w*.76,height:h*.18),math.pi,math.pi,false,p);
        break;
      case 'pyramid':
        polygon([at(.5,.08),at(.12,.84),at(.9,.84)]);
        line(.5,.08,.5,.56); line(.5,.56,.12,.84); line(.5,.56,.9,.84);
        break;
      case 'triangularPrism':
        polygon([at(.12,.38),at(.38,.12),at(.38,.76)]);
        polygon([at(.62,.38),at(.88,.12),at(.88,.76)]);
        line(.12,.38,.62,.38); line(.38,.12,.88,.12); line(.38,.76,.88,.76);
        break;
      case 'sphere':
        drawOval(.5,.5,.36,.36); drawOval(.5,.5,.36,.14);
        canvas.drawArc(Rect.fromCenter(center:at(.5,.5),width:w*.24,height:h*.72),math.pi/2,math.pi,false,p);
        canvas.drawArc(Rect.fromCenter(center:at(.5,.5),width:w*.24,height:h*.72),-math.pi/2,math.pi,false,p);
        break;
      case 'arc':
        canvas.drawArc(Rect.fromCenter(center:at(.5,.52),width:w*.72,height:h*.72),math.pi*1.05,math.pi*.9,false,p);
        break;
      case 'semicircle':
        canvas.drawArc(Rect.fromCenter(center:at(.5,.55),width:w*.74,height:h*.74),math.pi,math.pi,false,p);
        line(.13,.55,.87,.55);
        break;
      case 'sector':
        final sectorRect=Rect.fromCenter(center:at(.5,.5),width:w*.72,height:h*.72);
        final cp=at(.5,.5); final edge=at(.86,.5);
        final sectorPath=Path()..moveTo(cp.dx,cp.dy)..lineTo(edge.dx,edge.dy)
          ..arcTo(sectorRect,0,math.pi*.68,false)..close();
        canvas.drawPath(sectorPath,p);
        break;
      case 'ring':
        drawOval(.5,.5,.39,.39); drawOval(.5,.5,.2,.2);
        break;
      case 'crescent':
        final crescent=Path()..moveTo(left+w*.76,top+h*.16)
          ..cubicTo(left+w*.14,top+h*.08,left+w*.12,top+h*.89,left+w*.76,top+h*.84)
          ..cubicTo(left+w*.43,top+h*.65,left+w*.45,top+h*.34,left+w*.76,top+h*.16)..close();
        canvas.drawPath(crescent,p);
        break;
      case 'cross':
        canvas.drawRect(Rect.fromLTWH(left+w*.4,top+h*.12,w*.2,h*.76),p);
        canvas.drawRect(Rect.fromLTWH(left+w*.12,top+h*.4,w*.76,h*.2),p);
        break;
      case 'plus':
        line(.5,.12,.5,.88); line(.12,.5,.88,.5);
        break;
      case 'heart':
        final heart=Path()..moveTo(left+w*.5,top+h*.88)
          ..cubicTo(left+w*.35,top+h*.72,left+w*.04,top+h*.5,left+w*.11,top+h*.3)
          ..cubicTo(left+w*.18,top+h*.06,left+w*.42,top+h*.16,left+w*.5,top+h*.32)
          ..cubicTo(left+w*.64,top+h*.06,left+w*.9,top+h*.06,left+w*.92,top+h*.32)
          ..cubicTo(left+w*.96,top+h*.54,left+w*.64,top+h*.78,left+w*.5,top+h*.88)..close();
        canvas.drawPath(heart,p);
        break;
      case 'cloud':
        canvas.drawArc(Rect.fromLTWH(left+w*.12,top+h*.38,w*.34,h*.42),math.pi*.95,math.pi*1.1,false,p);
        canvas.drawArc(Rect.fromLTWH(left+w*.31,top+h*.18,w*.4,h*.52),math.pi*1.05,math.pi*1.1,false,p);
        canvas.drawArc(Rect.fromLTWH(left+w*.58,top+h*.36,w*.3,h*.38),math.pi*.96,math.pi*1.1,false,p);
        line(.2,.74,.81,.74);
        break;
      case 'speechBubble':
      case 'callout':
        final bubble=Path()..moveTo(left+w*.15,top+h*.18)..lineTo(left+w*.85,top+h*.18)
          ..lineTo(left+w*.85,top+h*.68)..lineTo(left+w*.56,top+h*.68)
          ..lineTo(left+w*.4,top+h*.88)..lineTo(left+w*.42,top+h*.68)
          ..lineTo(left+w*.15,top+h*.68)..close();
        canvas.drawPath(bubble,p);
        if(shape=='callout'){line(.25,.36,.7,.36);line(.25,.49,.62,.49);}
        break;
      case 'curlyBrace':
        final brace=Path()..moveTo(left+w*.72,top+h*.08)
          ..cubicTo(left+w*.4,top+h*.08,left+w*.62,top+h*.4,left+w*.43,top+h*.48)
          ..cubicTo(left+w*.62,top+h*.56,left+w*.4,top+h*.9,left+w*.72,top+h*.9);
        canvas.drawPath(brace,p);
        break;
      case 'bracket':
        line(.68,.1,.3,.1);line(.3,.1,.3,.9);line(.3,.9,.68,.9);
        break;
      case 'dimensionLine':
        arrow(.13,.5,.87,.5); line(.13,.32,.13,.68); line(.87,.32,.87,.68);
        break;
      case 'numberLine':
        arrow(.08,.58,.92,.58);
        for(var i=0;i<=8;i++){final x=.15+i*.0875;line(x,.52,x,.64);drawLabel((i-4).toString(),x-.025,.68);}
        break;
      case 'unitCircle':
        drawOval(.5,.5,.34,.34);line(.1,.5,.9,.5);line(.5,.1,.5,.9);
        line(.5,.5,.74,.25);circle(.5,.5,.02);
        break;
      case 'cubicGraph':
      case 'exponentialGraph':
      case 'logarithmicGraph':
      case 'tangentGraph':
        arrow(.08,.8,.94,.8); arrow(.16,.92,.16,.08);
        {
          final graph=Path(); var started=false;
          for(var i=0;i<=100;i++){
            final x=-2.4+i*4.8/100;
            double y;
            if(shape=='cubicGraph'){y=.5-(x*x*x)/12;}
            else if(shape=='exponentialGraph'){y=.8-math.exp(x*.8)*.13;}
            else if(shape=='logarithmicGraph'){y=.55-math.log(math.max(.03,x+2.45))*.2;}
            else {y=.5-math.tan(x)*.15;}
            final nx=.16+(x+2.4)/4.8*.76; final ny=y.clamp(.08,.92).toDouble();
            if(shape=='tangentGraph' && math.cos(x).abs()<.12){started=false;continue;}
            if(!started){graph.moveTo(left+w*nx,top+h*ny);started=true;}else{graph.lineTo(left+w*nx,top+h*ny);}
          }
          canvas.drawPath(graph,p);
        }
        break;
      case 'ellipseAxes':
        drawOval(.5,.5,.37,.23);line(.08,.5,.92,.5);line(.5,.12,.5,.88);
        break;
      case 'vectorField':
        for(var x=.2;x<=.8;x+=.2){for(var y=.22;y<=.78;y+=.2){arrow(x,y,math.min(.92,x+.1),math.max(.08,y-.1));}}
        break;
      case 'polarGraph':
        for(var i=1;i<=4;i++){drawOval(.5,.5,.09*i,.09*i);}
        for(var i=0;i<12;i++){final a=i*math.pi/6;line(.5,.5,.5+.4*math.cos(a),.5+.4*math.sin(a));}
        break;
      case 'histogram':
      case 'barChart':
        line(.12,.88,.12,.12);line(.12,.88,.92,.88);
        final heights=[.35,.58,.46,.72,.51];
        for(var i=0;i<heights.length;i++){final x=.2+i*.14;canvas.drawRect(Rect.fromLTRB(left+w*x,top+h*(.88-heights[i]),left+w*(x+.09),top+h*.88),p);}
        break;
      case 'pieChart':
        final pie=Path()..moveTo(at(.5,.5).dx,at(.5,.5).dy)
          ..lineTo(at(.5,.16).dx,at(.5,.16).dy)
          ..arcTo(Rect.fromCenter(center:at(.5,.5),width:w*.68,height:h*.68),-math.pi/2,math.pi*1.25,false)..close();
        canvas.drawPath(pie,p);line(.5,.5,.5,.84);
        break;
      case 'flowchartTerminator':
        canvas.drawRRect(RRect.fromRectAndRadius(rect,Radius.circular(h*.2)),p);
        break;
      case 'flowchartProcess':
        canvas.drawRect(rect,p);
        break;
      case 'flowchartDecision':
        polygon([at(.5,.08),at(.92,.5),at(.5,.92),at(.08,.5)]);
        break;
      case 'flowchartInputOutput':
        polygon([at(.25,.14),at(.92,.14),at(.75,.86),at(.08,.86)]);
        break;
      case 'flowchartDocument':
        final docPath=Path()..moveTo(left+w*.12,top+h*.12)..lineTo(left+w*.88,top+h*.12)..lineTo(left+w*.88,top+h*.72)
          ..quadraticBezierTo(left+w*.7,top+h*.92,left+w*.5,top+h*.78)
          ..quadraticBezierTo(left+w*.28,top+h*.65,left+w*.12,top+h*.82)..close();
        canvas.drawPath(docPath,p);
        break;
      case 'flowchartDatabase':
        drawOval(.5,.22,.34,.1);
        line(.16,.22,.16,.8);line(.84,.22,.84,.8);
        canvas.drawArc(Rect.fromCenter(center:at(.5,.8),width:w*.68,height:h*.2),0,math.pi,false,p);
        canvas.drawArc(Rect.fromCenter(center:at(.5,.8),width:w*.68,height:h*.2),math.pi,math.pi,false,p);
        break;
      case 'flowchartConnector':
        drawOval(.5,.5,.28,.28);
        break;
      case 'timeline':
        line(.08,.5,.92,.5);
        for(var i=0;i<5;i++){final x=.12+i*.19;circle(x,.5,.025);line(x,.5,x,.28+(i.isEven ? .22 : -.22));}
        break;
      case 'tableGrid':
        canvas.drawRect(Rect.fromLTWH(left+w*.12,top+h*.18,w*.76,h*.64),p);
        for(var i=1;i<=2;i++){line(.12,.18+i*.213,.88,.18+i*.213);line(.12+i*.253,.18,.12+i*.253,.82);}
        break;
      case 'checklist':
        for(var i=0;i<4;i++){final y=.18+i*.2;canvas.drawRect(Rect.fromLTWH(left+w*.1,top+h*y,w*.11,h*.1),p);line(.3,y+.05,.88,y+.05);}
        break;
      case 'waveform':
        final wave=Path()..moveTo(left+w*.05,top+h*.5);
        for(var i=1;i<=80;i++){final x=i/80;wave.lineTo(left+w*(.05+.9*x),top+h*(.5-.38*math.sin(x*math.pi*8)*(.4+.6*math.sin(x*math.pi))));}
        canvas.drawPath(wave,p);
        break;
      case 'spring':
        line(.1,.14,.9,.14);line(.1,.86,.9,.86);
        final spring=Path()..moveTo(left+w*.1,top+h*.5);
        for(var i=1;i<=12;i++){spring.lineTo(left+w*(.1+i*.066),top+h*(i.isEven ? .28 : .72));}
        canvas.drawPath(spring,p);
        break;
      case 'lever':
        line(.12,.36,.9,.36);polygon([at(.44,.38),at(.56,.38),at(.5,.7)]);
        canvas.drawRect(Rect.fromLTWH(left+w*.18,top+h*.18,w*.18,h*.18),p);
        break;
      case 'inclinedPlane':
        line(.1,.84,.9,.84);line(.12,.84,.82,.2);line(.12,.84,.12,.2);
        canvas.save();canvas.translate(left+w*.48,top+h*.48);canvas.rotate(-.74);canvas.drawRect(Rect.fromCenter(center:Offset.zero,width:w*.2,height:h*.17),p);canvas.restore();
        break;
      case 'gear':
        drawOval(.5,.5,.25,.25);drawOval(.5,.5,.1,.1);
        for(var i=0;i<12;i++){final a=i*math.pi/6;line(.5+.25*math.cos(a),.5+.25*math.sin(a),.5+.34*math.cos(a),.5+.34*math.sin(a));}
        break;
      case 'magnet':
        final magnet=Path()..moveTo(left+w*.25,top+h*.15)..lineTo(left+w*.25,top+h*.58)
          ..quadraticBezierTo(left+w*.25,top+h*.88,left+w*.5,top+h*.88)
          ..quadraticBezierTo(left+w*.75,top+h*.88,left+w*.75,top+h*.58)..lineTo(left+w*.75,top+h*.15);
        canvas.drawPath(magnet,p);line(.25,.15,.42,.15);line(.58,.15,.75,.15);
        break;
      case 'thermometer':
        line(.5,.15,.5,.72);drawOval(.5,.78,.14,.14);line(.42,.72,.42,.5);line(.58,.72,.58,.5);
        break;
      case 'stopwatch':
        drawOval(.5,.55,.31,.31);line(.5,.24,.5,.1);line(.39,.1,.61,.1);line(.5,.55,.65,.4);
        break;
      case 'ruler':
        canvas.drawRect(Rect.fromLTWH(left+w*.1,top+h*.28,w*.8,h*.36),p);
        for(var i=0;i<=10;i++){final x=.12+i*.076;line(x,.28,x,.28+(i.isEven ? .16 : .09));}
        break;
      case 'compass':
        drawOval(.5,.5,.34,.34);line(.5,.5,.5,.17);line(.5,.5,.78,.68);circle(.5,.5,.025);
        break;
      case 'protractor':
        canvas.drawArc(Rect.fromCenter(center:at(.5,.72),width:w*.76,height:h*.76),math.pi,math.pi,false,p);
        line(.12,.72,.88,.72);
        for(var i=0;i<=10;i++){final a=math.pi+i*math.pi/10;line(.5+.35*math.cos(a),.72+.35*math.sin(a),.5+.3*math.cos(a),.72+.3*math.sin(a));}
        break;
      case 'divider':
        drawOval(.5,.2,.10,.08);
        line(.5,.24,.31,.78);
        line(.5,.24,.69,.78);
        line(.5,.24,.5,.12);
        circle(.31,.78,.025);
        circle(.69,.78,.025);
        break;
      case 'dottedLine':
      case 'dashedLine':
        line(.08,.5,.92,.5);
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
