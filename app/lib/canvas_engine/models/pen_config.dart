import 'dart:ui';

enum PenType {
  ballpoint,
  fountain,
  pencil,
  highlighter,
  pointer,
}

class PenConfig {
  final PenType type;
  final Color color;
  final double size;
  final double opacity;

  const PenConfig({
    required this.type,
    required this.color,
    this.size = 3,
    this.opacity = 1,
  });
}
