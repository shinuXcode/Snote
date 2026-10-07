import 'dart:ui';

enum PenType {
  ballpoint,
  fountain,
  pencil,
  highlighter,
  pointer,
}

enum CanvasTool {
  ballpoint,
  fountain,
  pencil,
  highlighter,
  eraser,
  lasso,
  line,
  arrow,
  rectangle,
  ellipse,
  triangle,
}

extension CanvasToolX on CanvasTool {
  bool get isPen => this == CanvasTool.ballpoint ||
      this == CanvasTool.fountain ||
      this == CanvasTool.pencil ||
      this == CanvasTool.highlighter;

  bool get isShape => this == CanvasTool.line ||
      this == CanvasTool.arrow ||
      this == CanvasTool.rectangle ||
      this == CanvasTool.ellipse ||
      this == CanvasTool.triangle;

  PenType get penType {
    switch (this) {
      case CanvasTool.fountain:
        return PenType.fountain;
      case CanvasTool.pencil:
        return PenType.pencil;
      case CanvasTool.highlighter:
        return PenType.highlighter;
      default:
        return PenType.ballpoint;
    }
  }

  String get label {
    switch (this) {
      case CanvasTool.ballpoint: return 'Pen';
      case CanvasTool.fountain: return 'Fountain';
      case CanvasTool.pencil: return 'Pencil';
      case CanvasTool.highlighter: return 'Highlighter';
      case CanvasTool.eraser: return 'Eraser';
      case CanvasTool.lasso: return 'Lasso';
      case CanvasTool.line: return 'Line';
      case CanvasTool.arrow: return 'Arrow';
      case CanvasTool.rectangle: return 'Rectangle';
      case CanvasTool.ellipse: return 'Circle';
      case CanvasTool.triangle: return 'Triangle';
    }
  }

  String get iconName => label;
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
