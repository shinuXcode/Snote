import 'dart:math' as math;
import 'dart:ui';

import '../models/stroke.dart';

/// Commit-time denoising with a strict displacement ceiling.
///
/// The ceiling prevents the final stroke from visibly jumping away from the
/// live stroke when prediction is removed and the document layer is committed.
class AdaptiveStabilizer {
  final double strength;

  const AdaptiveStabilizer({this.strength = .42});

  List<StrokePoint> finalize(List<StrokePoint> source) {
    if (source.length < 3 || strength <= .01) {
      return List<StrokePoint>.of(source);
    }

    final result = <StrokePoint>[source.first];
    final safeStrength = strength.clamp(.05, .65).toDouble();

    for (var i = 1; i < source.length - 1; i++) {
      final previous = source[i - 1];
      final current = source[i];
      final next = source[i + 1];

      final dt = math.max(.5, next.timestamp - previous.timestamp);
      final speed = (next.position - previous.position).distance / dt;
      final velocityFactor = (1.0 - (speed / 2.8).clamp(0.0, 1.0));
      final amount = safeStrength * velocityFactor * .32;

      final neighbor = Offset(
        (previous.position.dx +
                current.position.dx +
                next.position.dx) /
            3,
        (previous.position.dy +
                current.position.dy +
                next.position.dy) /
            3,
      );

      var delta = (neighbor - current.position) * amount;
      if (delta.distance > .75) {
        delta = delta / delta.distance * .75;
      }

      result.add(current.copyWith(position: current.position + delta));
    }

    // The physical pen-up endpoint is authoritative.
    result.add(source.last);
    return result;
  }
}
