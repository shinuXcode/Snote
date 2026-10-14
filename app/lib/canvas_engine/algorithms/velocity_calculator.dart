import 'dart:ui';

class VelocityCalculator {
  Offset? _lastPosition;
  Duration? _lastTime;

  double update(Offset position, Duration time) {
    if (_lastPosition == null || _lastTime == null) {
      _lastPosition = position;
      _lastTime = time;
      return 0;
    }

    final dt = (time - _lastTime!).inMicroseconds / 1000000.0;
    final velocity = dt <= 0 ? 0.0 : (position - _lastPosition!).distance / dt;

    _lastPosition = position;
    _lastTime = time;
    return velocity.toDouble();
  }

  void reset() {
    _lastPosition = null;
    _lastTime = null;
  }
}

double fountainWidth({
  required double baseWidth,
  required double velocity,
  required double pressure,
}) {
  // Velocity is measured in canvas pixels per millisecond by the stroke
  // pipeline. Normalize it before applying a clear but bounded nib response.
  final speedResponse = (velocity / 1.8).clamp(0.0, 1.0).toDouble();
  final speedFactor = 1.24 - speedResponse * .52;
  final pressureFactor = .48 + pressure.clamp(0.0, 1.0) * .95;
  return (baseWidth * speedFactor * pressureFactor)
      .clamp(baseWidth * .3, baseWidth * 1.7)
      .toDouble();
}
