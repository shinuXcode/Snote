import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

/// Runs on-device OCR without uploading the selected handwriting.
Future<String> recognizeSelectionText(Uint8List pngBytes) async {
  if (!Platform.isAndroid && !Platform.isIOS) {
    throw UnsupportedError(
      'Handwriting OCR is currently supported on Android and iOS only.',
    );
  }
  if (pngBytes.isEmpty) {
    throw ArgumentError.value(pngBytes, 'pngBytes', 'Image must not be empty.');
  }

  final directory = await getTemporaryDirectory();
  final file = File(
    '${directory.path}/snote-selection-${DateTime.now().microsecondsSinceEpoch}.png',
  );
  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    await file.writeAsBytes(pngBytes, flush: true);
    final image = InputImage.fromFilePath(file.path);
    final recognized = await recognizer.processImage(image);
    return recognized.text.trim();
  } finally {
    await recognizer.close();
    try {
      if (await file.exists()) await file.delete();
    } catch (error) {
      debugPrint('[Snote][OCR] temporary image cleanup failed: $error');
    }
  }
}
