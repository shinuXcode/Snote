import 'dart:ui';
import 'pen_config.dart';
import 'stroke.dart';

class StrokeCodec {
  static Map<String, Object?> strokeToJson(Stroke s) => {
    'id': s.id, 'shape': s.shape, 'fill': s.fill, 'fillOpacity': s.fillOpacity,
    'customSides': s.customSides, 'stickerText': s.stickerText,
    'pen': {'type': s.pen.type.name, 'color': s.pen.color.toARGB32(), 'size': s.pen.size, 'opacity': s.pen.opacity},
    'points': s.points.map((p) => {'x': p.position.dx, 'y': p.position.dy, 'pressure': p.pressure, 'timestamp': p.timestamp}).toList(),
  };

  static Map<String, Object?> strokesToDocument(List<Stroke> strokes) =>
      {'version': 3, 'strokes': strokes.map(strokeToJson).toList()};

  static List<Stroke> documentToStrokes(Object? document) {
    if (document is! Map || document['strokes'] is! List) return const [];
    return (document['strokes'] as List).whereType<Map>().map((raw) {
      final penMap = raw['pen'] is Map ? raw['pen'] as Map : const {};
      final type = PenType.values.firstWhere((p) => p.name == penMap['type']?.toString(), orElse: () => PenType.ballpoint);
      final points = (raw['points'] is List ? raw['points'] as List : const []).whereType<Map>().map((p) => StrokePoint(
        position: Offset((p['x'] as num?)?.toDouble() ?? 0, (p['y'] as num?)?.toDouble() ?? 0),
        pressure: ((p['pressure'] as num?)?.toDouble() ?? 1).clamp(0, 1),
        timestamp: (p['timestamp'] as num?)?.toDouble() ?? 0,
      )).toList();
      return Stroke(
        id: raw['id']?.toString() ?? '', shape: raw['shape']?.toString(),
        fill: raw['fill'] == true,
        fillOpacity: ((raw['fillOpacity'] as num?)?.toDouble() ?? .18).clamp(0, 1),
        customSides: ((raw['customSides'] as num?)?.toInt() ?? 6).clamp(3, 24),
        stickerText: raw['stickerText']?.toString(), points: points,
        pen: PenConfig(
          type: type,
          color: Color((penMap['color'] as num?)?.toInt() ?? 0xff111111),
          size: ((penMap['size'] as num?)?.toDouble() ?? 3).clamp(.5, 60),
          opacity: ((penMap['opacity'] as num?)?.toDouble() ?? 1).clamp(.05, 1),
        ),
      );
    }).where((s) => s.id.isNotEmpty && s.points.isNotEmpty).toList();
  }
}
