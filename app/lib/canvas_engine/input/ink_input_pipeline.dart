import 'package:flutter/gestures.dart';

import '../algorithms/adaptive_stabilizer.dart';
import '../models/stroke.dart';
import 'ink_prediction.dart';
import 'ink_sample.dart';
import 'stroke_sample_buffer.dart';

class InkFrame {
  final List<StrokePoint> realPoints;
  final List<StrokePoint> livePoints;
  final StrokePoint? predictedPoint;
  final double predictionHorizonMs;

  const InkFrame({
    required this.realPoints,
    required this.livePoints,
    required this.predictedPoint,
    required this.predictionHorizonMs,
  });
}

/// Low-latency handwriting pipeline.
///
/// Raw samples are the source of truth. The live layer uses an adaptive
/// first-order tail filter only on the newest point, then optionally extends
/// the visible tail with a very short prediction. Finalization uses raw
/// samples plus commit-time stabilization. Predicted points never persist.
class InkInputPipeline {
  final double smoothing;
  final StrokeSampleBuffer _buffer;
  final InkPrediction _predictor = InkPrediction();
  late final AdaptiveStabilizer _stabilizer;

  final List<StrokePoint> _livePoints = <StrokePoint>[];
  StrokePoint? _previousPrediction;
  double? _lastTimestamp;

  InkInputPipeline({
    this.smoothing = .72,
    int maxSamples = 16384,
  }) : _buffer = StrokeSampleBuffer(capacity: maxSamples) {
    _stabilizer = AdaptiveStabilizer(
      strength: smoothing.clamp(.05, .65).toDouble(),
    );
  }

  List<StrokePoint> get realPoints => _buffer.points;
  List<StrokePoint> get livePoints => _livePoints;

  void reset() {
    _buffer.clear();
    _livePoints.clear();
    _previousPrediction = null;
    _lastTimestamp = null;
    _predictor.reset();
  }

  InkFrame begin(PointerDownEvent event) {
    reset();
    final sample = InkSample.fromEvent(event);
    final point = sample.toStrokePoint();
    _append(sample, point);
    _livePoints.add(point);
    _lastTimestamp = sample.timestampMs;

    return InkFrame(
      realPoints: _buffer.points,
      livePoints: _livePoints,
      predictedPoint: null,
      predictionHorizonMs: 0,
    );
  }

  InkFrame update(PointerMoveEvent event) {
    final oldPrediction = _previousPrediction;
    final sample = InkSample.fromEvent(event);
    final actual = sample.toStrokePoint();

    // Reconcile while the previous prediction is still represented in the
    // live layer, then remove it. This feeds the prediction controller with
    // real error information instead of losing it.
    _predictor.reconcile(actual, oldPrediction);
    if (oldPrediction != null) {
      _livePoints.removeWhere((point) => identical(point, oldPrediction));
    }
    _previousPrediction = null;

    final appended = _append(sample, actual);
    if (!appended || _buffer.last == null) {
      return _frame(null, actual);
    }

    // The newest real sample is always the visible endpoint. Continuous
    // ribbon geometry smooths the path without moving the tip away from the
    // physical stylus location.
    _livePoints.add(actual);

    final prediction = _predictor.predict(_buffer.points);
    if (prediction != null) {
      _livePoints.add(prediction);
      _previousPrediction = prediction;
    }

    return _frame(prediction, actual);
  }

  List<StrokePoint> finish(PointerUpEvent event) {
    final oldPrediction = _previousPrediction;
    final sample = InkSample.fromEvent(event);
    final actual = sample.toStrokePoint();

    _predictor.reconcile(actual, oldPrediction);
    if (oldPrediction != null) {
      _livePoints.removeWhere((point) => identical(point, oldPrediction));
    }
    _previousPrediction = null;

    _append(sample, actual);

    final result = _stabilizer.finalize(_buffer.points);
    if (result.isNotEmpty) {
      result[result.length - 1] = actual;
    }
    return result;
  }

  InkFrame _frame(StrokePoint? prediction, StrokePoint actual) {
    return InkFrame(
      realPoints: _buffer.points,
      livePoints: _livePoints,
      predictedPoint: prediction,
      predictionHorizonMs:
          prediction == null ? 0 : prediction.timestamp - actual.timestamp,
    );
  }

  bool _append(InkSample sample, [StrokePoint? point]) {
    final timestamp = sample.timestampMs;
    if (_lastTimestamp != null && timestamp < _lastTimestamp!) return false;
    final canonical = point ?? sample.toStrokePoint();
    final added = _buffer.add(canonical);
    if (added) _lastTimestamp = timestamp;
    return added;
  }
}