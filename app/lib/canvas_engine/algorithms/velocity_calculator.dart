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
    final velocity = dt <= 0 ? 0 : (position - _lastPosition!).distance / dt;

    _lastPosition = position;
    _lastTime = time;
    return velocity;
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
  final speedFactor = 1 / (1 + velocity * .012);
  final pressureFactor = .7 + (pressure.clamp(0, 1) * .6);
  return (baseWidth * speedFactor * pressureFactor).clamp(
    baseWidth * .3,
    baseWidth * 1.4,
  );
}
