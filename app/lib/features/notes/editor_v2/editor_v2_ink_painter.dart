import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../canvas_engine/models/pen_config.dart';
import '../../../canvas_engine/models/stroke.dart';

/// Independent renderer used by the rebuilt editor surface.
///
/// The serialized Stroke model is intentionally shared with legacy documents,
/// but this painter has no dependency on the legacy SnoteCanvas widget,
/// controller, gesture recognizers, or repaint pipeline.
class EditorV2InkPainter extends CustomPainter {
  final List<Stroke> strokes;
  final Stroke? liveStroke;
  final Set<String> selectedStrokeIds;
  final Offset? eraserCursor;
  final double eraserRadius;
  final bool highlighterOnTop;
  final bool onlyHighlighters;
  static final Finalizer<ui.Picture> _pictureFinalizer =
      Finalizer<ui.Picture>((picture) => picture.dispose());
  ui.Picture? _basePicture;
  Path? _liveHighlighterPath;
  List<StrokePoint>? _liveHighlighterPoints;
  int _liveHighlighterPointCount = 0;

  EditorV2InkPainter({
    required this.strokes,
    this.liveStroke,
    this.selectedStrokeIds = const <String>{},
    this.eraserCursor,
    this.eraserRadius = 18,
    this.highlighterOnTop = false,
    this.onlyHighlighters = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final basePicture = _basePicture ?? _recordBasePicture();
    canvas.drawPicture(basePicture);
    if (liveStroke != null &&
        !(highlighterOnTop && !onlyHighlighters && liveStroke!.pen.type == PenType.highlighter) &&
        (!onlyHighlighters || liveStroke!.pen.type == PenType.highlighter)) {
      if (liveStroke!.pen.type == PenType.highlighter) {
        _drawLiveHighlighter(canvas, liveStroke!);
      } else {
        _drawStroke(canvas, liveStroke!);
      }
    }
    if (eraserCursor != null) {
      final bounds = Rect.fromCircle(center: eraserCursor!, radius: eraserRadius);
      // A translucent footprint plus a contrasting double outline stays visible
      // over both light and dark page backgrounds while tracking pressure live.
      canvas.drawCircle(
        eraserCursor!,
        eraserRadius,
        Paint()..color = const Color(0xff3979e8).withValues(alpha: .10),
      );
      canvas.drawCircle(
        eraserCursor!,
        eraserRadius,
        Paint()
          ..color = Colors.white.withValues(alpha: .95)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.2,
      );
      canvas.drawCircle(
        eraserCursor!,
        eraserRadius,
        Paint()
          ..color = const Color(0xff174ea6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
      canvas.drawCircle(
        eraserCursor!,
        math.max(1.2, bounds.width * .012),
        Paint()..color = const Color(0xff174ea6),
      );
    }
  }

  ui.Picture _recordBasePicture() {
    final recorder = ui.PictureRecorder();
    final recordingCanvas = Canvas(recorder);
    for (final stroke in strokes) {
      if (onlyHighlighters && stroke.pen.type != PenType.highlighter) continue;
      if (highlighterOnTop && !onlyHighlighters && stroke.pen.type == PenType.highlighter) continue;
      _drawStroke(recordingCanvas, stroke);
    }
    final picture = recorder.endRecording();
    _basePicture = picture;
    _pictureFinalizer.attach(this, picture, detach: this);
    return picture;
  }

  void _drawLiveHighlighter(Canvas canvas, Stroke stroke) {
    final points = stroke.points;
    if (points.isEmpty) return;
    if (!identical(_liveHighlighterPoints, points) ||
        _liveHighlighterPointCount > points.length) {
      _liveHighlighterPath = null;
      _liveHighlighterPoints = points;
      _liveHighlighterPointCount = 0;
    }
    if (_liveHighlighterPath == null) {
      _liveHighlighterPath = Path()..moveTo(
        points.first.position.dx,
        points.first.position.dy,
      );
      _liveHighlighterPointCount = 1;
    }
    final path = _liveHighlighterPath!;
    while (_liveHighlighterPointCount < points.length) {
      final point = points[_liveHighlighterPointCount].position;
      path.lineTo(point.dx, point.dy);
      _liveHighlighterPointCount++;
    }
    final baseWidth = stroke.pen.size.clamp(.5, 60).toDouble();
    final alpha = (stroke.pen.color.a * stroke.pen.opacity).clamp(0.0, 1.0).toDouble();
    final paint = Paint()
      ..color = stroke.pen.color.withValues(alpha: math.min(alpha, .38))
      ..blendMode = BlendMode.multiply
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = math.max(baseWidth, 7).toDouble()
      ..isAntiAlias = true;
    if (points.length == 1) {
      canvas.drawCircle(
        points.first.position,
        math.max(1.5, paint.strokeWidth * .42),
        Paint()
          ..color = paint.color
          ..blendMode = BlendMode.multiply
          ..isAntiAlias = true,
      );
    } else {
      canvas.drawPath(path, paint);
    }
  }

  Rect? _strokeBounds(Stroke stroke) {
    if (stroke.points.isEmpty) return null;
    var left = double.infinity;
    var top = double.infinity;
    var right = double.negativeInfinity;
    var bottom = double.negativeInfinity;
    for (final point in stroke.points) {
      left = math.min(left, point.position.dx);
      top = math.min(top, point.position.dy);
      right = math.max(right, point.position.dx);
      bottom = math.max(bottom, point.position.dy);
    }
    final padding = math.max(2.0, stroke.pen.size).toDouble();
    return Rect.fromLTRB(left, top, right, bottom).inflate(padding);
  }

  void _drawStroke(Canvas canvas, Stroke stroke) {
    if (stroke.points.isEmpty) return;
    if (stroke.shape != null && stroke.shape!.isNotEmpty) {
      _drawShape(canvas, stroke);
      return;
    }

    final type = stroke.pen.type;
    final baseWidth = stroke.pen.size.clamp(.5, 60).toDouble();
    final alpha = (stroke.pen.color.a * stroke.pen.opacity *
            (type == PenType.pencil ? .78 : 1.0))
        .clamp(0.0, 1.0)
        .toDouble();
    final paint = Paint()
      ..color = stroke.pen.color.withValues(alpha: alpha)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = baseWidth
      ..isAntiAlias = true;

    if (stroke.fill && stroke.points.length >= 4 &&
        (stroke.points.first.position - stroke.points.last.position).distance <=
            math.max(18.0, baseWidth * 2.5)) {
      final loop = Path()..moveTo(
        stroke.points.first.position.dx,
        stroke.points.first.position.dy,
      );
      for (final sample in stroke.points.skip(1)) {
        loop.lineTo(sample.position.dx, sample.position.dy);
      }
      loop.close();
      canvas.drawPath(
        loop,
        Paint()
          ..color = (stroke.fillColor ?? stroke.pen.color).withValues(
            alpha: (stroke.fillColor ?? stroke.pen.color).a * stroke.fillOpacity.clamp(0, 1).toDouble(),
          )
          ..style = PaintingStyle.fill
          ..isAntiAlias = true,
      );
    }
    if (type == PenType.highlighter) {
      paint
        ..strokeWidth = math.max(baseWidth, 7)
        ..blendMode = BlendMode.multiply
        ..color = stroke.pen.color.withValues(
          alpha: math.min(alpha, .38),
        );
    } else if (type == PenType.marker) {
      paint.strokeWidth = baseWidth * 1.35;
    } else if (type == PenType.brush) {
      paint.strokeWidth = baseWidth * 1.2;
    }

    if (stroke.points.length == 1) {
      final pressure = stroke.points.first.pressure.clamp(.08, 1.0);
      final pressureWidth = baseWidth * (1 - stroke.pen.pressureSensitivity * .52 + stroke.pen.pressureSensitivity * pressure);
      canvas.drawCircle(
        stroke.points.first.position,
        math.max(.6, pressureWidth * .42).toDouble(),
        Paint()
          ..color = paint.color
          ..style = PaintingStyle.fill
          ..isAntiAlias = true,
      );
      return;
    }

    final path = Path()..moveTo(
        stroke.points.first.position.dx,
        stroke.points.first.position.dy,
      );
    for (var i = 1; i < stroke.points.length - 1; i++) {
      final current = stroke.points[i].position;
      final next = stroke.points[i + 1].position;
      final midpoint = Offset(
        (current.dx + next.dx) / 2,
        (current.dy + next.dy) / 2,
      );
      path.quadraticBezierTo(current.dx, current.dy, midpoint.dx, midpoint.dy);
    }
    final last = stroke.points.last.position;
    path.lineTo(last.dx, last.dy);
    final pressureSensitive = type != PenType.pointer &&
        stroke.pen.pressureSensitivity > .001 &&
        stroke.points.length > 1;
    final inkBaseWidth = type == PenType.highlighter
        ? math.max(baseWidth, 7).toDouble()
        : type == PenType.marker
            ? baseWidth * 1.35
            : type == PenType.brush
                ? baseWidth * 1.2
                : baseWidth;

    if (type == PenType.fountain) {
      // Fountain ink reacts to both pressure and speed. Fast strokes become
      // narrower; heavier pressure broadens the nib. The first and last
      // segments taper, while a faint outer pass gives ink a soft natural edge.
      final pressureSensitivity =
          stroke.pen.pressureSensitivity.clamp(0.0, 1.0).toDouble();
      final velocitySensitivity =
          stroke.pen.velocitySensitivity.clamp(0.0, 1.0).toDouble();
      final lastIndex = stroke.points.length - 1;
      // Reuse the segment paints instead of allocating two objects per point.
      final edgePaint = Paint()
        ..blendMode = paint.blendMode
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true;
      final inkPaint = Paint()
        ..blendMode = paint.blendMode
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true;
      for (var i = 1; i < stroke.points.length; i++) {
        final a = stroke.points[i - 1];
        final b = stroke.points[i];
        final distance = (b.position - a.position).distance;
        final elapsedMs = (b.timestamp - a.timestamp).abs().clamp(1.0, 250.0);
        final speed = distance / elapsedMs;
        final speedResponse = (speed / 24.0).clamp(0.0, 1.0).toDouble();
        final pressure = ((a.pressure + b.pressure) / 2).clamp(.05, 1.0);
        final pressureFactor = .48 + pressure * (.70 + pressureSensitivity * .50);
        final velocityFactor = 1.24 - speedResponse * (.52 * velocitySensitivity);
        final progress = i / lastIndex;
        final taper = math.min(
          1.0,
          math.min(.55 + progress * 2.25, .55 + (1 - progress) * 2.25),
        );
        final width = (inkBaseWidth * pressureFactor * velocityFactor * taper)
            .clamp(.45, 60.0)
            .toDouble();
        final flowAlpha = (alpha * (.78 + pressure * .22) *
                (1 - speedResponse * .08))
            .clamp(.04, 1.0)
            .toDouble();
        edgePaint
          ..color = stroke.pen.color.withValues(alpha: flowAlpha * .13)
          ..strokeWidth = width + math.max(.45, baseWidth * .12);
        inkPaint
          ..color = stroke.pen.color.withValues(alpha: flowAlpha)
          ..strokeWidth = width;
        canvas.drawLine(a.position, b.position, edgePaint);
        canvas.drawLine(a.position, b.position, inkPaint);
      }
    } else if (!pressureSensitive) {
      canvas.drawPath(path, paint);
    } else {
      // Use variable-width segments only: a full-width base path would hide
      // the pressure effect beneath those segments. Reuse one Paint for the
      // whole stroke to avoid allocating an object for every pointer sample.
      final segmentPaint = Paint()
        ..color = paint.color
        ..blendMode = paint.blendMode
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true;
      for (var i = 1; i < stroke.points.length; i++) {
        final a = stroke.points[i - 1];
        final b = stroke.points[i];
        final pressure = ((a.pressure + b.pressure) / 2).clamp(.08, 1.0);
        final width = inkBaseWidth *
            (1 - stroke.pen.pressureSensitivity * .52 +
                stroke.pen.pressureSensitivity * pressure);
        segmentPaint.strokeWidth = width.clamp(.5, 60).toDouble();
        canvas.drawLine(a.position, b.position, segmentPaint);
      }
    }
  }

  void _drawShape(Canvas canvas, Stroke stroke) {
    final points = stroke.points;
    if (points.isEmpty) return;
    final start = points.first.position;
    final end = points.length > 1 ? points.last.position : start + const Offset(1, 1);
    final rect = Rect.fromPoints(start, end);
    final safeRect = rect.width < 1 || rect.height < 1
        ? Rect.fromCenter(
            center: rect.center,
            width: math.max(rect.width, 2).toDouble(),
            height: math.max(rect.height, 2).toDouble(),
          )
        : rect;
    final shape = stroke.shape ?? 'line';
    final pressureMean = points.isEmpty
        ? 1.0
        : points.fold<double>(0, (sum, point) => sum + point.pressure) / points.length;
    final pressureSensitivity = stroke.pen.type == PenType.pointer
        ? 0.0
        : stroke.pen.pressureSensitivity.clamp(0, 1).toDouble();
    final pressureWidth = stroke.pen.size *
        (1 - pressureSensitivity * .52 + pressureSensitivity * pressureMean.clamp(.08, 1.0));
    final base = Paint()
      ..color = stroke.pen.color.withValues(
        alpha: stroke.pen.opacity.clamp(.05, 1).toDouble(),
      )
      ..strokeWidth = pressureWidth.clamp(.6, 20).toDouble()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    final fill = Paint()
      ..color = (stroke.fillColor ?? stroke.pen.color).withValues(
        alpha: stroke.fill ? stroke.fillOpacity.clamp(0, 1).toDouble() : 0,
      )
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    void line(Offset a, Offset b, [Paint? p]) => canvas.drawLine(a, b, p ?? base);
    void arrow(Offset a, Offset b, {bool both = false}) {
      line(a, b);
      _drawArrowHead(canvas, a, b, base);
      if (both) _drawArrowHead(canvas, b, a, base);
    }

    Path polygon(List<Offset> vertices, {bool close = true}) {
      final path = Path()..moveTo(vertices.first.dx, vertices.first.dy);
      for (final p in vertices.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      if (close) path.close();
      return path;
    }

    List<Offset> regularPolygon(int sides, {double rotation = -math.pi / 2}) {
      return List<Offset>.generate(sides, (index) {
        final angle = rotation + index * math.pi * 2 / sides;
        return Offset(
          safeRect.center.dx + math.cos(angle) * safeRect.width * .48,
          safeRect.center.dy + math.sin(angle) * safeRect.height * .48,
        );
      });
    }

    void label(String text) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: stroke.pen.color,
            fontSize: math.max(9, math.min(16, safeRect.height * .14)).toDouble(),
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        maxLines: 2,
      )..layout(maxWidth: math.max(24, safeRect.width - 8));
      painter.paint(
        canvas,
        Offset(
          safeRect.center.dx - painter.width / 2,
          safeRect.center.dy - painter.height / 2,
        ),
      );
    }

    if (stroke.fill) {
      final lower = shape.toLowerCase();
      final openShape = const {
        'line', 'dottedLine', 'dashedLine', 'divider', 'arrow',
        'vectorArrow', 'curvedArrow', 'doubleArrow', 'dimensionLine',
        'numberLine', 'ruler', 'compass', 'protractor', 'rayDiagram',
        'waveform', 'projectilePath',
      }.contains(shape) || lower.contains('arrow') || lower.contains('line');

      if (!openShape) {
        late Path fillPath;
        switch (shape) {
          case 'roundedRectangle':
            fillPath = Path()..addRRect(RRect.fromRectAndRadius(safeRect, const Radius.circular(12)));
            break;
          case 'ellipse':
          case 'circle':
          case 'sphere':
          case 'flowchartConnector':
          case 'animalCell':
          case 'unitCircle':
          case 'atom':
          case 'orbital':
            fillPath = Path()..addOval(safeRect);
            break;
          case 'triangle':
          case 'pyramid':
            fillPath = polygon([
              Offset(safeRect.center.dx, safeRect.top),
              safeRect.bottomRight,
              Offset(safeRect.left, safeRect.bottom),
            ]);
            break;
          case 'diamond':
          case 'flowchartDecision':
            fillPath = polygon([
              Offset(safeRect.center.dx, safeRect.top),
              safeRect.centerRight,
              Offset(safeRect.center.dx, safeRect.bottom),
              safeRect.centerLeft,
            ]);
            break;
          case 'pentagon':
            fillPath = polygon(regularPolygon(5));
            break;
          case 'hexagon':
            fillPath = polygon(regularPolygon(6));
            break;
          case 'heptagon':
            fillPath = polygon(regularPolygon(7));
            break;
          case 'octagon':
            fillPath = polygon(regularPolygon(8));
            break;
          case 'nonagon':
            fillPath = polygon(regularPolygon(9));
            break;
          case 'decagon':
            fillPath = polygon(regularPolygon(10));
            break;
          case 'customPolygon':
            fillPath = polygon(regularPolygon(stroke.customSides.clamp(3, 24)));
            break;
          case 'parallelogram':
            fillPath = polygon([
              Offset(safeRect.left + safeRect.width * .22, safeRect.top),
              safeRect.topRight,
              Offset(safeRect.right - safeRect.width * .22, safeRect.bottom),
              safeRect.bottomLeft,
            ]);
            break;
          case 'trapezoid':
            fillPath = polygon([
              Offset(safeRect.left + safeRect.width * .2, safeRect.top),
              Offset(safeRect.right - safeRect.width * .2, safeRect.top),
              safeRect.bottomRight,
              safeRect.bottomLeft,
            ]);
            break;
          case 'star':
            fillPath = polygon(List<Offset>.generate(10, (index) {
              final radius = index.isEven ? .48 : .21;
              final angle = -math.pi / 2 + index * math.pi / 5;
              return Offset(
                safeRect.center.dx + math.cos(angle) * safeRect.width * radius,
                safeRect.center.dy + math.sin(angle) * safeRect.height * radius,
              );
            }));
            break;
          default:
            fillPath = Path()..addRect(safeRect);
            break;
        }
        canvas.drawPath(fillPath, fill);
      }
    }

    switch (shape) {
      case 'line':
      case 'dottedLine':
      case 'dashedLine':
      case 'divider':
        if (shape == 'dottedLine' || stroke.dashed) {
          _drawDashedLine(canvas, start, end, base, dotted: shape == 'dottedLine');
        } else {
          line(start, end);
        }
      case 'arrow':
      case 'vectorArrow':
      case 'rayDiagram':
      case 'forceDiagram':
        arrow(start, end);
        if (shape == 'forceDiagram') {
          arrow(safeRect.topLeft, safeRect.bottomRight);
          arrow(safeRect.bottomLeft, safeRect.topRight);
        }
      case 'dimensionLine':
        arrow(start, end, both: true);
        _drawDimensionTicks(canvas, start, end, base);
      case 'numberLine':
        line(Offset(safeRect.left, safeRect.center.dy),
            Offset(safeRect.right, safeRect.center.dy));
        for (var x = safeRect.left; x <= safeRect.right; x += 16) {
          line(Offset(x, safeRect.center.dy - 6),
              Offset(x, safeRect.center.dy + 6));
        }
      case 'rectangle':
      case 'flowchartProcess':
      case 'cuboid':
        canvas.drawRect(safeRect, base);
        if (shape == 'cuboid') {
          final o = Offset(safeRect.width * .16, -safeRect.height * .16);
          canvas.drawRect(safeRect.shift(o), base);
          line(safeRect.topLeft, safeRect.topLeft + o);
          line(safeRect.topRight, safeRect.topRight + o);
          line(safeRect.bottomRight, safeRect.bottomRight + o);
        }
      case 'roundedRectangle':
        canvas.drawRRect(
          RRect.fromRectAndRadius(safeRect, const Radius.circular(12)),
          base,
        );
      case 'ellipse':
      case 'circle':
      case 'sphere':
      case 'flowchartConnector':
      case 'atom':
      case 'orbital':
      case 'animalCell':
        canvas.drawOval(safeRect, base);
        if (shape == 'sphere') {
          canvas.drawOval(
            Rect.fromLTWH(
              safeRect.left + safeRect.width * .22,
              safeRect.top,
              safeRect.width * .56,
              safeRect.height,
            ),
            base,
          );
          canvas.drawOval(
            Rect.fromLTWH(
              safeRect.left,
              safeRect.top + safeRect.height * .3,
              safeRect.width,
              safeRect.height * .4,
            ),
            base,
          );
        } else if (shape == 'atom' || shape == 'orbital') {
          canvas.drawOval(
            Rect.fromCenter(
              center: safeRect.center,
              width: safeRect.width * .48,
              height: safeRect.height,
            ),
            base,
          );
          canvas.drawOval(
            Rect.fromCenter(
              center: safeRect.center,
              width: safeRect.width,
              height: safeRect.height * .48,
            ),
            base,
          );
          canvas.drawCircle(safeRect.center, math.max(2, base.strokeWidth * 1.8).toDouble(), fill..color = stroke.pen.color);
        }
      case 'triangle':
      case 'pyramid':
        canvas.drawPath(
          polygon([
            Offset(safeRect.center.dx, safeRect.top),
            safeRect.bottomRight,
            Offset(safeRect.left, safeRect.bottom),
          ]),
          base,
        );
        if (shape == 'pyramid') {
          line(Offset(safeRect.center.dx, safeRect.top),
              Offset(safeRect.center.dx, safeRect.bottom));
          line(Offset(safeRect.center.dx, safeRect.bottom),
              Offset(safeRect.left, safeRect.bottom - safeRect.height * .15));
        }
      case 'diamond':
        canvas.drawPath(
          polygon([
            Offset(safeRect.center.dx, safeRect.top),
            Offset(safeRect.right, safeRect.center.dy),
            Offset(safeRect.center.dx, safeRect.bottom),
            Offset(safeRect.left, safeRect.center.dy),
          ]),
          base,
        );
      case 'pentagon':
        canvas.drawPath(polygon(regularPolygon(5)), base);
      case 'hexagon':
      case 'benzeneRing':
        canvas.drawPath(polygon(regularPolygon(6)), base);
        if (shape == 'benzeneRing') {
          canvas.drawPath(
            polygon(regularPolygon(6).map((p) {
              return Offset(
                safeRect.center.dx + (p.dx - safeRect.center.dx) * .68,
                safeRect.center.dy + (p.dy - safeRect.center.dy) * .68,
              );
            }).toList()),
            base,
          );
        }
      case 'customPolygon':
        canvas.drawPath(polygon(regularPolygon(stroke.customSides.clamp(3, 24))), base);
      case 'star':
        final vertices = <Offset>[];
        for (var i = 0; i < 10; i++) {
          final radius = i.isEven ? .48 : .21;
          final angle = -math.pi / 2 + i * math.pi / 5;
          vertices.add(Offset(
            safeRect.center.dx + math.cos(angle) * safeRect.width * radius,
            safeRect.center.dy + math.sin(angle) * safeRect.height * radius,
          ));
        }
        canvas.drawPath(polygon(vertices), base);
      case 'parallelogram':
      case 'trapezoid':
        final inset = safeRect.width * (shape == 'trapezoid' ? .2 : .14);
        canvas.drawPath(
          polygon([
            Offset(safeRect.left + inset, safeRect.top),
            Offset(safeRect.right, safeRect.top),
            Offset(safeRect.right - inset, safeRect.bottom),
            Offset(safeRect.left, safeRect.bottom),
          ]),
          base,
        );
      case 'cube':
      case 'triangularPrism':
        final o = Offset(safeRect.width * .2, -safeRect.height * .2);
        canvas.drawRect(safeRect, base);
        canvas.drawRect(safeRect.shift(o), base);
        line(safeRect.topLeft, safeRect.topLeft + o);
        line(safeRect.topRight, safeRect.topRight + o);
        line(safeRect.bottomRight, safeRect.bottomRight + o);
      case 'cylinder':
        canvas.drawRect(safeRect, base);
        canvas.drawOval(Rect.fromLTWH(safeRect.left, safeRect.top, safeRect.width, safeRect.height * .2), base);
        canvas.drawArc(Rect.fromLTWH(safeRect.left, safeRect.bottom - safeRect.height * .2, safeRect.width, safeRect.height * .2), 0, math.pi, false, base);
      case 'cone':
        canvas.drawPath(
          polygon([
            Offset(safeRect.center.dx, safeRect.top),
            Offset(safeRect.right, safeRect.bottom),
            Offset(safeRect.left, safeRect.bottom),
          ]),
          base,
        );
        canvas.drawOval(Rect.fromLTWH(safeRect.left, safeRect.bottom - safeRect.height * .14, safeRect.width, safeRect.height * .22), base);
      case 'arc':
      case 'semicircle':
      case 'sector':
      case 'ring':
      case 'crescent':
        if (shape == 'semicircle') {
          canvas.drawArc(safeRect, math.pi, math.pi, false, base);
          line(Offset(safeRect.left, safeRect.center.dy), Offset(safeRect.right, safeRect.center.dy));
        } else if (shape == 'sector') {
          canvas.drawArc(safeRect, -math.pi / 2, math.pi * .72, false, base);
          line(safeRect.center, Offset(safeRect.center.dx, safeRect.top));
          line(safeRect.center, Offset(safeRect.right, safeRect.center.dy + safeRect.height * .08));
        } else if (shape == 'ring') {
          canvas.drawOval(safeRect, base);
          canvas.drawOval(safeRect.deflate(math.min(safeRect.width, safeRect.height) * .22), base);
        } else if (shape == 'crescent') {
          canvas.drawArc(safeRect, -.9, 4.8, false, base);
          canvas.drawArc(safeRect.shift(Offset(safeRect.width * .25, 0)), -.9, 4.8, false, base);
        } else {
          canvas.drawArc(safeRect, math.pi * 1.1, math.pi * 1.6, false, base);
        }
      case 'cross':
      case 'plus':
        line(Offset(safeRect.center.dx, safeRect.top), Offset(safeRect.center.dx, safeRect.bottom));
        line(Offset(safeRect.left, safeRect.center.dy), Offset(safeRect.right, safeRect.center.dy));
      case 'heart':
        final path = Path()
          ..moveTo(safeRect.center.dx, safeRect.bottom)
          ..cubicTo(safeRect.left - safeRect.width * .12, safeRect.center.dy,
              safeRect.left + safeRect.width * .08, safeRect.top,
              safeRect.center.dx, safeRect.top + safeRect.height * .24)
          ..cubicTo(safeRect.right - safeRect.width * .08, safeRect.top,
              safeRect.right + safeRect.width * .12, safeRect.center.dy,
              safeRect.center.dx, safeRect.bottom)
          ..close();
        canvas.drawPath(path, base);
      case 'cloud':
        final p = Path()
          ..moveTo(safeRect.left + safeRect.width * .12, safeRect.bottom)
          ..cubicTo(safeRect.left - safeRect.width * .05, safeRect.bottom - safeRect.height * .35, safeRect.left + safeRect.width * .12, safeRect.top + safeRect.height * .35, safeRect.center.dx - safeRect.width * .2, safeRect.top + safeRect.height * .4)
          ..cubicTo(safeRect.center.dx - safeRect.width * .1, safeRect.top - safeRect.height * .05, safeRect.center.dx + safeRect.width * .15, safeRect.top + safeRect.height * .08, safeRect.center.dx + safeRect.width * .2, safeRect.top + safeRect.height * .34)
          ..cubicTo(safeRect.right + safeRect.width * .05, safeRect.top + safeRect.height * .26, safeRect.right + safeRect.width * .12, safeRect.bottom - safeRect.height * .25, safeRect.right - safeRect.width * .1, safeRect.bottom)
          ..close();
        canvas.drawPath(p, base);
      case 'speechBubble':
      case 'callout':
        final p = Path()
          ..addRRect(RRect.fromRectAndRadius(safeRect.deflate(safeRect.width * .04), const Radius.circular(8)))
          ..moveTo(safeRect.left + safeRect.width * .28, safeRect.bottom - 2)
          ..lineTo(safeRect.left + safeRect.width * .18, safeRect.bottom + safeRect.height * .12)
          ..lineTo(safeRect.left + safeRect.width * .43, safeRect.bottom - 2);
        canvas.drawPath(p, base);
      case 'curlyBrace':
      case 'bracket':
        final x = shape == 'bracket' ? safeRect.left : safeRect.center.dx;
        final p = Path()
          ..moveTo(x + 12, safeRect.top)
          ..quadraticBezierTo(x, safeRect.top, x, safeRect.top + 12)
          ..lineTo(x, safeRect.center.dy - 10)
          ..quadraticBezierTo(x, safeRect.center.dy, x - 10, safeRect.center.dy)
          ..quadraticBezierTo(x, safeRect.center.dy, x, safeRect.center.dy + 10)
          ..lineTo(x, safeRect.bottom - 12)
          ..quadraticBezierTo(x, safeRect.bottom, x + 12, safeRect.bottom);
        canvas.drawPath(p, base);
      case 'cartesianPlane':
      case 'coordinateAxes':
      case 'ellipseAxes':
      case 'unitCircle':
        canvas.drawRect(safeRect, Paint()..color = base.color.withValues(alpha: .25)..style = PaintingStyle.stroke..strokeWidth = .8);
        final center = safeRect.center;
        line(Offset(safeRect.left, center.dy), Offset(safeRect.right, center.dy));
        line(Offset(center.dx, safeRect.bottom), Offset(center.dx, safeRect.top));
        _drawArrowHead(canvas, Offset(safeRect.left, center.dy), Offset(safeRect.right, center.dy), base);
        _drawArrowHead(canvas, Offset(center.dx, safeRect.bottom), Offset(center.dx, safeRect.top), base);
        if (shape == 'unitCircle') canvas.drawOval(safeRect.deflate(math.min(safeRect.width, safeRect.height) * .1), base);
        if (shape == 'ellipseAxes') canvas.drawOval(safeRect.deflate(math.min(safeRect.width, safeRect.height) * .2), base);
        if (shape == 'cartesianPlane') {
          for (double x = safeRect.left + 14; x < safeRect.right; x += 14) line(Offset(x, safeRect.top), Offset(x, safeRect.bottom), Paint()..color = base.color.withValues(alpha: .15)..strokeWidth = .5);
          for (double y = safeRect.top + 14; y < safeRect.bottom; y += 14) line(Offset(safeRect.left, y), Offset(safeRect.right, y), Paint()..color = base.color.withValues(alpha: .15)..strokeWidth = .5);
        }
      case 'sineWave':
      case 'waveform':
      case 'cubicGraph':
      case 'parabola':
      case 'exponentialGraph':
      case 'logarithmicGraph':
      case 'tangentGraph':
      case 'projectilePath':
        _drawGraph(canvas, safeRect, base, shape);
      case 'polarGraph':
      case 'vectorField':
        for (var i = 1; i <= 4; i++) {
          canvas.drawOval(safeRect.deflate(math.min(safeRect.width, safeRect.height) * i / 10), base);
        }
        for (var i = 0; i < 8; i++) {
          final a = i * math.pi / 4;
          line(
            Offset(safeRect.center.dx + math.cos(a) * safeRect.width * .48, safeRect.center.dy + math.sin(a) * safeRect.height * .48),
            Offset(safeRect.center.dx - math.cos(a) * safeRect.width * .48, safeRect.center.dy - math.sin(a) * safeRect.height * .48),
          );
        }
        if (shape == 'vectorField') {
          for (double x = safeRect.left + 18; x < safeRect.right; x += 34) {
            for (double y = safeRect.top + 18; y < safeRect.bottom; y += 34) {
              arrow(Offset(x - 5, y), Offset(x + 5, y - 3));
            }
          }
        }
      case 'histogram':
      case 'barChart':
        canvas.drawLine(Offset(safeRect.left, safeRect.bottom), Offset(safeRect.right, safeRect.bottom), base);
        canvas.drawLine(Offset(safeRect.left, safeRect.top), Offset(safeRect.left, safeRect.bottom), base);
        final bars = [0.35, 0.7, 0.53, 0.9, 0.46];
        final gap = safeRect.width * .035;
        final barWidth = (safeRect.width - gap * (bars.length + 1)) / bars.length;
        for (var i = 0; i < bars.length; i++) {
          final left = safeRect.left + gap + i * (barWidth + gap);
          canvas.drawRect(Rect.fromLTWH(left, safeRect.bottom - safeRect.height * bars[i], barWidth, safeRect.height * bars[i]), base);
        }
      case 'pieChart':
        canvas.drawCircle(safeRect.center, math.min(safeRect.width, safeRect.height) * .45, base);
        for (var i = 0; i < 4; i++) {
          final angle = -math.pi / 2 + i * math.pi / 2;
          line(safeRect.center, Offset(safeRect.center.dx + math.cos(angle) * safeRect.width * .45, safeRect.center.dy + math.sin(angle) * safeRect.height * .45));
        }
      case 'flowchartDecision':
        canvas.drawPath(polygon([
          Offset(safeRect.center.dx, safeRect.top),
          Offset(safeRect.right, safeRect.center.dy),
          Offset(safeRect.center.dx, safeRect.bottom),
          Offset(safeRect.left, safeRect.center.dy),
        ]), base);
        label('Decision');
      case 'flowchartTerminator':
        canvas.drawRRect(RRect.fromRectAndRadius(safeRect, Radius.circular(safeRect.height * .45)), base);
        label('Start / End');
      case 'flowchartInputOutput':
        canvas.drawPath(polygon([
          Offset(safeRect.left + safeRect.width * .16, safeRect.top),
          Offset(safeRect.right, safeRect.top),
          Offset(safeRect.right - safeRect.width * .16, safeRect.bottom),
          Offset(safeRect.left, safeRect.bottom),
        ]), base);
      case 'flowchartDocument':
        final p = Path()
          ..moveTo(safeRect.left, safeRect.top)
          ..lineTo(safeRect.right, safeRect.top)
          ..lineTo(safeRect.right, safeRect.bottom - 8)
          ..quadraticBezierTo(safeRect.center.dx, safeRect.bottom + 10, safeRect.left, safeRect.bottom - 8)
          ..close();
        canvas.drawPath(p, base);
      case 'flowchartDatabase':
        canvas.drawOval(Rect.fromLTWH(safeRect.left, safeRect.top, safeRect.width, safeRect.height * .22), base);
        canvas.drawLine(safeRect.topLeft, Offset(safeRect.left, safeRect.bottom - safeRect.height * .12), base);
        canvas.drawLine(safeRect.topRight, Offset(safeRect.right, safeRect.bottom - safeRect.height * .12), base);
        canvas.drawArc(Rect.fromLTWH(safeRect.left, safeRect.bottom - safeRect.height * .22, safeRect.width, safeRect.height * .22), 0, math.pi, false, base);
      case 'timeline':
        line(Offset(safeRect.left, safeRect.center.dy), Offset(safeRect.right, safeRect.center.dy));
        for (var i = 0; i < 5; i++) {
          canvas.drawCircle(Offset(safeRect.left + safeRect.width * i / 4, safeRect.center.dy), 4, Paint()..color = base.color..style = PaintingStyle.fill);
          line(Offset(safeRect.left + safeRect.width * i / 4, safeRect.center.dy - 5), Offset(safeRect.left + safeRect.width * i / 4, safeRect.top + 8));
        }
      case 'tableGrid':
        canvas.drawRect(safeRect, base);
        for (var i = 1; i < 4; i++) {
          line(Offset(safeRect.left + safeRect.width * i / 4, safeRect.top), Offset(safeRect.left + safeRect.width * i / 4, safeRect.bottom));
          line(Offset(safeRect.left, safeRect.top + safeRect.height * i / 4), Offset(safeRect.right, safeRect.top + safeRect.height * i / 4));
        }
      case 'checklist':
        for (var i = 0; i < 4; i++) {
          final y = safeRect.top + i * safeRect.height / 4 + 2;
          canvas.drawRect(Rect.fromLTWH(safeRect.left, y, safeRect.height / 7, safeRect.height / 7), base);
          line(Offset(safeRect.left + safeRect.height / 6, y + safeRect.height / 14), Offset(safeRect.right, y + safeRect.height / 14));
        }
      case 'convexLens':
      case 'concaveLens':
        final p = Path()
          ..moveTo(safeRect.center.dx, safeRect.top)
          ..quadraticBezierTo(safeRect.left - safeRect.width * (shape == 'convexLens' ? .25 : -.2), safeRect.center.dy, safeRect.center.dx, safeRect.bottom)
          ..quadraticBezierTo(safeRect.right + safeRect.width * (shape == 'convexLens' ? .25 : -.2), safeRect.center.dy, safeRect.center.dx, safeRect.top)
          ..close();
        canvas.drawPath(p, base);
      case 'planeMirror':
        line(Offset(safeRect.center.dx, safeRect.top), Offset(safeRect.center.dx, safeRect.bottom));
        for (var y = safeRect.top; y < safeRect.bottom; y += 10) {
          line(Offset(safeRect.center.dx, y), Offset(safeRect.center.dx + 8, y - 8));
        }
      case 'pulley':
        canvas.drawCircle(safeRect.center, math.min(safeRect.width, safeRect.height) * .28, base);
        line(Offset(safeRect.center.dx, safeRect.top), Offset(safeRect.center.dx, safeRect.bottom));
        line(Offset(safeRect.left, safeRect.center.dy), Offset(safeRect.right, safeRect.center.dy));
      case 'circuitResistor':
        _drawResistor(canvas, safeRect, base);
      case 'circuitBattery':
        line(Offset(safeRect.left, safeRect.center.dy), Offset(safeRect.center.dx - 10, safeRect.center.dy));
        line(Offset(safeRect.center.dx - 10, safeRect.top + safeRect.height * .22), Offset(safeRect.center.dx - 10, safeRect.bottom - safeRect.height * .22));
        line(Offset(safeRect.center.dx + 10, safeRect.top + safeRect.height * .35), Offset(safeRect.center.dx + 10, safeRect.bottom - safeRect.height * .35));
        line(Offset(safeRect.center.dx + 10, safeRect.center.dy), Offset(safeRect.right, safeRect.center.dy));
      case 'capacitor':
        line(Offset(safeRect.left, safeRect.center.dy), Offset(safeRect.center.dx - 4, safeRect.center.dy));
        line(Offset(safeRect.center.dx - 4, safeRect.top), Offset(safeRect.center.dx - 4, safeRect.bottom));
        line(Offset(safeRect.center.dx + 4, safeRect.top), Offset(safeRect.center.dx + 4, safeRect.bottom));
        line(Offset(safeRect.center.dx + 4, safeRect.center.dy), Offset(safeRect.right, safeRect.center.dy));
      case 'circuitSwitch':
        line(Offset(safeRect.left, safeRect.center.dy), Offset(safeRect.center.dx - 8, safeRect.center.dy));
        canvas.drawCircle(Offset(safeRect.center.dx - 8, safeRect.center.dy), 2.5, fill..color = base.color);
        line(Offset(safeRect.center.dx - 8, safeRect.center.dy), Offset(safeRect.center.dx + 8, safeRect.center.dy - safeRect.height * .24));
        canvas.drawCircle(Offset(safeRect.center.dx + 10, safeRect.center.dy), 2.5, fill..color = base.color);
        line(Offset(safeRect.center.dx + 10, safeRect.center.dy), Offset(safeRect.right, safeRect.center.dy));
      case 'circuitLamp':
        canvas.drawCircle(safeRect.center, math.min(safeRect.width, safeRect.height) * .28, base);
        line(safeRect.center - Offset(6, 6), safeRect.center + const Offset(6, 6));
        line(safeRect.center - const Offset(6, -6), safeRect.center + const Offset(6, -6));
      case 'molecule':
        final centers = [
          Offset(safeRect.left + safeRect.width * .23, safeRect.center.dy),
          Offset(safeRect.center.dx, safeRect.top + safeRect.height * .22),
          Offset(safeRect.right - safeRect.width * .23, safeRect.center.dy),
          Offset(safeRect.center.dx, safeRect.bottom - safeRect.height * .22),
        ];
        for (var i = 0; i < centers.length; i++) {
          line(centers[i], centers[(i + 1) % centers.length]);
          canvas.drawCircle(centers[i], math.min(safeRect.width, safeRect.height) * .1, base);
        }
      case 'beaker':
      case 'testTube':
      case 'conicalFlask':
        final p = Path()
          ..moveTo(safeRect.left + safeRect.width * .3, safeRect.top)
          ..lineTo(safeRect.left + safeRect.width * .7, safeRect.top)
          ..lineTo(safeRect.left + safeRect.width * .7, safeRect.top + safeRect.height * .22)
          ..lineTo(shape == 'beaker' ? safeRect.right : safeRect.right - safeRect.width * .1, safeRect.bottom)
          ..lineTo(shape == 'beaker' ? safeRect.left : safeRect.left + safeRect.width * .1, safeRect.bottom)
          ..lineTo(safeRect.left + safeRect.width * .3, safeRect.top + safeRect.height * .22)
          ..close();
        canvas.drawPath(p, base);
        line(Offset(safeRect.left + safeRect.width * .25, safeRect.top + safeRect.height * .52), Offset(safeRect.right - safeRect.width * .25, safeRect.top + safeRect.height * .52));
      case 'plantCell':
        canvas.drawRRect(RRect.fromRectAndRadius(safeRect, const Radius.circular(12)), base);
        canvas.drawOval(safeRect.deflate(safeRect.width * .15), base);
        canvas.drawCircle(safeRect.center, math.max(2, safeRect.width * .04), base);
      case 'dnaHelix':
        final p1 = Path()..moveTo(safeRect.left, safeRect.center.dy);
        final p2 = Path()..moveTo(safeRect.right, safeRect.center.dy);
        for (var i = 1; i <= 24; i++) {
          final t = i / 24;
          final x = safeRect.left + safeRect.width * t;
          final wave = math.sin(t * math.pi * 6) * safeRect.height * .35;
          p1.lineTo(x, safeRect.center.dy + wave);
          p2.lineTo(x, safeRect.center.dy - wave);
          if (i % 2 == 0) line(Offset(x, safeRect.center.dy + wave), Offset(x, safeRect.center.dy - wave), Paint()..color = base.color.withValues(alpha: .55)..strokeWidth = .8);
        }
        canvas.drawPath(p1, base);
        canvas.drawPath(p2, base);
      case 'neuron':
        final center = safeRect.center;
        canvas.drawCircle(center, math.min(safeRect.width, safeRect.height) * .12, base);
        for (var i = 0; i < 7; i++) {
          final a = i * math.pi * 2 / 7;
          final end = Offset(center.dx + math.cos(a) * safeRect.width * .4, center.dy + math.sin(a) * safeRect.height * .4);
          line(center, end);
          line(end, end + Offset(math.cos(a + .6) * 12, math.sin(a + .6) * 12));
          line(end, end + Offset(math.cos(a - .6) * 12, math.sin(a - .6) * 12));
        }
      case 'leaf':
        final p = Path()
          ..moveTo(safeRect.left, safeRect.bottom)
          ..quadraticBezierTo(safeRect.left, safeRect.top, safeRect.right, safeRect.top)
          ..quadraticBezierTo(safeRect.right, safeRect.bottom, safeRect.left, safeRect.bottom)
          ..close();
        canvas.drawPath(p, base);
        line(safeRect.bottomLeft, safeRect.topRight);
      case 'microscope':
        final p = Path()
          ..moveTo(safeRect.left + safeRect.width * .38, safeRect.top)
          ..lineTo(safeRect.left + safeRect.width * .65, safeRect.top + safeRect.height * .08)
          ..lineTo(safeRect.center.dx + safeRect.width * .12, safeRect.center.dy)
          ..lineTo(safeRect.center.dx, safeRect.center.dy + safeRect.height * .12)
          ..lineTo(safeRect.center.dx - safeRect.width * .14, safeRect.center.dy - safeRect.height * .12)
          ..moveTo(safeRect.center.dx, safeRect.center.dy)
          ..lineTo(safeRect.center.dx - safeRect.width * .2, safeRect.bottom - safeRect.height * .16)
          ..lineTo(safeRect.right - safeRect.width * .1, safeRect.bottom - safeRect.height * .16)
          ..moveTo(safeRect.left + safeRect.width * .12, safeRect.bottom)
          ..lineTo(safeRect.right, safeRect.bottom);
        canvas.drawPath(p, base);
      case 'ruler':
        canvas.drawRect(safeRect, base);
        for (var i = 0; i <= 10; i++) {
          final x = safeRect.left + safeRect.width * i / 10;
          line(Offset(x, safeRect.top), Offset(x, safeRect.top + safeRect.height * (i.isEven ? .6 : .35)));
        }
      case 'compass':
        canvas.drawCircle(safeRect.center, math.min(safeRect.width, safeRect.height) * .45, base);
        line(safeRect.center, Offset(safeRect.center.dx, safeRect.top));
        line(safeRect.center, Offset(safeRect.right, safeRect.center.dy));
      case 'protractor':
        canvas.drawArc(safeRect, math.pi, math.pi, false, base);
        line(safeRect.bottomLeft, safeRect.bottomRight);
        for (var i = 0; i <= 18; i++) {
          final a = math.pi + math.pi * i / 18;
          final r = math.min(safeRect.width, safeRect.height) * .45;
          final inner = r - (i % 3 == 0 ? 10 : 5);
          line(Offset(safeRect.center.dx + math.cos(a) * inner, safeRect.center.dy + math.sin(a) * inner), Offset(safeRect.center.dx + math.cos(a) * r, safeRect.center.dy + math.sin(a) * r));
        }
      case 'spring':
        final p = Path()..moveTo(safeRect.left, safeRect.center.dy);
        for (var i = 1; i <= 12; i++) {
          p.lineTo(safeRect.left + safeRect.width * i / 12, safeRect.center.dy + (i.isEven ? -1 : 1) * safeRect.height * .35);
        }
        p.lineTo(safeRect.right, safeRect.center.dy);
        canvas.drawPath(p, base);
      case 'lever':
      case 'inclinedPlane':
        line(safeRect.bottomLeft, safeRect.topRight);
        canvas.drawPath(polygon([
          Offset(safeRect.center.dx, safeRect.bottom),
          Offset(safeRect.center.dx - safeRect.width * .12, safeRect.bottom - safeRect.height * .15),
          Offset(safeRect.center.dx + safeRect.width * .12, safeRect.bottom - safeRect.height * .15),
        ]), base);
      case 'gear':
        final center = safeRect.center;
        final radius = math.min(safeRect.width, safeRect.height) * .42;
        final vertices = <Offset>[];
        for (var i = 0; i < 24; i++) {
          final r = radius * (i % 2 == 0 ? 1 : .82);
          final a = i * math.pi / 12;
          vertices.add(Offset(center.dx + math.cos(a) * r, center.dy + math.sin(a) * r));
        }
        canvas.drawPath(polygon(vertices), base);
        canvas.drawCircle(center, radius * .26, base);
      case 'magnet':
        final p = Path()
          ..moveTo(safeRect.left, safeRect.top)
          ..lineTo(safeRect.left, safeRect.bottom - safeRect.height * .2)
          ..quadraticBezierTo(safeRect.center.dx, safeRect.bottom + safeRect.height * .15, safeRect.right, safeRect.bottom - safeRect.height * .2)
          ..lineTo(safeRect.right, safeRect.top);
        canvas.drawPath(p, base);
        line(Offset(safeRect.left, safeRect.top + safeRect.height * .18), Offset(safeRect.left + safeRect.width * .25, safeRect.top + safeRect.height * .18));
        line(Offset(safeRect.right - safeRect.width * .25, safeRect.top + safeRect.height * .18), Offset(safeRect.right, safeRect.top + safeRect.height * .18));
      case 'thermometer':
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(safeRect.center.dx, safeRect.center.dy - 5), width: safeRect.width * .28, height: safeRect.height * .7), const Radius.circular(8)), base);
        canvas.drawCircle(Offset(safeRect.center.dx, safeRect.bottom - safeRect.height * .08), math.min(safeRect.width, safeRect.height) * .1, base);
        line(Offset(safeRect.center.dx, safeRect.center.dy + safeRect.height * .2), Offset(safeRect.center.dx, safeRect.bottom - safeRect.height * .12));
      case 'stopwatch':
        canvas.drawCircle(safeRect.center, math.min(safeRect.width, safeRect.height) * .42, base);
        canvas.drawRect(Rect.fromCenter(center: Offset(safeRect.center.dx, safeRect.top + 4), width: safeRect.width * .18, height: 8), base);
        line(safeRect.center, Offset(safeRect.center.dx, safeRect.top + safeRect.height * .18));
        line(safeRect.center, Offset(safeRect.center.dx + safeRect.width * .2, safeRect.center.dy));
      case 'heptagon':
        canvas.drawPath(polygon(regularPolygon(7)), base);
      case 'octagon':
        canvas.drawPath(polygon(regularPolygon(8)), base);
      case 'nonagon':
        canvas.drawPath(polygon(regularPolygon(9)), base);
      case 'decagon':
        canvas.drawPath(polygon(regularPolygon(10)), base);
      case 'hexagram':
        canvas.drawPath(polygon([
          Offset(safeRect.center.dx, safeRect.top),
          Offset(safeRect.center.dx + safeRect.width * .16, safeRect.center.dy - safeRect.height * .12),
          safeRect.topRight,
          Offset(safeRect.center.dx + safeRect.width * .18, safeRect.center.dy + safeRect.height * .1),
          Offset(safeRect.center.dx + safeRect.width * .3, safeRect.bottom),
          safeRect.center,
          Offset(safeRect.center.dx - safeRect.width * .3, safeRect.bottom),
          Offset(safeRect.center.dx - safeRect.width * .18, safeRect.center.dy + safeRect.height * .1),
          safeRect.topLeft,
          Offset(safeRect.center.dx - safeRect.width * .16, safeRect.center.dy - safeRect.height * .12),
        ]), base);
      case 'pentagram':
        final vertices = <Offset>[];
        for (var i = 0; i < 10; i++) {
          final radius = i.isEven ? .48 : .2;
          final angle = -math.pi / 2 + i * math.pi / 5;
          vertices.add(Offset(safeRect.center.dx + math.cos(angle) * safeRect.width * radius, safeRect.center.dy + math.sin(angle) * safeRect.height * radius));
        }
        canvas.drawPath(polygon(vertices), base);
      case 'arrowUp':
        arrow(Offset(safeRect.center.dx, safeRect.bottom), Offset(safeRect.center.dx, safeRect.top));
      case 'arrowDown':
        arrow(Offset(safeRect.center.dx, safeRect.top), Offset(safeRect.center.dx, safeRect.bottom));
      case 'arrowLeft':
        arrow(Offset(safeRect.right, safeRect.center.dy), Offset(safeRect.left, safeRect.center.dy));
      case 'arrowRight':
        arrow(Offset(safeRect.left, safeRect.center.dy), Offset(safeRect.right, safeRect.center.dy));
      case 'doubleArrow':
        arrow(start, end, both: true);
      case 'curvedArrow':
        final path = Path()
          ..moveTo(safeRect.left, safeRect.bottom)
          ..quadraticBezierTo(safeRect.center.dx, safeRect.top, safeRect.right, safeRect.center.dy);
        canvas.drawPath(path, base);
        _drawArrowHead(canvas, Offset(safeRect.center.dx, safeRect.top), safeRect.centerRight, base);
      case 'zigzag':
        final path = Path()..moveTo(safeRect.left, safeRect.center.dy);
        for (var i = 1; i <= 8; i++) {
          path.lineTo(safeRect.left + safeRect.width * i / 8, safeRect.center.dy + (i.isEven ? -1 : 1) * safeRect.height * .35);
        }
        canvas.drawPath(path, base);
      case 'lightningBolt':
        canvas.drawPath(polygon([
          Offset(safeRect.left + safeRect.width * .55, safeRect.top),
          Offset(safeRect.left + safeRect.width * .18, safeRect.center.dy),
          Offset(safeRect.center.dx + safeRect.width * .02, safeRect.center.dy),
          Offset(safeRect.left + safeRect.width * .38, safeRect.bottom),
          Offset(safeRect.right - safeRect.width * .12, safeRect.top + safeRect.height * .38),
          Offset(safeRect.center.dx + safeRect.width * .02, safeRect.top + safeRect.height * .4),
        ]), base);
      case 'crescentMoon':
        canvas.drawCircle(safeRect.center, math.min(safeRect.width, safeRect.height) * .42, base);
        canvas.drawCircle(Offset(safeRect.center.dx + safeRect.width * .2, safeRect.center.dy - safeRect.height * .1), math.min(safeRect.width, safeRect.height) * .37, Paint()..color = stroke.pen.color.withValues(alpha: .015)..style = PaintingStyle.fill);
        canvas.drawArc(safeRect, -math.pi * .45, math.pi * 1.65, false, base);
      case 'sunSymbol':
        canvas.drawCircle(safeRect.center, math.min(safeRect.width, safeRect.height) * .22, base);
        for (var i = 0; i < 8; i++) {
          final angle = i * math.pi / 4;
          final a = Offset(safeRect.center.dx + math.cos(angle) * safeRect.width * .28, safeRect.center.dy + math.sin(angle) * safeRect.height * .28);
          final b = Offset(safeRect.center.dx + math.cos(angle) * safeRect.width * .45, safeRect.center.dy + math.sin(angle) * safeRect.height * .45);
          line(a, b);
        }
      case 'doubleChevron':
        for (var i = 0; i < 2; i++) {
          final dx = safeRect.width * i * .24;
          canvas.drawPath(polygon([
            Offset(safeRect.left + dx, safeRect.top),
            Offset(safeRect.center.dx + dx, safeRect.center.dy),
            Offset(safeRect.left + dx, safeRect.bottom),
          ], close: false), base);
        }
      case 'chevron':
        canvas.drawPath(polygon([
          Offset(safeRect.left, safeRect.top),
          safeRect.centerRight,
          Offset(safeRect.left, safeRect.bottom),
        ], close: false), base);
      case 'bracketLeft':
      case 'braceLeft':
        final path = Path()
          ..moveTo(safeRect.right, safeRect.top)
          ..lineTo(safeRect.left + safeRect.width * .25, safeRect.top)
          ..lineTo(safeRect.left + safeRect.width * .25, safeRect.center.dy)
          ..lineTo(safeRect.left, safeRect.center.dy)
          ..lineTo(safeRect.left + safeRect.width * .25, safeRect.center.dy)
          ..lineTo(safeRect.left + safeRect.width * .25, safeRect.bottom)
          ..lineTo(safeRect.right, safeRect.bottom);
        canvas.drawPath(path, base);
      case 'bracketRight':
      case 'braceRight':
        final path = Path()
          ..moveTo(safeRect.left, safeRect.top)
          ..lineTo(safeRect.right - safeRect.width * .25, safeRect.top)
          ..lineTo(safeRect.right - safeRect.width * .25, safeRect.center.dy)
          ..lineTo(safeRect.right, safeRect.center.dy)
          ..lineTo(safeRect.right - safeRect.width * .25, safeRect.center.dy)
          ..lineTo(safeRect.right - safeRect.width * .25, safeRect.bottom)
          ..lineTo(safeRect.left, safeRect.bottom);
        canvas.drawPath(path, base);
      case 'equalsSign':
        line(Offset(safeRect.left, safeRect.center.dy - safeRect.height * .12), Offset(safeRect.right, safeRect.center.dy - safeRect.height * .12));
        line(Offset(safeRect.left, safeRect.center.dy + safeRect.height * .12), Offset(safeRect.right, safeRect.center.dy + safeRect.height * .12));
      case 'notEqualSign':
        line(Offset(safeRect.left, safeRect.center.dy - safeRect.height * .12), Offset(safeRect.right, safeRect.center.dy - safeRect.height * .12));
        line(Offset(safeRect.left, safeRect.center.dy + safeRect.height * .12), Offset(safeRect.right, safeRect.center.dy + safeRect.height * .12));
        line(Offset(safeRect.left + safeRect.width * .2, safeRect.bottom), Offset(safeRect.right - safeRect.width * .2, safeRect.top));
      case 'approximateEqual':
        label('≈');
      case 'greaterThanSign':
        label('>');
      case 'lessThanSign':
        label('<');
      case 'plusMinus':
        label('±');
      case 'infinitySymbol':
        label('∞');
      case 'integralSymbol':
        label('∫');
      case 'sigmaSymbol':
      case 'summationSymbol':
        label('Σ');
      case 'deltaSymbol':
        label('Δ');
      case 'thetaSymbol':
        label('θ');
      case 'omegaSymbol':
        label('Ω');
      case 'squareRootSymbol':
        label('√');
      case 'fractionBar':
        line(Offset(safeRect.left, safeRect.center.dy), Offset(safeRect.right, safeRect.center.dy));
      case 'coordinatePoint':
        canvas.drawLine(safeRect.topLeft, safeRect.bottomRight, _axisPaint(base));
        canvas.drawLine(safeRect.bottomLeft, safeRect.topRight, _axisPaint(base));
        canvas.drawCircle(safeRect.center, math.max(base.strokeWidth * 2.5, 3).toDouble(), base..style = PaintingStyle.fill);
      case 'linearGraph':
      case 'circleGraph':
        _drawGraph(canvas, safeRect, base, shape);
      case 'scatterPlot':
        canvas.drawLine(Offset(safeRect.left, safeRect.center.dy), Offset(safeRect.right, safeRect.center.dy), _axisPaint(base));
        canvas.drawLine(Offset(safeRect.center.dx, safeRect.top), Offset(safeRect.center.dx, safeRect.bottom), _axisPaint(base));
        for (final fraction in const [Offset(.12, .72), Offset(.24, .51), Offset(.38, .6), Offset(.52, .32), Offset(.67, .42), Offset(.8, .22)]) {
          canvas.drawCircle(Offset(safeRect.left + fraction.dx * safeRect.width, safeRect.top + fraction.dy * safeRect.height), math.max(2, base.strokeWidth * 1.3).toDouble(), base..style = PaintingStyle.fill);
        }
      case 'flowchartPreparation':
        canvas.drawPath(polygon([
          Offset(safeRect.left + safeRect.width * .2, safeRect.top),
          Offset(safeRect.right - safeRect.width * .2, safeRect.top),
          Offset(safeRect.right, safeRect.center.dy),
          Offset(safeRect.right - safeRect.width * .2, safeRect.bottom),
          Offset(safeRect.left + safeRect.width * .2, safeRect.bottom),
          Offset(safeRect.left, safeRect.center.dy),
        ]), base);
      case 'flowchartManualInput':
        canvas.drawPath(polygon([
          Offset(safeRect.left + safeRect.width * .18, safeRect.top),
          safeRect.topRight,
          safeRect.bottomRight,
          safeRect.bottomLeft,
        ]), base);
      case 'flowchartDelay':
        canvas.drawRect(safeRect, base);
        canvas.drawArc(safeRect, -math.pi / 2, math.pi, false, base);
      case 'flowchartOffPage':
        canvas.drawPath(polygon([
          safeRect.topLeft,
          safeRect.topRight,
          Offset(safeRect.right, safeRect.bottom - safeRect.height * .28),
          Offset(safeRect.center.dx, safeRect.bottom),
          Offset(safeRect.left, safeRect.bottom - safeRect.height * .28),
        ]), base);
      case 'databaseCylinder':
        canvas.drawRect(Rect.fromLTWH(safeRect.left, safeRect.top + safeRect.height * .1, safeRect.width, safeRect.height * .8), base);
        canvas.drawOval(Rect.fromLTWH(safeRect.left, safeRect.top, safeRect.width, safeRect.height * .2), base);
        canvas.drawArc(Rect.fromLTWH(safeRect.left, safeRect.bottom - safeRect.height * .2, safeRect.width, safeRect.height * .2), 0, math.pi, false, base);
      case 'documentStack':
        canvas.drawRect(safeRect.deflate(safeRect.width * .1), base);
        canvas.drawRect(safeRect.deflate(safeRect.width * .05).shift(Offset(0, -safeRect.height * .06)), base);
        canvas.drawRect(safeRect, base);
      case 'serverRack':
        canvas.drawRRect(RRect.fromRectAndRadius(safeRect, const Radius.circular(4)), base);
        for (var i = 1; i <= 3; i++) {
          final y = safeRect.top + safeRect.height * i / 4;
          line(Offset(safeRect.left + 4, y), Offset(safeRect.right - 4, y));
          canvas.drawCircle(Offset(safeRect.right - 7, y - safeRect.height * .08), 1.5, base);
        }
      case 'networkNode':
        for (final fraction in const [Offset(.2,.5), Offset(.5,.25), Offset(.8,.5), Offset(.5,.8)]) {
          final point = Offset(safeRect.left + fraction.dx * safeRect.width, safeRect.top + fraction.dy * safeRect.height);
          line(safeRect.center, point);
          canvas.drawCircle(point, math.max(2, base.strokeWidth * 2).toDouble(), base..style = PaintingStyle.fill);
        }
        canvas.drawCircle(safeRect.center, math.max(3, base.strokeWidth * 2.5).toDouble(), base..style = PaintingStyle.fill);
      case 'batterySymbol':
        canvas.drawRect(Rect.fromLTWH(safeRect.left + safeRect.width * .1, safeRect.top + safeRect.height * .18, safeRect.width * .8, safeRect.height * .64), base);
        line(Offset(safeRect.center.dx - safeRect.width * .1, safeRect.center.dy), Offset(safeRect.center.dx + safeRect.width * .1, safeRect.center.dy));
        line(Offset(safeRect.center.dx, safeRect.center.dy - safeRect.height * .12), Offset(safeRect.center.dx, safeRect.center.dy + safeRect.height * .12));
      case 'groundSymbol':
        line(Offset(safeRect.center.dx, safeRect.top), Offset(safeRect.center.dx, safeRect.center.dy));
        for (var i = 0; i < 3; i++) {
          final y = safeRect.center.dy + i * safeRect.height * .1;
          final half = safeRect.width * (.24 - i * .065);
          line(Offset(safeRect.center.dx - half, y), Offset(safeRect.center.dx + half, y));
        }
      case 'voltageSource':
      case 'currentSource':
        canvas.drawCircle(safeRect.center, math.min(safeRect.width, safeRect.height) * .32, base);
        line(Offset(safeRect.center.dx, safeRect.top), Offset(safeRect.center.dx, safeRect.center.dy - safeRect.height * .32));
        line(Offset(safeRect.center.dx, safeRect.center.dy + safeRect.height * .32), Offset(safeRect.center.dx, safeRect.bottom));
        label(shape == 'voltageSource' ? '+' : 'I');
      case 'inductorSymbol':
        final step = safeRect.width / 6;
        for (var i = 0; i < 4; i++) {
          canvas.drawArc(Rect.fromLTWH(safeRect.left + step * (i + .4), safeRect.center.dy - safeRect.height * .24, step * 1.2, safeRect.height * .48), math.pi, math.pi, false, base);
        }
        line(safeRect.topLeft, Offset(safeRect.left + step * .4, safeRect.center.dy));
        line(Offset(safeRect.right - step * .4, safeRect.center.dy), safeRect.topRight);
      case 'diodeSymbol':
        line(safeRect.centerLeft, safeRect.centerRight);
        canvas.drawPath(polygon([
          Offset(safeRect.left + safeRect.width * .25, safeRect.top + safeRect.height * .2),
          Offset(safeRect.left + safeRect.width * .25, safeRect.bottom - safeRect.height * .2),
          Offset(safeRect.right - safeRect.width * .22, safeRect.center.dy),
        ]), base);
        line(Offset(safeRect.right - safeRect.width * .22, safeRect.top + safeRect.height * .12), Offset(safeRect.right - safeRect.width * .22, safeRect.bottom - safeRect.height * .12));
      case 'matrixGrid':
        canvas.drawRect(safeRect, base);
        for (var i = 1; i < 3; i++) {
          final x = safeRect.left + safeRect.width * i / 3;
          final y = safeRect.top + safeRect.height * i / 3;
          line(Offset(x, safeRect.top), Offset(x, safeRect.bottom));
          line(Offset(safeRect.left, y), Offset(safeRect.right, y));
        }
      case 'derivativeSymbol':
        label('d/dx');
      case 'angle':
        final vertex = Offset(
          safeRect.left + safeRect.width * .18,
          safeRect.bottom - safeRect.height * .12,
        );
        final rayEndA = Offset(
          safeRect.left + safeRect.width * .18,
          safeRect.top + safeRect.height * .15,
        );
        final rayEndB = Offset(
          safeRect.right - safeRect.width * .12,
          safeRect.top + safeRect.height * .15,
        );
        line(vertex, rayEndA);
        line(vertex, rayEndB);
        final radius = math.min(safeRect.width, safeRect.height) * .28;
        canvas.drawArc(
          Rect.fromCircle(center: vertex, radius: radius),
          -math.pi * .75,
          math.pi * .5,
          false,
          base,
        );
      case 'lineChart':
      case 'areaChart':
      case 'stackedBarChart':
        line(Offset(safeRect.left + safeRect.width * .12, safeRect.top), Offset(safeRect.left + safeRect.width * .12, safeRect.bottom));
        line(Offset(safeRect.left + safeRect.width * .12, safeRect.bottom), safeRect.bottomRight);
        if (shape == 'stackedBarChart') {
          for (var i = 0; i < 4; i++) {
            final w = safeRect.width * .13;
            final x = safeRect.left + safeRect.width * (.2 + i * .18);
            final h1 = safeRect.height * (.25 + (i % 3) * .08);
            final h2 = safeRect.height * (.18 + ((i + 1) % 3) * .07);
            canvas.drawRect(Rect.fromLTWH(x, safeRect.bottom - h1, w, h1), base);
            canvas.drawRect(Rect.fromLTWH(x, safeRect.bottom - h1 - h2, w, h2), base);
          }
        } else {
          final pts = <Offset>[
            Offset(safeRect.left + safeRect.width * .16, safeRect.bottom - safeRect.height * .2),
            Offset(safeRect.left + safeRect.width * .34, safeRect.top + safeRect.height * .42),
            Offset(safeRect.left + safeRect.width * .52, safeRect.top + safeRect.height * .58),
            Offset(safeRect.left + safeRect.width * .72, safeRect.top + safeRect.height * .2),
            Offset(safeRect.right - safeRect.width * .08, safeRect.top + safeRect.height * .3),
          ];
          final graph = polygon(pts, close: shape == 'areaChart');
          if (shape == 'areaChart') {
            canvas.drawPath(graph, fill..color = stroke.pen.color.withValues(alpha: .12));
          }
          canvas.drawPath(graph, base);
          for (final point in pts) {
            canvas.drawCircle(point, math.max(2, base.strokeWidth * 1.3).toDouble(), fill..color = stroke.pen.color);
          }
        }
      case 'donutChart':
        canvas.drawOval(safeRect, base);
        canvas.drawArc(safeRect, -math.pi / 2, math.pi * .78, false, base..strokeWidth = base.strokeWidth * 2);
        canvas.drawOval(
          Rect.fromCenter(center: safeRect.center, width: safeRect.width * .42, height: safeRect.height * .42),
          Paint()..color = stroke.pen.color.withValues(alpha: .15)..style = PaintingStyle.fill,
        );
      case 'networkGraph':
        final nodes = <Offset>[
          Offset(safeRect.left + safeRect.width * .18, safeRect.top + safeRect.height * .3),
          Offset(safeRect.left + safeRect.width * .5, safeRect.top + safeRect.height * .12),
          Offset(safeRect.right - safeRect.width * .15, safeRect.top + safeRect.height * .35),
          Offset(safeRect.left + safeRect.width * .28, safeRect.bottom - safeRect.height * .16),
          Offset(safeRect.right - safeRect.width * .22, safeRect.bottom - safeRect.height * .2),
        ];
        for (final pair in const [(0, 1), (1, 2), (0, 3), (1, 3), (1, 4), (2, 4), (3, 4)]) {
          line(nodes[pair.$1], nodes[pair.$2]);
        }
        for (final node in nodes) {
          canvas.drawCircle(node, math.max(3, base.strokeWidth * 1.8).toDouble(), fill..color = stroke.pen.color);
        }
      case 'vennDiagram':
        canvas.drawCircle(Offset(safeRect.left + safeRect.width * .38, safeRect.center.dy), safeRect.width * .28, base);
        canvas.drawCircle(Offset(safeRect.left + safeRect.width * .62, safeRect.center.dy), safeRect.width * .28, base);
        canvas.drawCircle(Offset(safeRect.center.dx, safeRect.top + safeRect.height * .34), safeRect.width * .28, base);
      case 'cloudSymbol':
        final cloud = Path()
          ..moveTo(safeRect.left + safeRect.width * .15, safeRect.center.dy + safeRect.height * .2)
          ..cubicTo(safeRect.left - safeRect.width * .02, safeRect.center.dy, safeRect.left + safeRect.width * .12, safeRect.top + safeRect.height * .28, safeRect.left + safeRect.width * .34, safeRect.top + safeRect.height * .34)
          ..cubicTo(safeRect.left + safeRect.width * .38, safeRect.top - safeRect.height * .02, safeRect.right - safeRect.width * .16, safeRect.top + safeRect.height * .02, safeRect.right - safeRect.width * .18, safeRect.center.dy + safeRect.height * .04)
          ..cubicTo(safeRect.right + safeRect.width * .02, safeRect.center.dy + safeRect.height * .08, safeRect.right - safeRect.width * .02, safeRect.bottom - safeRect.height * .06, safeRect.right - safeRect.width * .25, safeRect.bottom - safeRect.height * .1)
          ..lineTo(safeRect.left + safeRect.width * .18, safeRect.bottom - safeRect.height * .1)
          ..close();
        canvas.drawPath(cloud, base);
      case 'networkLink':
        line(Offset(safeRect.left + safeRect.width * .16, safeRect.center.dy), Offset(safeRect.right - safeRect.width * .16, safeRect.center.dy));
        canvas.drawCircle(Offset(safeRect.left + safeRect.width * .16, safeRect.center.dy), math.max(3, base.strokeWidth * 2).toDouble(), base);
        canvas.drawCircle(Offset(safeRect.right - safeRect.width * .16, safeRect.center.dy), math.max(3, base.strokeWidth * 2).toDouble(), base);
      case 'wifiSymbol':
        canvas.drawArc(safeRect, -math.pi * .78, math.pi * .56, false, base);
        canvas.drawArc(safeRect.deflate(safeRect.width * .18), -math.pi * .75, math.pi * .5, false, base);
        canvas.drawArc(safeRect.deflate(safeRect.width * .36), -math.pi * .7, math.pi * .4, false, base);
        canvas.drawCircle(Offset(safeRect.center.dx, safeRect.bottom - safeRect.height * .12), math.max(2, base.strokeWidth).toDouble(), fill..color = stroke.pen.color);
      case 'transistorSymbol':
        canvas.drawCircle(safeRect.center, math.min(safeRect.width, safeRect.height) * .32, base);
        line(Offset(safeRect.left, safeRect.center.dy), Offset(safeRect.center.dx - safeRect.width * .12, safeRect.center.dy));
        line(Offset(safeRect.center.dx, safeRect.top), Offset(safeRect.center.dx, safeRect.center.dy - safeRect.height * .32));
        arrow(Offset(safeRect.center.dx - safeRect.width * .1, safeRect.center.dy + safeRect.height * .1), Offset(safeRect.center.dx + safeRect.width * .3, safeRect.bottom));
      case 'logicAnd':
      case 'logicOr':
      case 'logicNot':
      case 'logicXor':
        if (shape == 'logicNot') {
          canvas.drawPath(polygon([safeRect.topLeft, safeRect.bottomLeft, safeRect.centerRight]), base);
          canvas.drawCircle(Offset(safeRect.right - safeRect.width * .07, safeRect.center.dy), safeRect.width * .06, base);
        } else {
          final gate = Path()..moveTo(safeRect.left, safeRect.top)..lineTo(safeRect.center.dx, safeRect.top);
          if (shape == 'logicOr' || shape == 'logicXor') {
            gate.quadraticBezierTo(safeRect.right, safeRect.top + safeRect.height * .2, safeRect.right, safeRect.center.dy);
            gate.quadraticBezierTo(safeRect.right, safeRect.bottom - safeRect.height * .2, safeRect.center.dx, safeRect.bottom);
          } else {
            gate.lineTo(safeRect.right - safeRect.width * .15, safeRect.top);
            gate.quadraticBezierTo(safeRect.right + safeRect.width * .2, safeRect.center.dy, safeRect.right - safeRect.width * .15, safeRect.bottom);
            gate.lineTo(safeRect.left, safeRect.bottom);
          }
          gate.close();
          canvas.drawPath(gate, base);
          line(Offset(safeRect.left, safeRect.top + safeRect.height * .3), Offset(safeRect.left + safeRect.width * .12, safeRect.top + safeRect.height * .3));
          line(Offset(safeRect.left, safeRect.bottom - safeRect.height * .3), Offset(safeRect.left + safeRect.width * .12, safeRect.bottom - safeRect.height * .3));
        }
      case 'gearTrain':
        canvas.drawCircle(Offset(safeRect.left + safeRect.width * .33, safeRect.center.dy), safeRect.height * .22, base);
        canvas.drawCircle(Offset(safeRect.left + safeRect.width * .67, safeRect.center.dy), safeRect.height * .22, base);
        canvas.drawCircle(Offset(safeRect.left + safeRect.width * .33, safeRect.center.dy), safeRect.height * .07, base);
        canvas.drawCircle(Offset(safeRect.left + safeRect.width * .67, safeRect.center.dy), safeRect.height * .07, base);
      case 'pendulum':
        line(Offset(safeRect.center.dx, safeRect.top), Offset(safeRect.right - safeRect.width * .18, safeRect.bottom - safeRect.height * .15));
        canvas.drawCircle(Offset(safeRect.right - safeRect.width * .18, safeRect.bottom - safeRect.height * .15), math.min(safeRect.width, safeRect.height) * .12, base);
      case 'weightSymbol':
        line(Offset(safeRect.center.dx, safeRect.top), Offset(safeRect.center.dx, safeRect.bottom - safeRect.height * .16));
        arrow(Offset(safeRect.center.dx, safeRect.bottom - safeRect.height * .22), Offset(safeRect.center.dx, safeRect.bottom));
      case 'electricField':
      case 'magneticField':
        for (var i = 1; i <= 3; i++) {
          final r = Rect.fromCenter(center: safeRect.center, width: safeRect.width * i / 3, height: safeRect.height * i / 3);
          canvas.drawOval(r, base);
        }
        if (shape == 'electricField') {
          arrow(Offset(safeRect.center.dx, safeRect.top + 4), Offset(safeRect.center.dx, safeRect.top + safeRect.height * .18));
          arrow(Offset(safeRect.right - 4, safeRect.center.dy), Offset(safeRect.right - safeRect.width * .18, safeRect.center.dy));
        }
      case 'waveFront':
        for (var i = 0; i < 4; i++) {
          final r = safeRect.deflate(i * safeRect.width * .1);
          canvas.drawArc(r, -math.pi / 2, math.pi, false, base);
        }
      case 'photonSymbol':
        final photon = Path()..moveTo(safeRect.left, safeRect.center.dy);
        for (var i = 1; i <= 8; i++) {
          photon.lineTo(safeRect.left + safeRect.width * i / 8, safeRect.center.dy + (i.isEven ? -1 : 1) * safeRect.height * .22);
        }
        canvas.drawPath(photon, base);
      case 'atomNucleus':
      case 'electronOrbit':
        canvas.drawOval(safeRect, base);
        canvas.drawOval(Rect.fromCenter(center: safeRect.center, width: safeRect.width * .48, height: safeRect.height), base);
        canvas.drawCircle(Offset(safeRect.center.dx + safeRect.width * .3, safeRect.center.dy), math.max(2.5, base.strokeWidth * 1.6).toDouble(), fill..color = stroke.pen.color);
        if (shape == 'atomNucleus') {
          for (var i = 0; i < 5; i++) {
            final point = Offset(safeRect.center.dx + (i - 2) * safeRect.width * .045, safeRect.center.dy + (i.isEven ? -1 : 1) * safeRect.height * .045);
            canvas.drawCircle(point, math.max(2, base.strokeWidth * 1.3).toDouble(), base);
          }
        }
      case 'ionSymbol':
        canvas.drawCircle(safeRect.center, math.min(safeRect.width, safeRect.height) * .38, base);
        label('±');
      case 'ionicBond':
      case 'covalentBond':
        canvas.drawCircle(Offset(safeRect.left + safeRect.width * .3, safeRect.center.dy), safeRect.height * .18, base);
        canvas.drawCircle(Offset(safeRect.left + safeRect.width * .7, safeRect.center.dy), safeRect.height * .18, base);
        if (shape == 'ionicBond') {
          label('+   −');
        } else {
          for (var i = -1; i <= 1; i++) {
            canvas.drawCircle(Offset(safeRect.center.dx + i * safeRect.width * .045, safeRect.center.dy), math.max(1.2, base.strokeWidth * .7).toDouble(), fill..color = stroke.pen.color);
          }
        }
      case 'moleculeChain':
      case 'organicChain':
        final points = <Offset>[
          Offset(safeRect.left + safeRect.width * .1, safeRect.center.dy),
          Offset(safeRect.left + safeRect.width * .28, safeRect.top + safeRect.height * .24),
          Offset(safeRect.left + safeRect.width * .48, safeRect.center.dy),
          Offset(safeRect.left + safeRect.width * .68, safeRect.top + safeRect.height * .24),
          Offset(safeRect.right - safeRect.width * .1, safeRect.center.dy),
        ];
        for (var i = 0; i < points.length - 1; i++) line(points[i], points[i + 1]);
        if (shape == 'moleculeChain') {
          for (final point in points) canvas.drawCircle(point, math.max(2.2, base.strokeWidth * 1.4).toDouble(), fill..color = stroke.pen.color);
        } else {
          label('C');
        }
      case 'crystalLattice':
        for (var row = 0; row < 3; row++) {
          for (var col = 0; col < 4; col++) {
            final point = Offset(safeRect.left + safeRect.width * (.12 + col * .25), safeRect.top + safeRect.height * (.2 + row * .3));
            canvas.drawCircle(point, math.max(2, base.strokeWidth * 1.2).toDouble(), fill..color = stroke.pen.color);
            if (col > 0) line(point, Offset(point.dx - safeRect.width * .25, point.dy));
            if (row > 0) line(point, Offset(point.dx, point.dy - safeRect.height * .3));
          }
        }
      case 'aminoAcid':
        canvas.drawCircle(Offset(safeRect.center.dx, safeRect.center.dy), math.min(safeRect.width, safeRect.height) * .12, base);
        line(safeRect.centerLeft, Offset(safeRect.center.dx - safeRect.width * .12, safeRect.center.dy));
        line(Offset(safeRect.center.dx + safeRect.width * .12, safeRect.center.dy), safeRect.centerRight);
        line(safeRect.center, Offset(safeRect.center.dx, safeRect.top));
        line(safeRect.center, Offset(safeRect.center.dx, safeRect.bottom));
        label('NH₂');
      case 'proteinSymbol':
        final protein = Path()..moveTo(safeRect.left, safeRect.center.dy);
        for (var i = 1; i <= 20; i++) {
          final t = i / 20;
          protein.lineTo(safeRect.left + safeRect.width * t, safeRect.center.dy + math.sin(t * math.pi * 5) * safeRect.height * .24);
        }
        canvas.drawPath(protein, base);
      case 'cellMembrane':
      case 'bloodCell':
        canvas.drawOval(safeRect, base);
        if (shape == 'cellMembrane') {
          canvas.drawOval(safeRect.deflate(math.min(safeRect.width, safeRect.height) * .12), base);
        } else {
          canvas.drawOval(safeRect.deflate(math.min(safeRect.width, safeRect.height) * .25), base..color = stroke.pen.color.withValues(alpha: .28));
        }
      case 'chloroplast':
        canvas.drawOval(safeRect, base);
        for (var i = 0; i < 4; i++) {
          final y = safeRect.top + safeRect.height * (.2 + i * .2);
          canvas.drawOval(Rect.fromCenter(center: Offset(safeRect.center.dx, y), width: safeRect.width * .72, height: safeRect.height * .12), base);
        }
      case 'mitochondrion':
        canvas.drawOval(safeRect, base);
        final inner = Path()..moveTo(safeRect.left + safeRect.width * .12, safeRect.center.dy);
        for (var i = 1; i <= 12; i++) {
          inner.lineTo(safeRect.left + safeRect.width * (.12 + i * .065), safeRect.center.dy + (i.isEven ? -1 : 1) * safeRect.height * .2);
        }
        canvas.drawPath(inner, base);
      case 'ribosome':
        canvas.drawCircle(Offset(safeRect.center.dx - safeRect.width * .16, safeRect.center.dy), safeRect.height * .22, base);
        canvas.drawCircle(Offset(safeRect.center.dx + safeRect.width * .13, safeRect.center.dy - safeRect.height * .08), safeRect.height * .3, base);
        canvas.drawCircle(Offset(safeRect.center.dx + safeRect.width * .23, safeRect.center.dy + safeRect.height * .18), safeRect.height * .14, fill..color = stroke.pen.color);
      case 'brainIcon':
        for (var i = 0; i < 4; i++) {
          final cx = safeRect.left + safeRect.width * (.24 + i * .17);
          final cy = safeRect.center.dy + (i.isEven ? -1 : 1) * safeRect.height * .05;
          canvas.drawCircle(Offset(cx, cy), safeRect.height * .22, base);
        }
        line(Offset(safeRect.center.dx, safeRect.top + safeRect.height * .12), Offset(safeRect.center.dx, safeRect.bottom - safeRect.height * .12));
      case 'heartOrgan':
        final heart = Path()
          ..moveTo(safeRect.center.dx, safeRect.bottom)
          ..cubicTo(safeRect.left - safeRect.width * .02, safeRect.center.dy, safeRect.left + safeRect.width * .22, safeRect.top - safeRect.height * .05, safeRect.center.dx, safeRect.top + safeRect.height * .3)
          ..cubicTo(safeRect.right - safeRect.width * .22, safeRect.top - safeRect.height * .05, safeRect.right + safeRect.width * .02, safeRect.center.dy, safeRect.center.dx, safeRect.bottom)
          ..close();
        canvas.drawPath(heart, base);
      case 'lungIcon':
        line(Offset(safeRect.center.dx, safeRect.top), Offset(safeRect.center.dx, safeRect.center.dy));
        canvas.drawOval(Rect.fromLTWH(safeRect.left + safeRect.width * .08, safeRect.center.dy - safeRect.height * .12, safeRect.width * .38, safeRect.height * .52), base);
        canvas.drawOval(Rect.fromLTWH(safeRect.left + safeRect.width * .54, safeRect.center.dy - safeRect.height * .12, safeRect.width * .38, safeRect.height * .52), base);
        line(Offset(safeRect.center.dx, safeRect.center.dy), Offset(safeRect.left + safeRect.width * .28, safeRect.center.dy + safeRect.height * .08));
        line(Offset(safeRect.center.dx, safeRect.center.dy), Offset(safeRect.left + safeRect.width * .72, safeRect.center.dy + safeRect.height * .08));
      case 'bacteriaIcon':
        canvas.drawOval(safeRect.deflate(safeRect.width * .15), base);
        for (var i = 0; i < 6; i++) {
          final x = safeRect.left + safeRect.width * (.12 + i * .15);
          final y = safeRect.center.dy + (i.isEven ? -1 : 1) * safeRect.height * .24;
          line(Offset(x, y), Offset(x + safeRect.width * .04, y + (i.isEven ? -1 : 1) * safeRect.height * .12));
        }
      case 'virusIcon':
        canvas.drawCircle(safeRect.center, math.min(safeRect.width, safeRect.height) * .28, base);
        for (var i = 0; i < 12; i++) {
          final angle = i * math.pi / 6;
          final start = Offset(safeRect.center.dx + math.cos(angle) * safeRect.width * .28, safeRect.center.dy + math.sin(angle) * safeRect.height * .28);
          final end = Offset(safeRect.center.dx + math.cos(angle) * safeRect.width * .42, safeRect.center.dy + math.sin(angle) * safeRect.height * .42);
          line(start, end);
          canvas.drawCircle(end, math.max(1.5, base.strokeWidth).toDouble(), base);
        }
      case 'flowerIcon':
        for (var i = 0; i < 8; i++) {
          final angle = i * math.pi / 4;
          canvas.drawCircle(Offset(safeRect.center.dx + math.cos(angle) * safeRect.width * .17, safeRect.center.dy + math.sin(angle) * safeRect.height * .17), math.min(safeRect.width, safeRect.height) * .13, base);
        }
        canvas.drawCircle(safeRect.center, math.min(safeRect.width, safeRect.height) * .1, fill..color = stroke.pen.color);
        line(Offset(safeRect.center.dx, safeRect.center.dy + safeRect.height * .25), Offset(safeRect.center.dx, safeRect.bottom));
      case 'treeIcon':
        canvas.drawPath(polygon([
          Offset(safeRect.center.dx, safeRect.top),
          Offset(safeRect.right, safeRect.top + safeRect.height * .48),
          Offset(safeRect.left, safeRect.top + safeRect.height * .48),
        ]), base);
        canvas.drawPath(polygon([
          Offset(safeRect.center.dx, safeRect.top + safeRect.height * .25),
          Offset(safeRect.right, safeRect.top + safeRect.height * .75),
          Offset(safeRect.left, safeRect.top + safeRect.height * .75),
        ]), base);
        canvas.drawRect(Rect.fromLTWH(safeRect.center.dx - safeRect.width * .07, safeRect.bottom - safeRect.height * .25, safeRect.width * .14, safeRect.height * .25), base);
      default:
        canvas.drawRRect(
          RRect.fromRectAndRadius(safeRect, const Radius.circular(5)),
          base,
        );
        label(_humanize(shape));
    }

  }

  static String _humanize(String raw) {
    final buffer = StringBuffer();
    for (var i = 0; i < raw.length; i++) {
      final code = raw.codeUnitAt(i);
      if (i > 0 && code >= 65 && code <= 90) buffer.write(' ');
      buffer.writeCharCode(code);
    }
    return buffer.toString();
  }

  static void _drawArrowHead(Canvas canvas, Offset from, Offset to, Paint paint) {
    final angle = math.atan2(to.dy - from.dy, to.dx - from.dx);
    const length = 11.0;
    const spread = .55;
    final a = Offset(
      to.dx - length * math.cos(angle - spread),
      to.dy - length * math.sin(angle - spread),
    );
    final b = Offset(
      to.dx - length * math.cos(angle + spread),
      to.dy - length * math.sin(angle + spread),
    );
    canvas.drawLine(to, a, paint);
    canvas.drawLine(to, b, paint);
  }

  static void _drawDashedLine(
    Canvas canvas,
    Offset a,
    Offset b,
    Paint paint, {
    bool dotted = false,
  }) {
    final delta = b - a;
    final length = delta.distance;
    if (length <= 0) return;
    final direction = delta / length;
    final unit = dotted ? 8.0 : 14.0;
    final gap = dotted ? 9.0 : 7.0;
    for (double d = 0; d < length; d += unit + gap) {
      final end = math.min(length, d + unit);
      if (dotted) {
        canvas.drawCircle(a + direction * d, math.max(1, paint.strokeWidth * .5).toDouble(), Paint()..color = paint.color);
      } else {
        canvas.drawLine(a + direction * d, a + direction * end, paint);
      }
    }
  }

  static void _drawDimensionTicks(Canvas canvas, Offset a, Offset b, Paint paint) {
    final delta = b - a;
    if (delta.distance == 0) return;
    final normal = Offset(-delta.dy, delta.dx) / delta.distance * 5;
    canvas.drawLine(a - normal, a + normal, paint);
    canvas.drawLine(b - normal, b + normal, paint);
  }

  static Paint _axisPaint(Paint source) => Paint()
    ..color = source.color.withValues(alpha: .32)
    ..strokeWidth = .8
    ..isAntiAlias = true;

  static void _drawGraph(Canvas canvas, Rect rect, Paint paint, String shape) {
    final axis = Paint()..color = paint.color.withValues(alpha: .32)..strokeWidth = .8;
    canvas.drawLine(Offset(rect.left, rect.center.dy), Offset(rect.right, rect.center.dy), axis);
    canvas.drawLine(Offset(rect.center.dx, rect.top), Offset(rect.center.dx, rect.bottom), axis);
    final path = Path();
    for (var i = 0; i <= 100; i++) {
      final t = i / 100;
      final x = rect.left + t * rect.width;
      final n = (t - .5) * 4;
      double y;
      switch (shape) {
        case 'sineWave':
        case 'waveform':
          y = math.sin(n * math.pi) * .36;
        case 'parabola':
        case 'projectilePath':
          y = -.8 + 1.6 * math.pow(n / 2, 2).toDouble();
        case 'cubicGraph':
          y = math.pow(n / 2, 3).toDouble() * .72;
        case 'exponentialGraph':
          y = (math.exp(n * .65) - 1) / 4;
        case 'logarithmicGraph':
          y = n <= -.94 ? 1 : math.log(n + 1.01) / 2;
        case 'tangentGraph':
          y = math.tan(n).clamp(-3.0, 3.0) / 4;
        default:
          y = math.sin(n);
      }
      final point = Offset(x, rect.center.dy + y * rect.height * .45);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.save();
    canvas.clipRect(rect);
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  static void _drawResistor(Canvas canvas, Rect rect, Paint paint) {
    final path = Path()..moveTo(rect.left, rect.center.dy);
    final step = rect.width / 10;
    for (var i = 1; i < 9; i++) {
      path.lineTo(rect.left + step * i,
          rect.center.dy + (i.isEven ? -rect.height * .25 : rect.height * .25));
    }
    path.lineTo(rect.right, rect.center.dy);
    canvas.drawPath(path, paint);
  }

  /// Releases the cached picture when an owner can explicitly end this painter's lifetime.
  /// RenderCustomPaint does not call this method; the finalizer remains the fallback
  /// for painters owned by the widget/rendering lifecycle.
  void dispose() {
    _pictureFinalizer.detach(this);
    final picture = _basePicture;
    _basePicture = null;
    picture?.dispose();
    _liveHighlighterPath = null;
    _liveHighlighterPoints = null;
    _liveHighlighterPointCount = 0;
  }

  @override
  bool shouldRepaint(covariant EditorV2InkPainter oldDelegate) {
    final sameBaseStrokes =
        identical(strokes, oldDelegate.strokes) &&
        highlighterOnTop == oldDelegate.highlighterOnTop &&
        onlyHighlighters == oldDelegate.onlyHighlighters;
    if (sameBaseStrokes && oldDelegate._basePicture != null) {
      _pictureFinalizer.detach(oldDelegate);
      _basePicture = oldDelegate._basePicture;
      oldDelegate._basePicture = null;
      _pictureFinalizer.attach(this, _basePicture!, detach: this);
    }

    final sameLiveHighlighterPoints =
        liveStroke?.pen.type == PenType.highlighter &&
        oldDelegate.liveStroke?.pen.type == PenType.highlighter &&
        identical(liveStroke?.points, oldDelegate.liveStroke?.points);
    if (sameLiveHighlighterPoints) {
      _liveHighlighterPath = oldDelegate._liveHighlighterPath;
      _liveHighlighterPoints = oldDelegate._liveHighlighterPoints;
      _liveHighlighterPointCount = oldDelegate._liveHighlighterPointCount;
      oldDelegate._liveHighlighterPath = null;
      oldDelegate._liveHighlighterPoints = null;
      oldDelegate._liveHighlighterPointCount = 0;
    }

    return !sameBaseStrokes ||
        liveStroke != oldDelegate.liveStroke ||
        selectedStrokeIds != oldDelegate.selectedStrokeIds ||
        eraserCursor != oldDelegate.eraserCursor ||
        eraserRadius != oldDelegate.eraserRadius ||
        highlighterOnTop != oldDelegate.highlighterOnTop ||
        onlyHighlighters != oldDelegate.onlyHighlighters;
  }

}
