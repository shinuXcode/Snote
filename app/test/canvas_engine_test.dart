import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:snote/canvas_engine/ink_renderer.dart';
import 'package:snote/canvas_engine/models/pen_config.dart';
import 'package:snote/canvas_engine/models/stroke.dart';
import 'package:snote/canvas_engine/models/stroke_codec.dart';
import 'package:snote/canvas_engine/algorithms/velocity_calculator.dart';
import 'package:snote/canvas_engine/painters/canvas_painter.dart';
import 'package:snote/canvas_engine/widgets/page_background.dart';

void main() {
  test('stroke codec round-trips vector data', () {
    const pen = PenConfig(
      type: PenType.fountain,
      color: Color(0xff3567ff),
      size: 4,
    );

    final source = Stroke(
      id: 'stroke-1',
      points: const [
        StrokePoint(
          position: Offset(12, 16),
          pressure: .8,
          timestamp: 1,
        ),
        StrokePoint(
          position: Offset(22, 26),
          pressure: .9,
          timestamp: 2,
        ),
      ],
      pen: pen,
    );

    final document = StrokeCodec.strokesToDocument([source]);
    final decoded = StrokeCodec.documentToStrokes(document);

    expect(decoded, hasLength(1));
    expect(decoded.first.id, 'stroke-1');
    expect(decoded.first.points, hasLength(2));
    expect(decoded.first.pen.type, PenType.fountain);
    expect(decoded.first.pen.color.toARGB32(), pen.color.toARGB32());
  });

  test('fountain width decreases as velocity increases', () {
    final slow = fountainWidth(
      baseWidth: 5,
      velocity: 1,
      pressure: 1,
    );
    final fast = fountainWidth(
      baseWidth: 5,
      velocity: 120,
      pressure: 1,
    );

    expect(fast, lessThan(slow));
    expect(fast, greaterThan(1));
  });

  test('fountain ink density responds to pressure and speed', () {
    const pen = PenConfig(
      type: PenType.fountain,
      color: Color(0xff253047),
      size: 5,
      pressureSensitivity: .7,
      velocitySensitivity: .8,
    );

    final slowFirm = fountainOpacityForSample(
      pressure: .9,
      speed: 1,
      pen: pen,
    );
    final fastFirm = fountainOpacityForSample(
      pressure: .9,
      speed: 35,
      pen: pen,
    );
    final slowLight = fountainOpacityForSample(
      pressure: .2,
      speed: 1,
      pen: pen,
    );

    expect(fastFirm, lessThan(slowFirm));
    expect(slowLight, lessThan(slowFirm));
  });

  test('fountain renderer paints a smooth, tapered stroke and a tap', () async {
    const pen = PenConfig(
      type: PenType.fountain,
      color: Color(0xff172334),
      size: 5,
      pressureSensitivity: .7,
      velocitySensitivity: .8,
    );
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);

    InkRenderer.drawInk(
      canvas,
      const [
        StrokePoint(position: Offset(18, 45), pressure: .3, timestamp: 0),
        StrokePoint(position: Offset(30, 42), pressure: .45, timestamp: 10),
        StrokePoint(position: Offset(42, 38), pressure: .8, timestamp: 18),
        StrokePoint(position: Offset(55, 40), pressure: .9, timestamp: 26),
        StrokePoint(position: Offset(66, 46), pressure: .55, timestamp: 34),
      ],
      pen,
    );
    InkRenderer.drawInk(
      canvas,
      const [StrokePoint(position: Offset(78, 60), pressure: .8, timestamp: 45)],
      pen,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(120, 90);
    final pixels = await image.toByteData(format: ImageByteFormat.rawRgba);
    expect(pixels, isNotNull);
    var visible = 0;
    for (var i = 3; i < pixels!.lengthInBytes; i += 4) {
      if (pixels.getUint8(i) > 0) visible++;
    }
    expect(visible, greaterThan(0));
    image.dispose();
    picture.dispose();
  });

  test('every shape tool has a label and paints visible pixels', () async {
    const pen = PenConfig(
      type: PenType.ballpoint,
      color: Color(0xff253047),
      size: 2.5,
    );

    final tools = CanvasTool.values.where((tool) => tool.isShape).toList();
    expect(tools.length, greaterThanOrEqualTo(100));
    expect(CanvasTool.dottedLine.isShape, isTrue);
    expect(CanvasTool.dashedLine.isShape, isTrue);
    expect(CanvasTool.cartesianPlane.isShape, isTrue);
    for (final tool in tools) {
      expect(tool.label, isNotEmpty, reason: tool.name);
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      final stroke = Stroke(
        id: tool.name,
        points: const [
          StrokePoint(position: Offset(24, 30), pressure: .7, timestamp: 1),
          StrokePoint(position: Offset(180, 170), pressure: .8, timestamp: 2),
        ],
        pen: pen,
        shape: tool.name,
      );
      SnoteCanvasPainter(
        strokes: [stroke],
        activeStroke: null,
        activePoints: const [],
        activePen: null,
        activeTool: null,
        activeFill: false,
        activeCustomSides: 6,
        activeStickerText: null,
        selectedIds: const {},
        lassoPath: const [],
        drawActive: false,
      ).paint(canvas, const Size(220, 220));

      final picture = recorder.endRecording();
      final image = await picture.toImage(220, 220);
      final pixels = await image.toByteData(format: ImageByteFormat.rawRgba);
      expect(pixels, isNotNull, reason: tool.name);
      var visiblePixels = 0;
      for (var i = 3; i < pixels!.lengthInBytes; i += 4) {
        if (pixels.getUint8(i) > 0) visiblePixels++;
      }
      image.dispose();
      picture.dispose();
      expect(
        visiblePixels,
        greaterThan(0),
        reason: 'Shape tool "${tool.name}" produced no visible pixels',
      );
    }
  });

  test('every paper template paints without throwing', () {
    for (final template in PageTemplate.values) {
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      PageBackground(
        template: template,
        paperColor: const Color(0xffffffff),
        lineColor: const Color(0xffb6c0cc),
      ).paint(canvas, const Size(320, 480));
      recorder.endRecording().dispose();
    }
  });
}
