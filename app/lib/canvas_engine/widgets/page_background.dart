import 'dart:math' as math;
import 'package:flutter/material.dart';

enum PageTemplate {
  blank,
  lined,
  grid,
  dotted,
  cornell,
  dotGrid,
  isometric,
  planner,
  music,
  checklist,
}

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
    this.lineColor = const Color(0xFFE0E4EA),
    this.spacing = 28,
    this.lineOpacity = 1,
    this.cornellAssist = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(paperColor, BlendMode.srcOver);
    final p = Paint()
      ..color = lineColor.withValues(alpha: lineOpacity.clamp(0, 1))
      ..strokeWidth = .7;

    final s = spacing.clamp(10, 80);

    switch (template) {
      case PageTemplate.blank:
        break;
      case PageTemplate.lined:
        for (double y = s; y < size.height; y += s) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
        }
      case PageTemplate.grid:
        for (double x = 0; x < size.width; x += s) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
        }
        for (double y = 0; y < size.height; y += s) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
        }
      case PageTemplate.dotted:
        final dot = Paint()..color = p.color;
        for (double y = s * .42; y < size.height; y += s) {
          for (double x = s * .42; x < size.width; x += s) {
            canvas.drawCircle(Offset(x, y), 1.1, dot);
          }
        }
      case PageTemplate.cornell:
        for (double y = s; y < size.height - 180; y += s) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
        }
        _drawCornell(canvas, size, p);
      case PageTemplate.dotGrid:
        final dot = Paint()..color = p.color;
        for (double y = s * .5; y < size.height; y += s) {
          for (double x = s * .5; x < size.width; x += s) {
            canvas.drawCircle(Offset(x, y), 1, dot);
          }
        }
        for (double x = 0; x < size.width; x += s * 5) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), p..strokeWidth=.45);
        }
        for (double y = 0; y < size.height; y += s * 5) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), p..strokeWidth=.45);
        }
      case PageTemplate.isometric:
        final h = s * .866;
        for (double y = -size.height; y < size.height * 2; y += h) {
          canvas.drawLine(Offset(-size.width, y), Offset(size.width * 2, y + size.width * .577), p);
        }
        for (double y = -size.height; y < size.height * 2; y += h) {
          canvas.drawLine(Offset(-size.width, y), Offset(size.width * 2, y - size.width * .577), p);
        }
      case PageTemplate.planner:
        for (double y = s; y < size.height; y += s) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
        }
        final header = Paint()..color = p.color..strokeWidth = 1.2;
        canvas.drawLine(Offset(0, s * 2), Offset(size.width, s * 2), header);
      case PageTemplate.music:
        final staff = s * .62;
        for (double y = s; y < size.height; y += staff * 8) {
          for (var i = 0; i < 5; i++) {
            final yy = y + i * staff;
            canvas.drawLine(Offset(0, yy), Offset(size.width, yy), p);
          }
        }
      case PageTemplate.checklist:
        for (double y = s; y < size.height; y += s * 1.5) {
          final box = Rect.fromLTWH(12, y - 10, 14, 14);
          canvas.drawRect(box, p);
          canvas.drawLine(Offset(36, y + 3), Offset(size.width, y + 3), p);
        }
    }

    if (cornellAssist && template != PageTemplate.cornell) {
      _drawCornell(canvas, size, p);
    }
  }

  void _drawCornell(Canvas canvas, Size size, Paint base) {
    final divider = Paint()
      ..color = base.color.withValues(alpha: (base.color.a * .9).clamp(0, 1))
      ..strokeWidth = 1.15;
    canvas.drawLine(Offset(size.width * .27, 0), Offset(size.width * .27, size.height), divider);
    canvas.drawLine(Offset(0, size.height - 180), Offset(size.width, size.height - 180), divider);
  }

  @override
  bool shouldRepaint(covariant PageBackground oldDelegate) =>
      oldDelegate.template != template ||
      oldDelegate.paperColor != paperColor ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.spacing != spacing ||
      oldDelegate.lineOpacity != lineOpacity ||
      oldDelegate.cornellAssist != cornellAssist;
}
