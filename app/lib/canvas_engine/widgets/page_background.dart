import 'package:flutter/material.dart';

enum PageTemplate { blank, lined, grid, dotted, cornell }

class PageBackground extends CustomPainter {
  final PageTemplate template;
  final Color paperColor;
  final Color lineColor;

  const PageBackground({
    required this.template,
    this.paperColor = Colors.white,
    this.lineColor = const Color(0xFFE2E6EF),
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(paperColor);

    final p = Paint()
      ..color = lineColor
      ..strokeWidth = 0.7;

    const spacing = 28.0;

    switch (template) {
      case PageTemplate.blank:
        return;
      case PageTemplate.lined:
        for (double y = spacing; y < size.height; y += spacing) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
        }
      case PageTemplate.grid:
        for (double x = 0; x < size.width; x += spacing) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
        }
        for (double y = 0; y < size.height; y += spacing) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
        }
      case PageTemplate.dotted:
        final dot = Paint()..color = lineColor;
        for (double y = 12; y < size.height; y += spacing) {
          for (double x = 12; x < size.width; x += spacing) {
            canvas.drawCircle(Offset(x, y), 1.15, dot);
          }
        }
      case PageTemplate.cornell:
        for (double y = spacing; y < size.height; y += spacing) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
        }
        final divider = Paint()
          ..color = const Color(0xFFC8CDD7)
          ..strokeWidth = 1.2;
        canvas.drawLine(
          Offset(size.width * .27, 0),
          Offset(size.width * .27, size.height),
          divider,
        );
        canvas.drawLine(
          Offset(0, size.height - 180),
          Offset(size.width, size.height - 180),
          divider,
        );
    }
  }

  @override
  bool shouldRepaint(covariant PageBackground oldDelegate) =>
      oldDelegate.template != template ||
      oldDelegate.paperColor != paperColor ||
      oldDelegate.lineColor != lineColor;
}
