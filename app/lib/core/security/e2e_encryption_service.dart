import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// User-controlled end-to-end vault for note payloads and local attachments.
///
/// The passphrase never leaves the device. Cloud sync receives only an
/// authenticated AES-256-GCM envelope. A second device must be provisioned
/// with the same recovery passphrase.
class SnoteE2EEncryption {
  SnoteE2EEncryption._();
  static final instance = SnoteE2EEncryption._();

  static const _enabledKey = 'snote.e2e.enabled';
  static const _passphraseKey = 'snote.e2e.passphrase';
  static const _saltKey = 'snote.e2e.salt';
  static const _iterations = 150000;

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<bool> get enabled async =>
      (await _storage.read(key: _enabledKey)) == 'true';

  Future<bool> get configured async {
    final passphrase = await _storage.read(key: _passphraseKey);
    return passphrase != null && passphrase.isNotEmpty;
  }

  Future<void> enable(String passphrase) async {
    if (passphrase.trim().length < 8) {
      throw const FormatException('Encryption passphrase must contain at least 8 characters.');
    }
    await _ensureSalt();
    await _storage.write(key: _passphraseKey, value: passphrase);
    await _storage.write(key: _enabledKey, value: 'true');
  }

  Future<void> disable() async {
    await _storage.write(key: _enabledKey, value: 'false');
  }

  Future<void> forgetPassphrase() async {
    await _storage.delete(key: _passphraseKey);
    await _storage.delete(key: _saltKey);
    await _storage.write(key: _enabledKey, value: 'false');
  }

  bool isEncryptedText(String text) => _isEnvelope(text);

  bool isEncryptedBytes(List<int> bytes) => _isBinaryEnvelope(bytes);

  Future<String> encryptText(String text) async {
    if (!(await enabled)) return text;
    final passphrase = await _storage.read(key: _passphraseKey);
    if (passphrase == null || passphrase.isEmpty) {
      throw const StateError('Encryption is enabled but no vault passphrase is configured.');
    }
    final salt = await _ensureSalt();
    return _encrypt(utf8.encode(text), passphrase, salt);
  }

  Future<String> decryptText(String value) async {
    if (!_isEnvelope(value)) return value;
    final passphrase = await _storage.read(key: _passphraseKey);
    if (passphrase == null || passphrase.isEmpty) {
      throw const StateError('This note is encrypted. Enter the Snote recovery passphrase first.');
    }
    final envelope = jsonDecode(value);
    if (envelope is! Map) throw const FormatException('Invalid encrypted note envelope.');
    final salt = base64Url.decode(envelope['salt'].toString());
    return utf8.decode(await _decryptBytes(envelope, passphrase, salt));
  }

  Future<List<int>> encryptBytes(List<int> bytes) async {
    if (!(await enabled)) return bytes;
    final passphrase = await _storage.read(key: _passphraseKey);
    if (passphrase == null || passphrase.isEmpty) {
      throw const StateError('Encryption is enabled but no vault passphrase is configured.');
    }
    final salt = await _ensureSalt();
    final envelope = jsonDecode(_encrypt(bytes, passphrase, salt)) as Map;
    final payload = <int>[
      ...utf8.encode('SNOTE-E2E-BIN-1\\n'),
      ...utf8.encode(jsonEncode(envelope)),
    ];
    return payload;
  }

  Future<List<int>> decryptBytes(List<int> bytes) async {
    if (!_isBinaryEnvelope(bytes)) return bytes;
    final raw = utf8.decode(bytes, allowMalformed: false);
    final jsonStart = raw.indexOf('\\n');
    if (jsonStart <= 0) throw const FormatException('Invalid encrypted attachment.');
    final envelope = jsonDecode(raw.substring(jsonStart + 1));
    if (envelope is! Map) throw const FormatException('Invalid encrypted attachment envelope.');
    final passphrase = await _storage.read(key: _passphraseKey);
    if (passphrase == null || passphrase.isEmpty) {
      throw const StateError('This attachment is encrypted. Enter the Snote recovery passphrase first.');
    }
    final salt = base64Url.decode(envelope['salt'].toString());
    return _decryptBytes(envelope, passphrase, salt);
  }

  bool _isEnvelope(String raw) {
    if (raw.length < 20) return false;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map && decoded['format'] == 'snote-e2e-v1';
    } catch (_) {
      return false;
    }
  }

  bool _isBinaryEnvelope(List<int> bytes) =>
      bytes.length >= 15 &&
      utf8.decode(bytes.take(15).toList(), allowMalformed: true)
          .startsWith('SNOTE-E2E-BIN-1');

  Future<String> _encrypt(
    List<int> clearBytes,
    String passphrase,
    List<int> salt,
  ) async {
    final kdf = Pbkdf2.hmacSha256(iterations: _iterations, bits: 256);
    final key = await kdf.deriveKeyFromPassword(password: passphrase, nonce: salt);
    final cipher = AesGcm.with256bits(nonceLength: 12);
    final box = await cipher.encrypt(clearBytes, secretKey: key);
    return jsonEncode({
      'format': 'snote-e2e-v1',
      'cipher': 'AES-256-GCM',
      'kdf': 'PBKDF2-HMAC-SHA256',
      'iterations': _iterations,
      'salt': base64UrlEncode(salt),
      'nonce': base64UrlEncode(box.nonce),
      'cipherText': base64UrlEncode(box.cipherText),
      'mac': base64UrlEncode(box.mac.bytes),
    });
  }

  Future<List<int>> _decryptBytes(
    Map envelope,
    String passphrase,
    List<int> salt,
  ) async {
    final iterations = (envelope['iterations'] as num?)?.toInt() ?? _iterations;
    final kdf = Pbkdf2.hmacSha256(iterations: iterations, bits: 256);
    final key = await kdf.deriveKeyFromPassword(password: passphrase, nonce: salt);
    final cipher = AesGcm.with256bits(nonceLength: 12);
    final box = SecretBox(
      base64Url.decode(envelope['cipherText'].toString()),
      nonce: base64Url.decode(envelope['nonce'].toString()),
      mac: Mac(base64Url.decode(envelope['mac'].toString())),
    );
    return cipher.decrypt(box, secretKey: key);
  }

  Future<List<int>> _ensureSalt() async {
    final current = await _storage.read(key: _saltKey);
    if (current != null && current.isNotEmpty) return base64Url.decode(current);
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    await _storage.write(key: _saltKey, value: base64UrlEncode(salt));
    return salt;
  }
}
