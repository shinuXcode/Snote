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
  final String? shape;

  const Stroke({
    required this.id,
    required this.points,
    required this.pen,
    this.shape,
  });

  Stroke copyWith({
    String? id,
    List<StrokePoint>? points,
    PenConfig? pen,
    String? shape,
  }) => Stroke(
        id: id ?? this.id,
        points: points ?? this.points,
        pen: pen ?? this.pen,
        shape: shape ?? this.shape,
      );
}
