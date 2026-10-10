import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
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

  test('every shape tool has a label and renders through the vector painter', () {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    const pen = PenConfig(
      type: PenType.ballpoint,
      color: Color(0xff253047),
      size: 2.5,
    );

    final tools = CanvasTool.values.where((tool) => tool.isShape).toList();
    expect(tools.length, greaterThanOrEqualTo(30));
    for (final tool in tools) {
      expect(tool.label, isNotEmpty, reason: tool.name);
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
    }
    recorder.endRecording().dispose();
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
