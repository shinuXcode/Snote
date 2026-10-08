import 'package:flutter/gestures.dart';

import '../algorithms/adaptive_stabilizer.dart';
import '../models/stroke.dart';
import 'ink_prediction.dart';
import 'ink_sample.dart';
import 'stroke_sample_buffer.dart';

/// The canonical high-frequency handwriting pipeline:
///
/// PointerEvent -> normalized sample -> canonical raw buffer -> transient
/// prediction -> live repaint -> commit-time stabilization.
///
/// No predicted point is ever inserted into the document model.
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
    int maxSamples = 8192,
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
    _append(sample);

    return InkFrame(
      realPoints: _buffer.points,
      livePoints: _livePoints,
      predictedPoint: null,
      predictionHorizonMs: 0,
    );
  }

  InkFrame update(PointerMoveEvent event) {
    // Reconcile against the prediction that was visible during the previous
    // frame BEFORE replacing it with the new actual sample.
    final oldPrediction = _previousPrediction;
    final sample = InkSample.fromEvent(event);
    final actual = sample.toStrokePoint();
    _predictor.reconcile(actual, oldPrediction);

    if (oldPrediction != null) {
      _livePoints.removeWhere((point) => identical(point, oldPrediction));
    }
    _previousPrediction = null;

    _append(sample);

    final prediction = _predictor.predict(_buffer.points);
    if (prediction != null) {
      _livePoints.add(prediction);
      _previousPrediction = prediction;
    }

    return InkFrame(
      realPoints: _buffer.points,
      livePoints: _livePoints,
      predictedPoint: prediction,
      predictionHorizonMs: prediction == null
          ? 0
          : prediction.timestamp - actual.timestamp,
    );
  }

  /// Finalize using only real samples. The physical pointer-up sample is
  /// authoritative and remains the exact final endpoint.
  List<StrokePoint> finish(PointerUpEvent event) {
    final oldPrediction = _previousPrediction;
    final sample = InkSample.fromEvent(event);
    final actual = sample.toStrokePoint();

    _predictor.reconcile(actual, oldPrediction);

    if (oldPrediction != null) {
      _livePoints.removeWhere((point) => identical(point, oldPrediction));
    }
    _previousPrediction = null;

    _append(sample);

    final result = _stabilizer.finalize(_buffer.points);
    if (result.isNotEmpty && result.last.position != actual.position) {
      result[result.length - 1] = actual;
    }
    return result;
  }

  void _append(InkSample sample) {
    final timestamp = sample.timestampMs;
    if (_lastTimestamp != null) {
      final gap = timestamp - _lastTimestamp!;
      // Flutter can occasionally deliver equal timestamps. Keep the physical
      // sample but never manufacture a negative time interval.
      if (gap < 0) return;
    }

    final point = sample.toStrokePoint();
    final added = _buffer.add(point);
    if (added) {
      _livePoints.add(point);
    }
    _lastTimestamp = timestamp;
  }
}
