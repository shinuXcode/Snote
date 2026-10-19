import 'dart:typed_data';

import 'selection_text_recognizer_stub.dart'
    if (dart.library.io) 'selection_text_recognizer_io.dart' as platform;

/// Recognizes a rasterized selection using the current platform's local OCR.
Future<String> recognizeSelectionText(Uint8List pngBytes) =>
    platform.recognizeSelectionText(pngBytes);
