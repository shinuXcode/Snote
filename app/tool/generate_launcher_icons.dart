import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// Creates Android adaptive-icon layers with a safe-zone inset.
///
/// The original Snotee mark nearly fills its square source image. Android
/// applies launcher-specific masks (circle, squircle, teardrop, etc.), so
/// using it edge-to-edge clips the pen and the outer stroke. This generator
/// scales the mark into the central 61% safe area and writes a dedicated foreground layer with transparent padding.
Future<void> main() async {
  const canvasSize = 512;
  const safeSize = 312;

  final source = File('assets/branding/snote-logo.png');
  if (!await source.exists()) {
    throw StateError('Missing source logo: ${source.path}');
  }

  final decoded = img.decodeImage(await source.readAsBytes());
  if (decoded == null) {
    throw const FormatException('Could not decode assets/branding/snote-logo.png');
  }

  final scale = math.min(
    safeSize / decoded.width,
    safeSize / decoded.height,
  );
  final width = math.max(1, (decoded.width * scale).round());
  final height = math.max(1, (decoded.height * scale).round());
  final resized = img.copyResize(
    decoded,
    width: width,
    height: height,
    interpolation: img.Interpolation.cubic,
  );

  final foreground = img.Image(
    width: canvasSize,
    height: canvasSize,
    numChannels: 4,
  );
  img.fill(foreground, color: img.ColorRgba8(0, 0, 0, 0));
  img.compositeImage(
    foreground,
    resized,
    dstX: (canvasSize - width) ~/ 2,
    dstY: (canvasSize - height) ~/ 2,
  );

  await File('assets/branding/snote-launcher-foreground.png')
      .writeAsBytes(img.encodePng(foreground));

  stdout.writeln(
    'Generated 512x512 adaptive icon layers with a centered $safeSize px safe-zone mark.',
  );
}
