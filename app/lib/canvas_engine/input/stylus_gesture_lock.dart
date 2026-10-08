import 'package:flutter/gestures.dart';

/// Coordinates the ownership of the canvas gesture stream.
///
/// A stylus owns the canvas while it is down. Touch remains available for
/// viewport gestures but can never steal an active stylus stroke.
class StylusGestureLock {
  int? _stylusPointer;

  bool get isLocked => _stylusPointer != null;
  int? get pointer => _stylusPointer;

  bool begin(PointerEvent event) {
    if (event.kind != PointerDeviceKind.stylus &&
        event.kind != PointerDeviceKind.invertedStylus) {
      return false;
    }
    if (_stylusPointer != null) return false;
    _stylusPointer = event.pointer;
    return true;
  }

  bool owns(PointerEvent event) => _stylusPointer == event.pointer;

  void end(PointerEvent event) {
    if (owns(event)) _stylusPointer = null;
  }

  void reset() => _stylusPointer = null;
}
