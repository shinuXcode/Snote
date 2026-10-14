import 'dart:typed_data';

import 'package:flutter/services.dart';

/// One-shot screenshot bytes from an explicitly approved Android MediaProjection session.
class SnoteScreenCapture {
  SnoteScreenCapture._();

  static const MethodChannel _channel = MethodChannel('com.snote/screen_capture');

  /// Returns in-memory PNG bytes, or null if the user declines capture.
  static Future<Uint8List?> captureScreen() =>
      _channel.invokeMethod<Uint8List?>('captureScreen');
}
