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
  final bool fill;
  final double fillOpacity;
  final int customSides;
  final String? stickerText;

  const Stroke({
    required this.id,
    required this.points,
    required this.pen,
    this.shape,
    this.fill = false,
    this.fillOpacity = .18,
    this.customSides = 6,
    this.stickerText,
  });

  Stroke copyWith({
    String? id,
    List<StrokePoint>? points,
    PenConfig? pen,
    String? shape,
    bool? fill,
    double? fillOpacity,
    int? customSides,
    String? stickerText,
  }) {
    return Stroke(
      id: id ?? this.id,
      points: points ?? this.points,
      pen: pen ?? this.pen,
      shape: shape ?? this.shape,
      fill: fill ?? this.fill,
      fillOpacity: fillOpacity ?? this.fillOpacity,
      customSides: customSides ?? this.customSides,
      stickerText: stickerText ?? this.stickerText,
    );
  }
}
