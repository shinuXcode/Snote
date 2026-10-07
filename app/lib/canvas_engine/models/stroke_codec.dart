import 'dart:ui';
import 'pen_config.dart';
import 'stroke.dart';

class StrokeCodec {
  static Map<String, Object?> strokeToJson(Stroke s) => {
        'id': s.id,
        'shape': s.shape,
        'pen': {
          'type': s.pen.type.name,
          'color': s.pen.color.toARGB32(),
          'size': s.pen.size,
          'opacity': s.pen.opacity,
        },
        'points': s.points.map((p) => {
          'x': p.position.dx,
          'y': p.position.dy,
          'pressure': p.pressure,
          'timestamp': p.timestamp,
        }).toList(),
      };

  static Map<String, Object?> strokesToDocument(List<Stroke> strokes) => {
        'version': 2,
        'strokes': strokes.map(strokeToJson).toList(),
      };

  static List<Stroke> documentToStrokes(Object? document) {
    if (document is! Map) return const [];
    final rawStrokes = document['strokes'];
    if (rawStrokes is! List) return const [];

    return rawStrokes.whereType<Map>().map((raw) {
      final penMap = raw['pen'] is Map ? raw['pen'] as Map : const {};
      final rawPoints = raw['points'] is List ? raw['points'] as List : const [];
      final typeName = penMap['type']?.toString() ?? PenType.ballpoint.name;
      final type = PenType.values.firstWhere(
        (p) => p.name == typeName,
        orElse: () => PenType.ballpoint,
      );
      final pen = PenConfig(
        type: type,
        color: Color((penMap['color'] as num?)?.toInt() ?? 0xff111111),
        size: ((penMap['size'] as num?)?.toDouble() ?? 3).clamp(0.5, 60),
        opacity: ((penMap['opacity'] as num?)?.toDouble() ?? 1).clamp(0.05, 1),
      );
      final points = rawPoints.whereType<Map>().map((p) => StrokePoint(
        position: Offset(
          (p['x'] as num?)?.toDouble() ?? 0,
          (p['y'] as num?)?.toDouble() ?? 0,
        ),
        pressure: ((p['pressure'] as num?)?.toDouble() ?? 1).clamp(0, 1),
        timestamp: (p['timestamp'] as num?)?.toDouble() ?? 0,
      )).toList();

      return Stroke(
        id: raw['id']?.toString() ?? '',
        shape: raw['shape']?.toString(),
        points: points,
        pen: pen,
      );
    }).where((s) => s.id.isNotEmpty && s.points.isNotEmpty).toList();
  }
}
