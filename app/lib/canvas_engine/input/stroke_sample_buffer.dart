import 'dart:math' as math;
import 'dart:ui';

import '../models/stroke.dart';

/// Allocation-light canonical stroke sample buffer.
class StrokeSampleBuffer {
  final int capacity;
  final List<StrokePoint> _points = <StrokePoint>[];

  StrokeSampleBuffer({this.capacity = 8192});

  List<StrokePoint> get points => _points;
  StrokePoint? get last => _points.isEmpty ? null : _points.last;
  int get length => _points.length;

  void clear() => _points.clear();

  bool add(StrokePoint point) {
    if (_points.isNotEmpty) {
      final previous = _points.last;
      final dt = point.timestamp - previous.timestamp;
      final distance = (point.position - previous.position).distance;
      final metadataChanged =
          (point.pressure - previous.pressure).abs() >= .008 ||
          (point.tilt - previous.tilt).abs() >= .004 ||
          (point.orientation - previous.orientation).abs() >= .004;

      if (!metadataChanged && distance < .08 && dt >= 0 && dt < 1.0) {
        return false;
      }
    }

    if (_points.length == capacity) {
      _points.removeAt(0);
    }
    _points.add(point);
    return true;
  }

  Offset velocityAt(int index) {
    if (_points.length < 2) return Offset.zero;
    final i = index.clamp(1, _points.length - 1).toInt();
    final a = _points[i - 1];
    final b = _points[i];
    final dt = math.max(.25, b.timestamp - a.timestamp);
    return (b.position - a.position) / dt;
  }

  double speedAt(int index) => velocityAt(index).distance;
}
