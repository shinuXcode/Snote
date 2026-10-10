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
  // Mathematical diagrams.
  coordinateAxes,
  parabola,
  sineWave,
  angle,
  vectorArrow,
  projectilePath,
  // Physics / optics / circuits.
  rayDiagram,
  convexLens,
  concaveLens,
  planeMirror,
  forceDiagram,
  pulley,
  circuitResistor,
  circuitBattery,
  capacitor,
  circuitSwitch,
  circuitLamp,
  // Chemistry diagrams.
  atom,
  molecule,
  benzeneRing,
  beaker,
  testTube,
  conicalFlask,
  orbital,
  // Biology diagrams.
  animalCell,
  plantCell,
  dnaHelix,
  neuron,
  leaf,
  microscope,
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
    CanvasTool.coordinateAxes,
    CanvasTool.parabola,
    CanvasTool.sineWave,
    CanvasTool.angle,
    CanvasTool.vectorArrow,
    CanvasTool.projectilePath,
    CanvasTool.rayDiagram,
    CanvasTool.convexLens,
    CanvasTool.concaveLens,
    CanvasTool.planeMirror,
    CanvasTool.forceDiagram,
    CanvasTool.pulley,
    CanvasTool.circuitResistor,
    CanvasTool.circuitBattery,
    CanvasTool.capacitor,
    CanvasTool.circuitSwitch,
    CanvasTool.circuitLamp,
    CanvasTool.atom,
    CanvasTool.molecule,
    CanvasTool.benzeneRing,
    CanvasTool.beaker,
    CanvasTool.testTube,
    CanvasTool.conicalFlask,
    CanvasTool.orbital,
    CanvasTool.animalCell,
    CanvasTool.plantCell,
    CanvasTool.dnaHelix,
    CanvasTool.neuron,
    CanvasTool.leaf,
    CanvasTool.microscope,
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
      case CanvasTool.coordinateAxes: return 'Coordinate axes';
      case CanvasTool.parabola: return 'Parabola graph';
      case CanvasTool.sineWave: return 'Sine wave';
      case CanvasTool.angle: return 'Angle';
      case CanvasTool.vectorArrow: return 'Vector arrow';
      case CanvasTool.projectilePath: return 'Projectile path';
      case CanvasTool.rayDiagram: return 'Ray diagram';
      case CanvasTool.convexLens: return 'Convex lens';
      case CanvasTool.concaveLens: return 'Concave lens';
      case CanvasTool.planeMirror: return 'Plane mirror';
      case CanvasTool.forceDiagram: return 'Force diagram';
      case CanvasTool.pulley: return 'Pulley';
      case CanvasTool.circuitResistor: return 'Resistor';
      case CanvasTool.circuitBattery: return 'Battery';
      case CanvasTool.capacitor: return 'Capacitor';
      case CanvasTool.circuitSwitch: return 'Circuit switch';
      case CanvasTool.circuitLamp: return 'Circuit lamp';
      case CanvasTool.atom: return 'Atom';
      case CanvasTool.molecule: return 'Molecule';
      case CanvasTool.benzeneRing: return 'Benzene ring';
      case CanvasTool.beaker: return 'Beaker';
      case CanvasTool.testTube: return 'Test tube';
      case CanvasTool.conicalFlask: return 'Conical flask';
      case CanvasTool.orbital: return 'Atomic orbital';
      case CanvasTool.animalCell: return 'Animal cell';
      case CanvasTool.plantCell: return 'Plant cell';
      case CanvasTool.dnaHelix: return 'DNA helix';
      case CanvasTool.neuron: return 'Neuron';
      case CanvasTool.leaf: return 'Leaf';
      case CanvasTool.microscope: return 'Microscope';
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
