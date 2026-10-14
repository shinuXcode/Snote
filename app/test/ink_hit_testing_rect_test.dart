import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:snote/canvas_engine/algorithms/ink_hit_testing.dart';
import 'package:snote/canvas_engine/models/stroke.dart';

StrokePoint point(double x, double y) =>
    StrokePoint(position: Offset(x, y), pressure: 1);

void main() {
  group('rectangular eraser hit testing', () {
    test('detects a sparse stroke crossing the eraser rectangle', () {
      final stroke = <StrokePoint>[point(0, 5), point(100, 5)];
      final footprint = Rect.fromLTRB(45, 0, 55, 10);

      expect(InkHitTesting.polylineTouchesRect(stroke, footprint), isTrue);
      expect(
        InkHitTesting.polylineTouchesRect(
          stroke,
          footprint,
          padding: 2,
        ),
        isTrue,
      );
    });

    test('subtraction keeps both un-erased ends and removes the bridge', () {
      final stroke = <StrokePoint>[point(0, 5), point(100, 5)];
      final pieces = InkHitTesting.subtractRect(
        stroke,
        Rect.fromLTRB(45, 0, 55, 10),
      );

      expect(pieces, hasLength(2));
      expect(pieces[0].first.position.dx, closeTo(0, 1e-6));
      expect(pieces[0].last.position.dx, closeTo(45, 1e-6));
      expect(pieces[1].first.position.dx, closeTo(55, 1e-6));
      expect(pieces[1].last.position.dx, closeTo(100, 1e-6));
    });

    test('does not change a stroke that misses the eraser rectangle', () {
      final stroke = <StrokePoint>[point(0, 40), point(100, 40)];
      final pieces = InkHitTesting.subtractRect(
        stroke,
        Rect.fromLTRB(45, 0, 55, 10),
      );

      expect(pieces, hasLength(1));
      expect(pieces.single, hasLength(2));
      expect(pieces.single.last.position, const Offset(100, 40));
    });
  });

  group('lasso precision', () {
    const lasso = <Offset>[
      Offset(0, 0),
      Offset(10, 0),
      Offset(10, 10),
      Offset(0, 10),
    ];

    test('selects a stroke whose centreline is inside the lasso', () {
      expect(
        InkHitTesting.polylineMostlyInsidePolygon(
          <StrokePoint>[point(2, 5), point(8, 5)],
          lasso,
        ),
        isTrue,
      );
    });

    test('rejects a long stroke that only clips the selection boundary', () {
      expect(
        InkHitTesting.polylineMostlyInsidePolygon(
          <StrokePoint>[point(-90, 5), point(10, 5)],
          lasso,
        ),
        isFalse,
      );
    });

    test('point-in-polygon supports closed freehand fill loops', () {
      expect(InkHitTesting.pointInPolygon(const Offset(5, 5), lasso), isTrue);
      expect(InkHitTesting.pointInPolygon(const Offset(15, 5), lasso), isFalse);
    });
  });
}
