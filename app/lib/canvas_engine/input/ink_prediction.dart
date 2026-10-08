import 'dart:math' as math;
import '../models/stroke.dart';

/// Conservative short-horizon predictor used only for transient live ink.
/// Predicted samples are never returned to the document model.
class InkPrediction {
  double confidence = 1.0;

  StrokePoint? predict(List<StrokePoint> points) {
    if (points.length < 2) return null;

    final b = points[points.length - 1];
    final a = points[points.length - 2];
    final dt = math.max(.5, b.timestamp - a.timestamp);
    final velocity = (b.position - a.position) / dt;
    final speed = velocity.distance;
    if (speed < .18) return null;

    if (points.length >= 3) {
      final previous = points[points.length - 3];
      final previousDt = math.max(.5, a.timestamp - previous.timestamp);
      final previousVelocity =
          (a.position - previous.position) / previousDt;
      final previousSpeed = previousVelocity.distance;
      if (previousSpeed > .18) {
        final alignment =
            (velocity.dx * previousVelocity.dx +
                    velocity.dy * previousVelocity.dy) /
                (speed * previousSpeed);
        if (alignment < .70) return null;
      }
    }

    final horizon =
        (2.0 + speed * 1.35).clamp(2.0, 6.0).toDouble() * confidence;

    return b.copyWith(
      position: b.position + velocity * horizon,
      timestamp: b.timestamp + horizon,
    );
  }

  void reconcile(StrokePoint actual, StrokePoint? prediction) {
    if (prediction == null) return;
    final error = (actual.position - prediction.position).distance;
    if (error > 14) {
      confidence = (confidence * .55).clamp(.18, 1.0).toDouble();
    } else if (error < 3.5) {
      confidence = (confidence + .035).clamp(.18, 1.0).toDouble();
    }
  }

  void reset() => confidence = 1.0;
}
