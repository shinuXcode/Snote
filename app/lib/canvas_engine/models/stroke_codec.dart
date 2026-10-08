import 'dart:ui';
import 'pen_config.dart';
import 'stroke.dart';

class StrokeCodec {
  static Map<String, Object?> strokeToJson(Stroke s) => {
    'id': s.id,
    'shape': s.shape,
    'fill': s.fill,
    'fillOpacity': s.fillOpacity,
    'customSides': s.customSides,
    'stickerText': s.stickerText,
    'dashed': s.dashed,
    'fillColor': s.fillColor?.toARGB32(),
    'pen': {
      'type': s.pen.type.name,
      'color': s.pen.color.toARGB32(),
      'size': s.pen.size,
      'opacity': s.pen.opacity,
      'pressureSensitivity': s.pen.pressureSensitivity,
      'velocitySensitivity': s.pen.velocitySensitivity,
      'pressureCurve': s.pen.pressureCurve.name,
      'customPressureExponent': s.pen.customPressureExponent,
    },
    'points': s.points
        .map(
          (p) => {
            'x': p.position.dx,
            'y': p.position.dy,
            'pressure': p.pressure,
            'timestamp': p.timestamp,
            'tilt': p.tilt,
            'orientation': p.orientation,
          },
        )
        .toList(),
  };

  static Map<String, Object?> strokesToDocument(
    List<Stroke> strokes,
  ) => {
        'version': 4,
        'strokes': strokes.map(strokeToJson).toList(),
      };

  static List<Stroke> documentToStrokes(Object? document) {
    if (document is! Map || document['strokes'] is! List) {
      return const [];
    }

    return (document['strokes'] as List)
        .whereType<Map>()
        .map((raw) {
          final penMap =
              raw['pen'] is Map ? raw['pen'] as Map : const {};
          final type = PenType.values.firstWhere(
            (p) => p.name == penMap['type']?.toString(),
            orElse: () => PenType.ballpoint,
          );
          final pressureCurve = PressureCurve.values.firstWhere(
            (p) => p.name == penMap['pressureCurve']?.toString(),
            orElse: () => PressureCurve.linear,
          );
          final points = (raw['points'] is List
                  ? raw['points'] as List
                  : const [])
              .whereType<Map>()
              .map(
                (p) => StrokePoint(
                  position: Offset(
                    (p['x'] as num?)?.toDouble() ?? 0,
                    (p['y'] as num?)?.toDouble() ?? 0,
                  ),
                  pressure:
                      ((p['pressure'] as num?)?.toDouble() ?? 1)
                          .clamp(0, 1)
                          .toDouble(),
                  timestamp:
                      (p['timestamp'] as num?)?.toDouble() ?? 0,
                  tilt: (p['tilt'] as num?)?.toDouble() ?? 0,
                  orientation:
                      (p['orientation'] as num?)?.toDouble() ?? 0,
                ),
              )
              .toList();

          return Stroke(
            id: raw['id']?.toString() ?? '',
            shape: raw['shape']?.toString(),
            fill: raw['fill'] == true,
            fillOpacity:
                ((raw['fillOpacity'] as num?)?.toDouble() ?? .18)
                    .clamp(0, 1)
                    .toDouble(),
            customSides: ((raw['customSides'] as num?)?.toInt() ?? 6)
                .clamp(3, 24)
                .toInt(),
            stickerText: raw['stickerText']?.toString(),
            points: points,
            dashed: raw['dashed'] == true,
            fillColor: raw['fillColor'] is num
                ? Color((raw['fillColor'] as num).toInt())
                : null,
            pen: PenConfig(
              type: type,
              color: Color(
                (penMap['color'] as num?)?.toInt() ?? 0xff111111,
              ),
              size: ((penMap['size'] as num?)?.toDouble() ?? 3)
                  .clamp(.5, 60)
                  .toDouble(),
              opacity:
                  ((penMap['opacity'] as num?)?.toDouble() ?? 1)
                      .clamp(.05, 1)
                      .toDouble(),
              pressureSensitivity:
                  ((penMap['pressureSensitivity'] as num?)
                              ?.toDouble() ??
                          .55)
                      .clamp(0, 1)
                      .toDouble(),
              velocitySensitivity:
                  ((penMap['velocitySensitivity'] as num?)
                              ?.toDouble() ??
                          .65)
                      .clamp(0, 1)
                      .toDouble(),
              pressureCurve: pressureCurve,
              customPressureExponent:
                  ((penMap['customPressureExponent'] as num?)
                              ?.toDouble() ??
                          1)
                      .clamp(.35, 2.5)
                      .toDouble(),
            ),
          );
        })
        .where((s) => s.id.isNotEmpty && s.points.isNotEmpty)
        .toList();
  }
}
