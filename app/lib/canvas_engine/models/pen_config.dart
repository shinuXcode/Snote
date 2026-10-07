import 'dart:math' as math;
import 'dart:ui';

enum PenType { ballpoint, fountain, pencil, highlighter, pointer, marker, brush }

enum PressureCurve { soft, linear, firm, custom }

enum CanvasTool {
  ballpoint,
  fountain,
  pencil,
  highlighter,
  marker,
  brush,
  eraser,
  pixelEraser,
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
  bool get isPen => {
    CanvasTool.ballpoint,
    CanvasTool.fountain,
    CanvasTool.pencil,
    CanvasTool.highlighter,
    CanvasTool.marker,
    CanvasTool.brush,
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
      case CanvasTool.fountain: return PenType.fountain;
      case CanvasTool.pencil: return PenType.pencil;
      case CanvasTool.highlighter: return PenType.highlighter;
      case CanvasTool.marker: return PenType.marker;
      case CanvasTool.brush: return PenType.brush;
      default: return PenType.ballpoint;
    }
  }

  String get label {
    switch (this) {
      case CanvasTool.ballpoint: return 'Pen';
      case CanvasTool.fountain: return 'Fountain';
      case CanvasTool.pencil: return 'Pencil';
      case CanvasTool.highlighter: return 'Highlighter';
      case CanvasTool.marker: return 'Marker';
      case CanvasTool.brush: return 'Brush';
      case CanvasTool.eraser: return 'Eraser';
      case CanvasTool.pixelEraser: return 'Pixel eraser';
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
  final double pressureSensitivity;
  final double velocitySensitivity;
  final PressureCurve pressureCurve;
  final double customPressureExponent;

  const PenConfig({
    required this.type,
    required this.color,
    this.size = 3,
    this.opacity = 1,
    this.pressureSensitivity = .55,
    this.velocitySensitivity = .65,
    this.pressureCurve = PressureCurve.linear,
    this.customPressureExponent = 1,
  });

  PenConfig copyWith({
    PenType? type,
    Color? color,
    double? size,
    double? opacity,
    double? pressureSensitivity,
    double? velocitySensitivity,
    PressureCurve? pressureCurve,
    double? customPressureExponent,
  }) => PenConfig(
    type: type ?? this.type,
    color: color ?? this.color,
    size: size ?? this.size,
    opacity: opacity ?? this.opacity,
    pressureSensitivity: pressureSensitivity ?? this.pressureSensitivity,
    velocitySensitivity: velocitySensitivity ?? this.velocitySensitivity,
    pressureCurve: pressureCurve ?? this.pressureCurve,
    customPressureExponent: customPressureExponent ?? this.customPressureExponent,
  );
}

double curvePressure(double pressure, PenConfig pen) {
  final p = pressure.clamp(0, 1).toDouble();
  final exponent = switch (pen.pressureCurve) {
    PressureCurve.soft => .72,
    PressureCurve.linear => 1.0,
    PressureCurve.firm => 1.35,
    PressureCurve.custom => pen.customPressureExponent.clamp(.35, 2.5).toDouble(),
  };
  return math.pow(p, exponent).toDouble();
}
