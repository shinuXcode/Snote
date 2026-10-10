import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:snote/canvas_engine/algorithms/ink_hit_testing.dart';
import 'package:snote/canvas_engine/models/stroke.dart';

void main() {
  const sparseLine = <StrokePoint>[
    StrokePoint(
      position: Offset(0, 0),
      pressure: .2,
      timestamp: 0,
    ),
    StrokePoint(
      position: Offset(100, 0),
      pressure: .8,
      timestamp: 10,
    ),
  ];

  test('pixel eraser detects sparse segments crossing its radius', () {
    expect(
      InkHitTesting.polylineTouchesCircle(sparseLine, const Offset(50, 0), 10),
      isTrue,
    );
  });

  test('pixel eraser clips a segment at exact circle intersections', () {
    final pieces = InkHitTesting.subtractCircle(
      sparseLine,
      const Offset(50, 0),
      10,
    );

    expect(pieces, hasLength(2));
    expect(pieces.first.first.position, const Offset(0, 0));
    expect(pieces.first.last.position.dx, closeTo(40, .0001));
    expect(pieces.last.first.position.dx, closeTo(60, .0001));
    expect(pieces.last.last.position, const Offset(100, 0));
    expect(pieces.first.last.pressure, closeTo(.44, .0001));
    expect(pieces.first.last.timestamp, closeTo(4, .0001));
  });

  test('pixel eraser leaves an unaffected segment untouched', () {
    final pieces = InkHitTesting.subtractCircle(
      sparseLine,
      const Offset(50, 20),
      10,
    );

    expect(pieces, hasLength(1));
    expect(pieces.single, hasLength(2));
    expect(pieces.single.first.position, const Offset(0, 0));
    expect(pieces.single.last.position, const Offset(100, 0));
  });

  test('lasso selects a segment crossing polygon with no interior samples', () {
    const rectangle = <Offset>[
      Offset(40, -10),
      Offset(60, -10),
      Offset(60, 10),
      Offset(40, 10),
    ];

    expect(
      InkHitTesting.polylineIntersectsPolygon(sparseLine, rectangle),
      isTrue,
    );
  });

  test('lasso ignores a segment that misses its polygon', () {
    const rectangle = <Offset>[
      Offset(40, -10),
      Offset(60, -10),
      Offset(60, 10),
      Offset(40, 10),
    ];
    const outside = <StrokePoint>[
      StrokePoint(position: Offset(0, 30)),
      StrokePoint(position: Offset(100, 30)),
    ];

    expect(
      InkHitTesting.polylineIntersectsPolygon(outside, rectangle),
      isFalse,
    );
  });
}
