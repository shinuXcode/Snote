import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import '../models/stroke.dart';

/// High-frequency input state.
///
/// Live points deliberately stay close to the physical pointer position.
/// Final smoothing is applied only when the stroke is committed so filtering
/// never creates visible input lag.
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
  final List<StrokePoint> _rawPoints = <StrokePoint>[];
  final List<StrokePoint> _livePoints = <StrokePoint>[];
  StrokePoint? _previousPrediction;
  double _predictionConfidence = 1;
  bool _hasPrediction = false;

  InkInputPipeline({this.smoothing = .72});

  /// Raw, non-predicted input. This is the canonical source for finalization.
  List<StrokePoint> get realPoints => _rawPoints;

  /// Raw input plus at most one transient prediction.
  List<StrokePoint> get livePoints => _livePoints;

  void reset() {
    _rawPoints.clear();
    _livePoints.clear();
    _previousPrediction = null;
    _predictionConfidence = 1;
    _hasPrediction = false;
  }

  InkFrame begin(PointerDownEvent event) {
    reset();
    _appendRaw(event);
    return InkFrame(
      realPoints: _rawPoints,
      livePoints: _livePoints,
      predictedPoint: null,
      predictionHorizonMs: 0,
    );
  }

  InkFrame update(PointerMoveEvent event) {
    _removePrediction();
    final point = _appendRaw(event);
    _reconcilePrediction(point);

    final prediction = _predict();
    if (prediction != null) {
      _livePoints.add(prediction);
      _previousPrediction = prediction;
      _hasPrediction = true;
    }

    return InkFrame(
      realPoints: _rawPoints,
      livePoints: _livePoints,
      predictedPoint: prediction,
      predictionHorizonMs:
          prediction == null ? 0 : prediction.timestamp - point.timestamp,
    );
  }

  /// Returns a clean final stroke. Predicted points can never enter it.
  List<StrokePoint> finish(PointerUpEvent event) {
    _removePrediction();
    _appendRaw(event);
    return _smoothForCommit(_rawPoints);
  }

  StrokePoint _appendRaw(PointerEvent event) {
    final pressure = event.pressure.isNaN
        ? 1.0
        : event.pressure.clamp(0, 1).toDouble();
    final point = StrokePoint(
      position: event.localPosition,
      pressure: pressure,
      timestamp: event.timeStamp.inMicroseconds / 1000,
      tilt: event.tilt.isNaN ? 0 : event.tilt,
      orientation: event.orientation.isNaN ? 0 : event.orientation,
    );

    if (_rawPoints.isNotEmpty) {
      final previous = _rawPoints.last;
      final distance = (point.position - previous.position).distance;
      final dt = point.timestamp - previous.timestamp;

      // Suppress only truly redundant samples. Never move a point to a
      // filtered position and never drop pressure changes.
      if (distance < .08 &&
          dt < 1 &&
          (point.pressure - previous.pressure).abs() < .01) {
        return previous;
      }
    }

    _rawPoints.add(point);
    _livePoints.add(point);
    return point;
  }

  List<StrokePoint> _smoothForCommit(List<StrokePoint> source) {
    if (source.length < 3 || smoothing <= .01) {
      return List<StrokePoint>.of(source);
    }

    final result = <StrokePoint>[];
    final strength = smoothing.clamp(.05, .72).toDouble();

    result.add(source.first);

    for (var i = 1; i < source.length - 1; i++) {
      final previous = source[i - 1];
      final current = source[i];
      final next = source[i + 1];

      final dt = math.max(.5, next.timestamp - previous.timestamp);
      final speed = (next.position - previous.position).distance / dt;
      final speedNorm = (speed / 2.4).clamp(0, 1).toDouble();

      // Slow handwriting benefits from stabilization. Fast handwriting stays
      // close to the actual path to preserve responsiveness and character.
      final stabilization = strength * (1 - speedNorm) * .55;
      final neighbor = Offset(
        (previous.position.dx + current.position.dx + next.position.dx) / 3,
        (previous.position.dy + current.position.dy + next.position.dy) / 3,
      );
      final position = Offset(
        current.position.dx +
            (neighbor.dx - current.position.dx) * stabilization,
        current.position.dy +
            (neighbor.dy - current.position.dy) * stabilization,
      );

      result.add(
        current.copyWith(position: position),
      );
    }

    // Preserve the physical pen-up endpoint exactly.
    result.add(source.last);
    return result;
  }

  StrokePoint? _predict() {
    if (_rawPoints.length < 2) return null;

    final a = _rawPoints[_rawPoints.length - 2];
    final b = _rawPoints.last;
    final dt = math.max(.5, b.timestamp - a.timestamp);
    final velocity = (b.position - a.position) / dt;
    final speed = velocity.distance;

    if (speed < .18) return null;

    final direction = velocity / speed;
    if (_rawPoints.length >= 3) {
      final previous = _rawPoints[_rawPoints.length - 3];
      final previousVelocity =
          (a.position - previous.position) /
          math.max(.5, a.timestamp - previous.timestamp);
      final previousSpeed = previousVelocity.distance;
      if (previousSpeed > .18) {
        final previousDirection = previousVelocity / previousSpeed;
        final alignment = direction.dx * previousDirection.dx +
            direction.dy * previousDirection.dy;
        if (alignment < .72) return null;
      }
    }

    final baseHorizon = (2.0 + speed * 1.45).clamp(2.0, 7.0).toDouble();
    final horizon = baseHorizon * _predictionConfidence;
    return b.copyWith(
      position: b.position + velocity * horizon,
      timestamp: b.timestamp + horizon,
    );
  }

  void _removePrediction() {
    if (_hasPrediction && _livePoints.isNotEmpty) {
      final last = _livePoints.last;
      if (identical(last, _previousPrediction)) {
        _livePoints.removeLast();
      }
    }
    _previousPrediction = null;
    _hasPrediction = false;
  }

  void _reconcilePrediction(StrokePoint actual) {
    final previous = _previousPrediction;
    if (previous == null) return;

    final error = (actual.position - previous.position).distance;
    if (error > 14) {
      _predictionConfidence =
          (_predictionConfidence * .52).clamp(.2, 1).toDouble();
    } else if (error < 4) {
      _predictionConfidence =
          (_predictionConfidence + .04).clamp(.2, 1).toDouble();
    }
  }
}
