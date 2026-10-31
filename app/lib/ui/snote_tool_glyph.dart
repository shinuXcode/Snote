import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../canvas_engine/models/pen_config.dart';

/// Small, background-free vector glyphs for the writing tools.
class SnoteToolGlyph extends StatelessWidget {
  const SnoteToolGlyph({
    super.key,
    required this.tool,
    required this.color,
    this.size = 18,
  });

  final CanvasTool tool;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: _SnoteToolGlyphPainter(tool, color),
      );
}

class _SnoteToolGlyphPainter extends CustomPainter {
  const _SnoteToolGlyphPainter(this.tool, this.color);

  final CanvasTool tool;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width, size.height) / 24;
    canvas.save();
    canvas.translate((size.width - 24 * scale) / 2, (size.height - 24 * scale) / 2);
    canvas.scale(scale);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    final fill = Paint()
      ..color = color.withValues(alpha: .16)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    void line(Offset a, Offset b, [Paint? paint]) => canvas.drawLine(a, b, paint ?? stroke);
    void polygon(List<Offset> points, {bool filled = false}) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      path.close();
      canvas.drawPath(path, filled ? fill : stroke);
      if (filled) canvas.drawPath(path, stroke);
    }

    switch (tool) {
      case CanvasTool.fountain:
        polygon(const <Offset>[
          Offset(12, 2.5), Offset(5.5, 14), Offset(12, 21.5), Offset(18.5, 14),
        ], filled: true);
        line(const Offset(12, 4), const Offset(12, 19));
        canvas.drawCircle(const Offset(12, 11), 1.25, fill);
        line(const Offset(8, 15), const Offset(16, 15));
        break;
      case CanvasTool.ballpoint:
        canvas.save();
        canvas.translate(12, 12);
        canvas.rotate(-math.pi / 4);
        canvas.drawRRect(
          RRect.fromRectAndRadius(const Rect.fromLTWH(8, -7, 8, 15), const Radius.circular(2.5)),
          fill,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(const Rect.fromLTWH(8, -7, 8, 15), const Radius.circular(2.5)),
          stroke,
        );
        polygon(const <Offset>[Offset(8, 8), Offset(16, 8), Offset(12, 13)]);
        line(const Offset(10.5, -7), const Offset(10.5, -9));
        line(const Offset(13.5, -7), const Offset(13.5, -9));
        canvas.restore();
        break;
      case CanvasTool.pencil:
        canvas.save();
        canvas.translate(12, 12);
        canvas.rotate(-math.pi / 4);
        polygon(const <Offset>[
          Offset(12, -10), Offset(16, -6), Offset(16, 7), Offset(12, 12),
          Offset(8, 7), Offset(8, -6),
        ], filled: true);
        line(const Offset(8, -6), const Offset(16, -6));
        line(const Offset(8, 7), const Offset(16, 7));
        canvas.restore();
        break;
      case CanvasTool.highlighter:
        canvas.save();
        canvas.translate(12, 12);
        canvas.rotate(-math.pi / 4);
        canvas.drawRRect(
          RRect.fromRectAndRadius(const Rect.fromLTWH(6, -9, 12, 15), const Radius.circular(2)),
          fill,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(const Rect.fromLTWH(6, -9, 12, 15), const Radius.circular(2)),
          stroke,
        );
        line(const Offset(6, 2), const Offset(18, 2));
        polygon(const <Offset>[Offset(6, 6), Offset(18, 6), Offset(15, 10), Offset(9, 10)]);
        canvas.restore();
        break;
      case CanvasTool.marker:
        canvas.save();
        canvas.translate(12, 12);
        canvas.rotate(-math.pi / 4);
        canvas.drawRRect(
          RRect.fromRectAndRadius(const Rect.fromLTWH(7, -9, 10, 18), const Radius.circular(3)),
          fill,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(const Rect.fromLTWH(7, -9, 10, 18), const Radius.circular(3)),
          stroke,
        );
        line(const Offset(7, 4), const Offset(17, 4));
        canvas.restore();
        break;
      case CanvasTool.brush:
        line(const Offset(6, 18), const Offset(16, 8));
        line(const Offset(4, 20), const Offset(8, 16));
        polygon(const <Offset>[Offset(15, 8), Offset(18, 3), Offset(21, 6), Offset(17, 11)], filled: true);
        canvas.drawCircle(const Offset(5, 19), 1.4, fill);
        break;
      case CanvasTool.eraser:
      case CanvasTool.pixelEraser:
        canvas.save();
        canvas.translate(12, 12);
        canvas.rotate(-math.pi / 4);
        canvas.drawRRect(
          RRect.fromRectAndRadius(const Rect.fromLTWH(5, -7, 14, 14), const Radius.circular(2.5)),
          fill,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(const Rect.fromLTWH(5, -7, 14, 14), const Radius.circular(2.5)),
          stroke,
        );
        line(const Offset(12, -7), const Offset(12, 7));
        if (tool == CanvasTool.pixelEraser) {
          canvas.drawRect(const Rect.fromLTWH(6.5, -5.5, 2, 2), stroke);
          canvas.drawRect(const Rect.fromLTWH(15, 2.5, 2, 2), stroke);
        }
        canvas.restore();
        break;
      default:
        canvas.drawCircle(const Offset(12, 12), 8, stroke);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SnoteToolGlyphPainter oldDelegate) =>
      oldDelegate.tool != tool || oldDelegate.color != color;
}
