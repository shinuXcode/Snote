import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:snote/canvas_engine/ink_renderer.dart';
import 'package:snote/canvas_engine/models/pen_config.dart';

void main() {
  const pen = PenConfig(
    type: PenType.fountain,
    color: Color(0xff24324a),
    size: 5,
    opacity: .9,
    pressureSensitivity: 1,
    velocitySensitivity: 1,
  );

  test('fountain opacity increases with pressure', () {
    final light = fountainOpacityForSample(
      pressure: .15,
      speed: 3,
      pen: pen,
    );
    final firm = fountainOpacityForSample(
      pressure: .9,
      speed: 3,
      pen: pen,
    );
    expect(firm, greaterThan(light));
  });

  test('fountain opacity decreases with speed and stays visible', () {
    final slow = fountainOpacityForSample(
      pressure: .8,
      speed: 1,
      pen: pen,
    );
    final fast = fountainOpacityForSample(
      pressure: .8,
      speed: 19,
      pen: pen,
    );
    expect(fast, lessThan(slow));
    expect(fast, greaterThanOrEqualTo(.08));
  });
}
