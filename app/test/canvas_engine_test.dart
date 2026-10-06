import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:snote/canvas_engine/models/pen_config.dart';
import 'package:snote/canvas_engine/models/stroke.dart';
import 'package:snote/canvas_engine/models/stroke_codec.dart';
import 'package:snote/canvas_engine/algorithms/velocity_calculator.dart';

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
    expect(decoded.first.pen.color.value, pen.color.value);
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
}
