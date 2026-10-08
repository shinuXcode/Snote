import 'dart:ui';
import '../models/stroke.dart';

/// Lightweight uniform-grid index for committed strokes.
/// Rebuilt only after a document mutation; pointer-move lookups are read-only.
class StrokeSpatialIndex {
  final double cellSize;
  final Map<int, List<int>> _cells = <int, List<int>>{};

  StrokeSpatialIndex({this.cellSize = 96});

  void rebuild(List<Stroke> strokes) {
    _cells.clear();
    for (var i = 0; i < strokes.length; i++) {
      final points = strokes[i].points;
      if (points.isEmpty) continue;
      var left = points.first.position.dx;
      var right = left;
      var top = points.first.position.dy;
      var bottom = top;
      for (final p in points.skip(1)) {
        left = left < p.position.dx ? left : p.position.dx;
        right = right > p.position.dx ? right : p.position.dx;
        top = top < p.position.dy ? top : p.position.dy;
        bottom = bottom > p.position.dy ? bottom : p.position.dy;
      }
      final minX = _cell(left);
      final maxX = _cell(right);
      final minY = _cell(top);
      final maxY = _cell(bottom);
      for (var y = minY; y <= maxY; y++) {
        for (var x = minX; x <= maxX; x++) {
          (_cells[_key(x, y)] ??= <int>[]).add(i);
        }
      }
    }
  }

  Iterable<int> candidates(Offset point, double radius) {
    final minX = _cell(point.dx - radius);
    final maxX = _cell(point.dx + radius);
    final minY = _cell(point.dy - radius);
    final maxY = _cell(point.dy + radius);
    final result = <int>{};
    for (var y = minY; y <= maxY; y++) {
      for (var x = minX; x <= maxX; x++) {
        final values = _cells[_key(x, y)];
        if (values != null) result.addAll(values);
      }
    }
    return result;
  }

  int _cell(double value) => (value / cellSize).floor();
  int _key(int x, int y) => Object.hash(x, y);
}
