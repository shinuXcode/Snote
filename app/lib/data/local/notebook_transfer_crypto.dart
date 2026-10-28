import 'dart:convert';
import 'dart:math' as math;

import 'package:cryptography/cryptography.dart';

/// Authenticated encryption for complete Snote notebook transfers.
class NotebookTransferCrypto {
  NotebookTransferCrypto._();

  static const int _iterations = 180000;
  static final AesGcm _cipher = AesGcm.with256bits();
  static final Pbkdf2 _kdf = Pbkdf2.hmacSha256(
    iterations: _iterations,
    bits: 256,
  );

  static Future<Map<String, dynamic>> encrypt(
    Map<String, dynamic> manifest,
    String password,
  ) async {
    if (password.length < 8) {
      throw ArgumentError('Use a password with at least 8 characters.');
    }
    final random = math.Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final key = await _kdf.deriveKeyFromPassword(password: password, nonce: salt);
    final box = await _cipher.encrypt(
      utf8.encode(jsonEncode(manifest)),
      secretKey: key,
    );
    return <String, dynamic>{
      'format': 'snote-encrypted-notebook-v1',
      'kdf': 'pbkdf2-hmac-sha256',
      'iterations': _iterations,
      'cipher': 'aes-256-gcm',
      'salt': base64Encode(salt),
      'nonce': base64Encode(box.nonce),
      'mac': base64Encode(box.mac.bytes),
      'ciphertext': base64Encode(box.cipherText),
    };
  }

  static Future<Map<String, dynamic>> decrypt(
    Map<String, dynamic> envelope,
    String password,
  ) async {
    if (envelope['format'] != 'snote-encrypted-notebook-v1' ||
        envelope['kdf'] != 'pbkdf2-hmac-sha256' ||
        envelope['cipher'] != 'aes-256-gcm' ||
        envelope['iterations'] != _iterations) {
      throw const FormatException('Unsupported encrypted Snote transfer.');
    }
    try {
      final salt = base64Decode(envelope['salt']?.toString() ?? '');
      final nonce = base64Decode(envelope['nonce']?.toString() ?? '');
      final mac = Mac(base64Decode(envelope['mac']?.toString() ?? ''));
      final ciphertext = base64Decode(envelope['ciphertext']?.toString() ?? '');
      if (salt.length != 16 || nonce.length != 12 || mac.bytes.length != 16) {
        throw const FormatException('Invalid encrypted transfer data.');
      }
      final key = await _kdf.deriveKeyFromPassword(password: password, nonce: salt);
      final clear = await _cipher.decrypt(
        SecretBox(ciphertext, nonce: nonce, mac: mac),
        secretKey: key,
      );
      final decoded = jsonDecode(utf8.decode(clear));
      if (decoded is! Map) throw const FormatException('Invalid notebook contents.');
      return decoded.cast<String, dynamic>();
    } catch (_) {
      throw const FormatException(
        'Could not decrypt the transfer. Check the password and file.',
      );
    }
  }
}
