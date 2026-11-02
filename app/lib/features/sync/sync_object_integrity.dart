import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Bounded in-memory verification for one immutable encrypted sync chunk.
///
/// Call this before decryption or database application. Large attachments must
/// be split into independently verifiable chunks rather than bypassing the cap.
class SyncObjectIntegrity {
  SyncObjectIntegrity._();

  static const int defaultMaximumBytes = 64 * 1024 * 1024;

  static Future<Uint8List> collectAndVerify(
    Stream<List<int>> chunks, {
    required int expectedByteLength,
    required String expectedSha256,
    int maximumBytes = defaultMaximumBytes,
  }) async {
    if (expectedByteLength < 0 ||
        expectedByteLength > maximumBytes ||
        maximumBytes <= 0 ||
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(expectedSha256)) {
      throw ArgumentError('Invalid sync object integrity metadata.');
    }

    final builder = BytesBuilder(copy: false);
    var received = 0;
    await for (final chunk in chunks) {
      received += chunk.length;
      if (received > expectedByteLength || received > maximumBytes) {
        throw const FormatException('Sync object exceeds its declared or permitted size.');
      }
      builder.add(chunk);
    }

    if (received != expectedByteLength) {
      throw const FormatException('Sync object is truncated or has an incorrect byte length.');
    }

    final bytes = builder.takeBytes();
    final actualSha256 = sha256.convert(bytes).toString();
    if (actualSha256.toLowerCase() != expectedSha256.toLowerCase()) {
      throw const FormatException('Sync object SHA-256 verification failed.');
    }
    return bytes;
  }
}
