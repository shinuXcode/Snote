import 'dart:ui';

class BezierSmoother {
  final List<Offset> _points = [];

  void reset() => _points.clear();

  void add(Offset point) {
    _points.add(point);
    if (_points.length > 8) {
      _points.removeAt(0);
    }
  }

  Path buildPath() {
    final path = Path();
    if (_points.isEmpty) return path;

    path.moveTo(_points.first.dx, _points.first.dy);

    if (_points.length == 1) return path;

    for (var i = 1; i < _points.length; i++) {
      final a = _points[i - 1];
      final b = _points[i];
      final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);

      path.quadraticBezierTo(a.dx, a.dy, mid.dx, mid.dy);
    }

    final last = _points.last;
    path.lineTo(last.dx, last.dy);
    return path;
  }
}
