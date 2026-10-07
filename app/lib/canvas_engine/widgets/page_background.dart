import 'package:flutter/material.dart';

enum PageTemplate { blank, lined, grid, dotted, cornell, dotGrid, isometric, planner, music, checklist }

class PageBackground extends CustomPainter {
  final PageTemplate template;
  final Color paperColor;
  final Color lineColor;
  final double spacing;
  final double lineOpacity;
  final bool cornellAssist;

  const PageBackground({
    required this.template,
    this.paperColor = Colors.white,
    this.lineColor = const Color(0xffe0e4ea),
    this.spacing = 28,
    this.lineOpacity = .85,
    this.cornellAssist = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(paperColor, BlendMode.srcOver);
    final double s = spacing.clamp(10, 80).toDouble();
    final line = Paint()..color = lineColor.withValues(alpha: lineOpacity.clamp(0, 1))..strokeWidth = .7;

    switch (template) {
      case PageTemplate.blank:
        break;
      case PageTemplate.lined:
        for (double y = s; y < size.height; y += s) canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
      case PageTemplate.grid:
        for (double x = 0; x < size.width; x += s) canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
        for (double y = 0; y < size.height; y += s) canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
      case PageTemplate.dotted:
        final dot = Paint()..color = line.color;
        for (double y = s * .42; y < size.height; y += s) {
          for (double x = s * .42; x < size.width; x += s) canvas.drawCircle(Offset(x, y), 1.1, dot);
        }
      case PageTemplate.cornell:
        for (double y = s; y < size.height - 180; y += s) canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
        _cornell(canvas, size);
      case PageTemplate.dotGrid:
        final dot = Paint()..color = line.color;
        for (double y = s * .5; y < size.height; y += s) {
          for (double x = s * .5; x < size.width; x += s) canvas.drawCircle(Offset(x, y), 1, dot);
        }
        for (double x = 0; x < size.width; x += s * 5) canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
        for (double y = 0; y < size.height; y += s * 5) canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
      case PageTemplate.isometric:
        final h = s * .866;
        for (double y = -size.height; y < size.height * 2; y += h) {
          canvas.drawLine(Offset(-size.width, y), Offset(size.width * 2, y + size.width * .577), line);
          canvas.drawLine(Offset(-size.width, y), Offset(size.width * 2, y - size.width * .577), line);
        }
      case PageTemplate.planner:
        for (double y = s; y < size.height; y += s) canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
        final header = Paint()..color = line.color..strokeWidth = 1.2;
        canvas.drawLine(Offset(0, s * 2), Offset(size.width, s * 2), header);
      case PageTemplate.music:
        final staff = s * .62;
        for (double y = s; y < size.height; y += staff * 8) {
          for (var i = 0; i < 5; i++) canvas.drawLine(Offset(0, y + i * staff), Offset(size.width, y + i * staff), line);
        }
      case PageTemplate.checklist:
        for (double y = s; y < size.height; y += s * 1.5) {
          canvas.drawRect(Rect.fromLTWH(12, y - 10, 14, 14), line);
          canvas.drawLine(Offset(36, y + 3), Offset(size.width, y + 3), line);
        }
    }

    if (cornellAssist && template != PageTemplate.cornell) _cornell(canvas, size);
  }

  void _cornell(Canvas canvas, Size size) {
    final p = Paint()..color = lineColor.withValues(alpha: .9)..strokeWidth = 1.1;
    canvas.drawLine(Offset(size.width * .27, 0), Offset(size.width * .27, size.height), p);
    canvas.drawLine(Offset(0, size.height - 180), Offset(size.width, size.height - 180), p);
  }

  @override
  bool shouldRepaint(covariant PageBackground old) =>
      old.template != template || old.paperColor != paperColor || old.lineColor != lineColor ||
      old.spacing != spacing || old.lineOpacity != lineOpacity || old.cornellAssist != cornellAssist;
}
