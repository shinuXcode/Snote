import 'dart:ui';
import 'pen_config.dart';

class StrokePoint {
  final Offset position;
  final double pressure;
  final double timestamp;

  const StrokePoint({
    required this.position,
    this.pressure = 1,
    this.timestamp = 0,
  });
}

class Stroke {
  final String id;
  final List<StrokePoint> points;
  final PenConfig pen;

  const Stroke({
    required this.id,
    required this.points,
    required this.pen,
  });
}
