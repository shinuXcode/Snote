import 'dart:ui';

enum PenType { ballpoint, fountain, pencil, highlighter, pointer }

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
  roundedRectangle,
  ellipse,
  triangle,
  circle,
  diamond,
  hexagon,
  star,
  customPolygon,
  sticker,
}

extension CanvasToolX on CanvasTool {
  bool get isPen => const {
    CanvasTool.ballpoint,
    CanvasTool.fountain,
    CanvasTool.pencil,
    CanvasTool.highlighter,
  }.contains(this);

  bool get isShape => const {
    CanvasTool.line,
    CanvasTool.arrow,
    CanvasTool.rectangle,
    CanvasTool.roundedRectangle,
    CanvasTool.ellipse,
    CanvasTool.triangle,
    CanvasTool.circle,
    CanvasTool.diamond,
    CanvasTool.hexagon,
    CanvasTool.star,
    CanvasTool.customPolygon,
  }.contains(this);

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
      case CanvasTool.roundedRectangle: return 'Rounded rectangle';
      case CanvasTool.ellipse: return 'Ellipse';
      case CanvasTool.triangle: return 'Triangle';
      case CanvasTool.circle: return 'Circle';
      case CanvasTool.diamond: return 'Diamond';
      case CanvasTool.hexagon: return 'Hexagon';
      case CanvasTool.star: return 'Star';
      case CanvasTool.customPolygon: return 'Custom polygon';
      case CanvasTool.sticker: return 'Sticker';
    }
  }
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

  PenConfig copyWith({PenType? type, Color? color, double? size, double? opacity}) {
    return PenConfig(
      type: type ?? this.type,
      color: color ?? this.color,
      size: size ?? this.size,
      opacity: opacity ?? this.opacity,
    );
  }
}
