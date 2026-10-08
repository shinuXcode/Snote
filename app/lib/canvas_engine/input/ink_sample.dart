import 'dart:ui';

import 'package:flutter/gestures.dart';

import '../models/stroke.dart';

/// Immutable normalized input sample captured directly from Flutter's pointer
/// event. No rendering or persistence work belongs in this layer.
class InkSample {
  final Offset position;
  final double pressure;
  final double timestampMs;
  final double tilt;
  final double orientation;
  final int pointer;
  final int device;
  final int buttons;
  final PointerDeviceKind kind;
  final bool synthesized;

  const InkSample({
    required this.position,
    required this.pressure,
    required this.timestampMs,
    required this.tilt,
    required this.orientation,
    required this.pointer,
    required this.device,
    required this.buttons,
    required this.kind,
    required this.synthesized,
  });

  factory InkSample.fromEvent(PointerEvent event) {
    final min = event.pressureMin;
    final max = event.pressureMax;
    final raw = event.pressure.isFinite ? event.pressure : 1.0;
    final pressure = max > min
        ? ((raw - min) / (max - min)).clamp(0.0, 1.0).toDouble()
        : raw.clamp(0.0, 1.0).toDouble();

    return InkSample(
      position: event.localPosition,
      pressure: pressure,
      timestampMs: event.timeStamp.inMicroseconds / 1000.0,
      tilt: event.tilt.isFinite ? event.tilt : 0.0,
      orientation:
          event.orientation.isFinite ? event.orientation : 0.0,
      pointer: event.pointer,
      device: event.device,
      buttons: event.buttons,
      kind: event.kind,
      synthesized: event.synthesized,
    );
  }

  StrokePoint toStrokePoint() => StrokePoint(
        position: position,
        pressure: pressure,
        timestamp: timestampMs,
        tilt: tilt,
        orientation: orientation,
      );
}
