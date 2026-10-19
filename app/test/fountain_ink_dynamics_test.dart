import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:snote/canvas_engine/algorithms/velocity_calculator.dart';
import 'package:snote/canvas_engine/ink_renderer.dart';
import 'package:snote/canvas_engine/models/pen_config.dart';

void main() {
  const pen = PenConfig(
    type: PenType.fountain,
    color: Color(0xff1e293b),
    size: 5,
    pressureSensitivity: 1,
    velocitySensitivity: 1,
  );

  test('fountain nib width responds to both speed and pressure', () {
    final slow = fountainWidth(
      baseWidth: 5,
      velocity: 1,
      pressure: .65,
    );
    final fast = fountainWidth(
      baseWidth: 5,
      velocity: 120,
      pressure: .65,
    );
    final light = fountainWidth(
      baseWidth: 5,
      velocity: 1,
      pressure: .1,
    );
    final firm = fountainWidth(
      baseWidth: 5,
      velocity: 1,
      pressure: .9,
    );

    expect(slow, greaterThan(fast));
    expect(firm, greaterThan(light));
  });

  test('fountain ink opacity responds to speed and pressure', () {
    final slow = fountainOpacityForSample(
      pressure: 1,
      speed: 0,
      pen: pen,
    );
    final fast = fountainOpacityForSample(
      pressure: 1,
      speed: 40,
      pen: pen,
    );
    final light = fountainOpacityForSample(
      pressure: 0,
      speed: 0,
      pen: pen,
    );

    expect(slow, greaterThan(fast));
    expect(slow, greaterThan(light));
  });
}
