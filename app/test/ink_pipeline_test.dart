import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snote/canvas_engine/input/ink_input_pipeline.dart';
import 'package:snote/canvas_engine/input/viewport_transform.dart';
import 'dart:ui';

void main() {
  test('live stroke follows the physical pointer without filtered lag', () {
    final pipeline = InkInputPipeline(smoothing: .72);
    pipeline.begin(
      const PointerDownEvent(
        pointer: 1,
        kind: PointerDeviceKind.stylus,
        position: Offset(10, 10),
      ),
    );

    final frame = pipeline.update(
      const PointerMoveEvent(
        pointer: 1,
        kind: PointerDeviceKind.stylus,
        position: Offset(100, 40),
        timeStamp: Duration(milliseconds: 8),
      ),
    );

    expect(frame.realPoints.last.position, const Offset(100, 40));
    expect(frame.livePoints.firstWhere(
      (point) => identical(point, frame.realPoints.last),
    ).position, const Offset(100, 40));
  });

  test('prediction is transient and never enters final points', () {
    final pipeline = InkInputPipeline(smoothing: .72);
    pipeline.begin(
      const PointerDownEvent(
        pointer: 1,
        kind: PointerDeviceKind.stylus,
        position: Offset(0, 0),
      ),
    );
    pipeline.update(
      const PointerMoveEvent(
        pointer: 1,
        kind: PointerDeviceKind.stylus,
        position: Offset(30, 0),
        timeStamp: Duration(milliseconds: 10),
      ),
    );
    final frame = pipeline.update(
      const PointerMoveEvent(
        pointer: 1,
        kind: PointerDeviceKind.stylus,
        position: Offset(60, 0),
        timeStamp: Duration(milliseconds: 20),
      ),
    );

    expect(frame.livePoints.length, greaterThanOrEqualTo(frame.realPoints.length));
    if (frame.predictedPoint != null) {
      expect(
        pipeline.realPoints.any((p) => identical(p, frame.predictedPoint)),
        isFalse,
      );
    }

    final finalPoints = pipeline.finish(
      const PointerUpEvent(
        pointer: 1,
        kind: PointerDeviceKind.stylus,
        position: Offset(60, 0),
        timeStamp: Duration(milliseconds: 21),
      ),
    );
    expect(finalPoints.last.position, const Offset(60, 0));
  });

  test('finalize preserves the physical pointer-up endpoint', () {
    final pipeline = InkInputPipeline(smoothing: .72);
    pipeline.begin(
      const PointerDownEvent(
        pointer: 1,
        position: Offset(0, 0),
      ),
    );
    pipeline.update(
      const PointerMoveEvent(
        pointer: 1,
        position: Offset(20, 20),
        timeStamp: Duration(milliseconds: 10),
      ),
    );

    final result = pipeline.finish(
      const PointerUpEvent(
        pointer: 1,
        position: Offset(40, 40),
        timeStamp: Duration(milliseconds: 20),
      ),
    );

    expect(result.last.position, const Offset(40, 40));
    expect(result.length, 3);
  });

  test('viewport transform round-trips coordinates', () {
    const transform = ViewportTransform(
      scale: 2,
      pan: Offset(25, 40),
    );
    const documentPoint = Offset(120, 80);
    final viewPoint = transform.toView(documentPoint);
    expect(transform.toDocument(viewPoint).dx, closeTo(documentPoint.dx, .0001));
    expect(transform.toDocument(viewPoint).dy, closeTo(documentPoint.dy, .0001));
  });
}
