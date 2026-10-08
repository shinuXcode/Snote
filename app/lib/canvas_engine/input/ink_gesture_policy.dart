import 'package:flutter/gestures.dart';

/// TouchNotes-style interaction policy without depending on proprietary code:
/// stylus is ink, touch/trackpad is navigation, and multi-touch owns viewport
/// transforms. This keeps the two input domains from competing.
class InkGesturePolicy {
  final bool allowSingleFingerPan;
  final bool stylusWinsOverTouch;

  const InkGesturePolicy({
    this.allowSingleFingerPan = false,
    this.stylusWinsOverTouch = true,
  });

  bool isViewportDevice(PointerDeviceKind kind) =>
      kind == PointerDeviceKind.touch || kind == PointerDeviceKind.trackpad;

  bool isStylus(PointerDeviceKind kind) =>
      kind == PointerDeviceKind.stylus ||
      kind == PointerDeviceKind.invertedStylus;

  bool allowsSingleFingerPan() => allowSingleFingerPan;
}
