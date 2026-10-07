import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import '../models/stroke.dart';

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
  final List<StrokePoint> _realPoints = <StrokePoint>[];
  StrokePoint? _lastFiltered;
  Offset? _lastDirection;
  StrokePoint? _previousPrediction;
  double _predictionConfidence = 1;

  InkInputPipeline({this.smoothing = .72});

  List<StrokePoint> get realPoints =>
      List<StrokePoint>.unmodifiable(_realPoints);

  void reset() {
    _realPoints.clear();
    _lastFiltered = null;
    _lastDirection = null;
    _previousPrediction = null;
    _predictionConfidence = 1;
  }

  InkFrame begin(PointerDownEvent event) {
    reset();
    final point = _append(
      event.localPosition,
      event.pressure,
      event.timeStamp,
      event.tilt,
      event.orientation,
    );
    return InkFrame(
      realPoints: realPoints,
      livePoints: List<StrokePoint>.unmodifiable(_realPoints),
      predictedPoint: null,
      predictionHorizonMs: 0,
    );
  }

  InkFrame update(PointerMoveEvent event) {
    final point = _append(
      event.localPosition,
      event.pressure,
      event.timeStamp,
      event.tilt,
      event.orientation,
    );
    _reconcilePrediction(point);

    final prediction = _predict();
    final live = <StrokePoint>[..._realPoints];
    if (prediction != null) live.add(prediction);

    return InkFrame(
      realPoints: realPoints,
      livePoints: List<StrokePoint>.unmodifiable(live),
      predictedPoint: prediction,
      predictionHorizonMs:
          prediction == null ? 0 : prediction.timestamp - point.timestamp,
    );
  }

  List<StrokePoint> finish(PointerUpEvent event) {
    _append(
      event.localPosition,
      event.pressure,
      event.timeStamp,
      event.tilt,
      event.orientation,
    );
    return realPoints;
  }

  StrokePoint _append(
    Offset rawPosition,
    double rawPressure,
    Duration timeStamp,
    double tilt,
    double orientation,
  ) {
    final normalized = StrokePoint(
      position: rawPosition,
      pressure:
          rawPressure.isNaN ? 1 : rawPressure.clamp(0, 1).toDouble(),
      timestamp: timeStamp.inMicroseconds / 1000,
      tilt: tilt.isNaN ? 0 : tilt,
      orientation: orientation.isNaN ? 0 : orientation,
    );

    final filteredPosition = _filterPosition(normalized);
    final filtered = normalized.copyWith(position: filteredPosition);
    _realPoints.add(filtered);
    _lastFiltered = filtered;
    return filtered;
  }

  Offset _filterPosition(StrokePoint next) {
    final previous = _lastFiltered;
    if (previous == null) return next.position;

    final dt = math.max(.25, next.timestamp - previous.timestamp);
    final delta = next.position - previous.position;
    final distance = delta.distance;
    final speed = distance / dt;
    final speedNorm = (speed / 2.4).clamp(0, 1).toDouble();
    final stabilization = smoothing.clamp(.15, .9).toDouble();

    var alpha = .70 -
        stabilization * .25 +
        speedNorm * stabilization * .48;

    final direction =
        distance < .01 ? _lastDirection : delta / distance;
    if (direction != null && _lastDirection != null) {
      final dot = (direction.dx * _lastDirection!.dx +
              direction.dy * _lastDirection!.dy)
          .clamp(-1, 1)
          .toDouble();
      final angle = math.acos(dot);
      if (angle > .55) alpha = math.max(alpha, .88);
    }

    alpha = alpha.clamp(.45, .96).toDouble();
    final filtered = Offset(
      previous.position.dx + delta.dx * alpha,
      previous.position.dy + delta.dy * alpha,
    );
    if (distance >= .1) _lastDirection = direction;
    return filtered;
  }

  StrokePoint? _predict() {
    if (_realPoints.length < 2 || _lastFiltered == null) return null;

    final a = _realPoints[_realPoints.length - 2];
    final b = _realPoints.last;
    final dt = math.max(.25, b.timestamp - a.timestamp);
    final velocity = (b.position - a.position) / dt;
    final speed = velocity.distance;
    if (speed < .18) return null;

    final direction = velocity / speed;
    if (_lastDirection != null) {
      final alignment =
          direction.dx * _lastDirection!.dx +
          direction.dy * _lastDirection!.dy;
      if (alignment < .72) return null;
    }

    final baseHorizon =
        (2.5 + speed * 1.7).clamp(2.5, 8.0).toDouble();
    final horizon = baseHorizon * _predictionConfidence;
    final predicted = b.copyWith(
      position: b.position + velocity * horizon,
      timestamp: b.timestamp + horizon,
    );
    _previousPrediction = predicted;
    return predicted;
  }

  void _reconcilePrediction(StrokePoint actual) {
    final previous = _previousPrediction;
    if (previous == null) return;
    final error = (actual.position - previous.position).distance;
    if (error > 18) {
      _predictionConfidence =
          (_predictionConfidence * .55).clamp(.25, 1).toDouble();
    } else if (error < 5) {
      _predictionConfidence =
          (_predictionConfidence + .035).clamp(.25, 1).toDouble();
    }
    _previousPrediction = null;
  }
}
