import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:snote/canvas_engine/algorithms/lasso_geometry.dart';
import 'package:snote/canvas_engine/models/stroke.dart';

StrokePoint p(double x, double y) =>
    StrokePoint(position: Offset(x, y), pressure: 1);

void main() {
  const box = <Offset>[
    Offset(0, 0),
    Offset(20, 0),
    Offset(20, 20),
    Offset(0, 20),
  ];

  group('tight lasso selection', () {
    test('selects a stroke mostly enclosed by the lasso', () {
      expect(
        LassoGeometry.strokeMostlyInsidePolygon(
          <StrokePoint>[p(4, 5), p(16, 5)],
          box,
        ),
        isTrue,
      );
    });

    test('rejects a long stroke that only touches the lasso boundary', () {
      expect(
        LassoGeometry.strokeMostlyInsidePolygon(
          <StrokePoint>[p(-100, 5), p(10, 5)],
          box,
        ),
        isFalse,
      );
    });

    test('rejects a stroke with only a small portion inside the lasso', () {
      expect(
        LassoGeometry.strokeMostlyInsidePolygon(
          <StrokePoint>[p(-20, 5), p(5, 5)],
          box,
        ),
        isFalse,
      );
    });

    test('accepts a single point only when it lies inside the lasso', () {
      expect(
        LassoGeometry.strokeMostlyInsidePolygon(<StrokePoint>[p(5, 5)], box),
        isTrue,
      );
      expect(
        LassoGeometry.strokeMostlyInsidePolygon(<StrokePoint>[p(25, 5)], box),
        isFalse,
      );
    });
  });
}
