import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snote/canvas_engine/algorithms/lasso_geometry.dart';
import 'package:snote/canvas_engine/algorithms/shape_recognizer.dart';
import 'package:snote/canvas_engine/algorithms/stroke_geometry.dart';
import 'package:snote/canvas_engine/models/stroke.dart';

void main() {
  group('LassoGeometry', () {
    const polygon = <Offset>[
      Offset(10, 10),
      Offset(90, 10),
      Offset(90, 90),
      Offset(10, 90),
    ];

    test('ray casting includes interior points and polygon boundaries', () {
      expect(LassoGeometry.pointInPolygon(const Offset(40, 40), polygon), isTrue);
      expect(LassoGeometry.pointInPolygon(const Offset(10, 40), polygon), isTrue);
      expect(LassoGeometry.pointInPolygon(const Offset(120, 40), polygon), isFalse);
    });

    test('selects a segment crossing the polygon between sparse samples', () {
      const stroke = <StrokePoint>[
        StrokePoint(position: Offset(0, 50)),
        StrokePoint(position: Offset(100, 50)),
      ];
      expect(LassoGeometry.strokeIntersectsPolygon(stroke, polygon), isTrue);
    });

    test('does not select strokes completely outside the polygon', () {
      const stroke = <StrokePoint>[
        StrokePoint(position: Offset(0, 0)),
        StrokePoint(position: Offset(5, 5)),
      ];
      expect(LassoGeometry.strokeIntersectsPolygon(stroke, polygon), isFalse);
    });
  });

  group('ShapeRecognizer', () {
    test('recognizes diagonal lines', () {
      final points = List<StrokePoint>.generate(
        12,
        (index) => StrokePoint(
          position: Offset(index * 10, index * 8 + (index.isEven ? 1 : -1)),
          timestamp: index * 8,
        ),
      );
      expect(ShapeRecognizer.recognize(points), 'line');
    });

    test('recognizes closed rectangular strokes', () {
      const offsets = <Offset>[
        Offset(0, 0),
        Offset(35, 1),
        Offset(70, 0),
        Offset(100, 15),
        Offset(100, 35),
        Offset(95, 60),
        Offset(60, 60),
        Offset(25, 59),
        Offset(0, 60),
        Offset(0, 30),
        Offset(0, 0),
      ];
      final points = offsets
          .asMap()
          .entries
          .map((entry) => StrokePoint(
                position: entry.value,
                timestamp: entry.key * 8,
              ))
          .toList();
      expect(ShapeRecognizer.recognize(points), 'rectangle');
    });

    test('recognizes roughly circular strokes', () {
      final points = List<StrokePoint>.generate(32, (index) {
        final angle = index * 2 * math.pi / 31;
        return StrokePoint(
          position: Offset(50 + 30 * math.cos(angle), 50 + 30 * math.sin(angle)),
          timestamp: index * 8,
        );
      });
      expect(ShapeRecognizer.recognize(points), 'ellipse');
    });
  });

  test('ribbon geometry produces a smooth non-empty path', () {
    const points = <StrokePoint>[
      StrokePoint(position: Offset(10, 10), pressure: .2),
      StrokePoint(position: Offset(30, 16), pressure: .5),
      StrokePoint(position: Offset(52, 18), pressure: .9),
      StrokePoint(position: Offset(78, 30), pressure: .7),
    ];
    final path = StrokeGeometry.buildRibbonPath(
      points,
      (point, _) => 2 + point.pressure * 3,
    );
    expect(path.computeMetrics().isNotEmpty, isTrue);
    expect(path.getBounds().width, greaterThan(0));
    expect(path.getBounds().height, greaterThan(0));
  });

  test('one sample produces a dot path', () {
    final path = StrokeGeometry.buildRibbonPath(
      const [StrokePoint(position: Offset(12, 18), pressure: .6)],
      (_, __) => 4,
    );
    expect(path.getBounds().width, closeTo(8, .01));
    expect(path.getBounds().height, closeTo(8, .01));
  });
}
