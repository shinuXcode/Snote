import 'dart:math' as math;
import '../models/pen_config.dart';

/// Tool-specific pressure/velocity response used by the final renderer.
class InkDynamics {
  static double width({
    required double base,
    required double pressure,
    required double velocity,
    required PenConfig pen,
  }) {
    final p = curvePressure(pressure, pen);
    final velocityFactor =
        1 - (velocity / 5.5).clamp(0.0, 1.0);
    final sensitivity =
        .25 + pen.velocitySensitivity.clamp(0, 1) * .75;
    final response = .72 + p * (.18 + pen.pressureSensitivity * .42);
    return (base * response * (1 + velocityFactor * .05 * sensitivity))
        .clamp(.5, 120)
        .toDouble();
  }

  static double tiltFactor(double tilt) =>
      1 + (tilt.clamp(0, math.pi / 2) / (math.pi / 2)) * .12;
}
