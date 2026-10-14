import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:snote/canvas_engine/models/stroke.dart';
import 'package:snote/features/notes/editor_v2/editor_v2_ink_painter.dart';
import 'package:snote/canvas_engine/models/pen_config.dart';
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
