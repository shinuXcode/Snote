import 'dart:typed_data';

import 'package:flutter/services.dart';

class SnoteScreenCapture {
  static const MethodChannel _channel = MethodChannel('com.snote/screen_capture');
  static Future<Uint8List?> captureDisplay() => _channel.invokeMethod<Uint8List>('captureDisplay');
}
