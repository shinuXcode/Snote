import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:snote/canvas_engine/models/stroke.dart';
import 'package:snote/features/notes/editor_v2/editor_v2_ink_painter.dart';
import 'package:snote/canvas_engine/models/pen_config.dart';
import 'package:snote/canvas_engine/models/stroke_codec.dart';
import 'package:snote/canvas_engine/widgets/page_background.dart';

void main() {
  test('shape catalogue exposes more than 200 tool choices', () {
    expect(CanvasTool.values.length, greaterThanOrEqualTo(200));
    expect(CanvasTool.octagon.isShape, isTrue);
    expect(CanvasTool.matrixGrid.isShape, isTrue);
    expect(CanvasTool.virusIcon.isShape, isTrue);
  });

  test('all categorized shape tools pass through the ink painter', () {
    final shapeTools = CanvasTool.values.where((tool) => tool.isShape).toList();
    expect(shapeTools.length, greaterThanOrEqualTo(150));

    final strokes = shapeTools.map((tool) => Stroke(
      id: 'shape-${tool.name}',
      points: const <StrokePoint>[
        StrokePoint(position: Offset(30, 30)),
        StrokePoint(position: Offset(170, 130)),
      ],
      pen: const PenConfig(
        type: PenType.ballpoint,
        color: Color(0xff176c83),
        size: 2.2,
        opacity: 1,
      ),
      shape: tool.name,
    )).toList();

    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    expect(
      () => EditorV2InkPainter(strokes: strokes).paint(canvas, const Size(220, 180)),
      returnsNormally,
    );
    recorder.endRecording().dispose();
  });

  test('fill tool and pressure data survive document serialization', () {
    final source = Stroke(
      id: 'filled-loop',
      points: const <StrokePoint>[
        StrokePoint(position: Offset(10, 10), pressure: .2, timestamp: 1),
        StrokePoint(position: Offset(50, 10), pressure: .45, timestamp: 2),
        StrokePoint(position: Offset(50, 50), pressure: .9, timestamp: 3),
        StrokePoint(position: Offset(10, 10), pressure: 1, timestamp: 4),
      ],
      pen: const PenConfig(
        type: PenType.fountain,
        color: Color(0xff153e75),
        size: 3.5,
        opacity: .9,
        pressureSensitivity: .92,
        velocitySensitivity: .4,
      ),
      fill: true,
      fillColor: Color(0xff14b8a6),
      fillOpacity: .72,
    );

    final encoded = StrokeCodec.strokesToDocument(<Stroke>[source]);
    final decoded = StrokeCodec.documentToStrokes(encoded).single;

    expect(CanvasTool.fill.label, 'Fill');
    expect(CanvasTool.fill.isShape, isFalse);
    expect(decoded.fill, isTrue);
    expect(decoded.fillColor?.toARGB32(), 0xff14b8a6);
    expect(decoded.fillOpacity, closeTo(.72, .001));
    expect(decoded.points.map((point) => point.pressure).toList(), <double>[.2, .45, .9, 1]);
    expect(decoded.pen.pressureSensitivity, closeTo(.92, .001));
    expect(decoded.pen.velocitySensitivity, closeTo(.4, .001));
  });

  test('filled vector shapes and pressure modulated pen strokes paint without errors', () {
    final shapes = <Stroke>[
      for (final tool in <CanvasTool>[CanvasTool.rectangle, CanvasTool.ellipse, CanvasTool.triangle, CanvasTool.diamond, CanvasTool.star])
        Stroke(
          id: 'filled-${tool.name}',
          points: const <StrokePoint>[
            StrokePoint(position: Offset(20, 20), pressure: .25),
            StrokePoint(position: Offset(180, 140), pressure: 1),
          ],
          pen: const PenConfig(type: PenType.ballpoint, color: Color(0xff166534), size: 3, pressureSensitivity: .8),
          shape: tool.name,
          fill: true,
          fillColor: Color(0xff93c5fd),
          fillOpacity: .55,
        ),
      Stroke(
        id: 'pressure-ink',
        points: const <StrokePoint>[
          StrokePoint(position: Offset(10, 80), pressure: .15),
          StrokePoint(position: Offset(60, 40), pressure: .55),
          StrokePoint(position: Offset(120, 100), pressure: 1),
        ],
        pen: const PenConfig(type: PenType.fountain, color: Color(0xff111827), size: 5, pressureSensitivity: 1),
      ),
    ];

    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    expect(() => EditorV2InkPainter(strokes: shapes).paint(canvas, const Size(220, 180)), returnsNormally);
    recorder.endRecording().dispose();
  });

  test('dotted page background redraws when opacity or spacing changes', () {
    const original = PageBackground(
      template: PageTemplate.dotted,
      spacing: 28,
      lineOpacity: .85,
    );
    const same = PageBackground(
      template: PageTemplate.dotted,
      spacing: 28,
      lineOpacity: .85,
    );
    const changed = PageBackground(
      template: PageTemplate.dotted,
      spacing: 36,
      lineOpacity: .6,
    );

    expect(original.shouldRepaint(same), isFalse);
    expect(original.shouldRepaint(changed), isTrue);
  });
}
