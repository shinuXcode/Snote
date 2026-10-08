import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snote/canvas_engine/algorithms/adaptive_stabilizer.dart';
import 'package:snote/canvas_engine/input/ink_input_pipeline.dart';
import 'package:snote/canvas_engine/input/ink_prediction.dart';
import 'package:snote/canvas_engine/input/stroke_sample_buffer.dart';
import 'package:snote/canvas_engine/input/stylus_gesture_lock.dart';
import 'package:snote/canvas_engine/input/viewport_transform.dart';
import 'package:snote/canvas_engine/models/stroke.dart';

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
    expect(
      frame.livePoints.any(
        (point) => identical(point, frame.realPoints.last),
      ),
      isTrue,
    );
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

    if (frame.predictedPoint != null) {
      expect(
        pipeline.realPoints.any(
          (p) => identical(p, frame.predictedPoint),
        ),
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

  test('prediction confidence actually reconciles against the next real sample', () {
    final predictor = InkPrediction();
    const points = <StrokePoint>[
      StrokePoint(
        position: Offset(0, 0),
        timestamp: 0,
      ),
      StrokePoint(
        position: Offset(20, 0),
        timestamp: 10,
      ),
    ];

    final prediction = predictor.predict(points);
    expect(prediction, isNotNull);
    final before = predictor.confidence;
    predictor.reconcile(
      const StrokePoint(position: Offset(100, 50), timestamp: 20),
      prediction,
    );
    expect(predictor.confidence, lessThan(before));
  });

  test('redundant samples are suppressed without moving the physical point', () {
    final buffer = StrokeSampleBuffer();
    expect(
      buffer.add(
        const StrokePoint(
          position: Offset(10, 10),
          timestamp: 0,
          pressure: .5,
        ),
      ),
      isTrue,
    );
    expect(
      buffer.add(
        const StrokePoint(
          position: Offset(10.02, 10.02),
          timestamp: .5,
          pressure: .5,
        ),
      ),
      isFalse,
    );
    expect(buffer.last!.position, const Offset(10, 10));
  });

  test('adaptive finalization preserves exact physical endpoint', () {
    const points = <StrokePoint>[
      StrokePoint(position: Offset(0, 0), timestamp: 0),
      StrokePoint(position: Offset(20, 20), timestamp: 10),
      StrokePoint(position: Offset(40, 40), timestamp: 20),
    ];
    final result = const AdaptiveStabilizer().finalize(points);
    expect(result.last.position, const Offset(40, 40));
  });

  test('stylus owns the canvas until pointer-up', () {
    final lock = StylusGestureLock();
    final stylus = const PointerDownEvent(
      pointer: 7,
      kind: PointerDeviceKind.stylus,
      position: Offset(1, 1),
    );
    expect(lock.begin(stylus), isTrue);
    expect(lock.isLocked, isTrue);
    expect(
      lock.begin(
        const PointerDownEvent(
          pointer: 8,
          kind: PointerDeviceKind.stylus,
        ),
      ),
      isFalse,
    );
    lock.end(
      const PointerUpEvent(
        pointer: 7,
        kind: PointerDeviceKind.stylus,
      ),
    );
    expect(lock.isLocked, isFalse);
  });

  test('viewport transform round-trips coordinates', () {
    const transform = ViewportTransform(
      scale: 2,
      pan: Offset(25, 40),
    );
    const documentPoint = Offset(120, 80);
    final viewPoint = transform.toView(documentPoint);
    expect(
      transform.toDocument(viewPoint).dx,
      closeTo(documentPoint.dx, .0001),
    );
    expect(
      transform.toDocument(viewPoint).dy,
      closeTo(documentPoint.dy, .0001),
    );
  });
}
