import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class NoteLockService {
  const NoteLockService();

  FlutterSecureStorage get _storage => const FlutterSecureStorage();

  String _key(String noteId) => 'snote.note-lock.$noteId';

  Future<Map<String, dynamic>?> _read(String noteId) async {
    final raw = await _storage.read(key: _key(noteId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? decoded.cast<String, dynamic>() : null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> hasPassword(String noteId) async => !kIsWeb && await _read(noteId) != null;

  Future<bool> isLocked(String noteId) async {
    if (kIsWeb) return false;
    final value = await _read(noteId);
    return value?['locked'] == true;
  }

  Future<void> setPassword(String noteId, String password) async {
    if (kIsWeb) return;
    final clean = password.trim();
    if (clean.length < 4) {
      throw const FormatException('Password must contain at least 4 characters.');
    }

    final salt = _randomSalt();
    final hash = _hash(clean, salt);
    await _storage.write(
      key: _key(noteId),
      value: jsonEncode(<String, Object>{
        'salt': salt,
        'hash': hash,
        'locked': true,
        'version': 1,
      }),
    );
  }

  Future<bool> unlock(String noteId, String password) async {
    if (kIsWeb) return true;
    final config = await _read(noteId);
    if (config == null) return false;
    final salt = config['salt']?.toString();
    final expected = config['hash']?.toString();
    if (salt == null || expected == null) return false;

    final ok = _hash(password, salt) == expected;
    if (ok) await _writeLocked(noteId, false, config);
    return ok;
  }

  Future<void> lock(String noteId) async {
    if (kIsWeb) return;
    final config = await _read(noteId);
    if (config == null) {
      throw const StateError('Set a note password before locking this note.');
    }
    await _writeLocked(noteId, true, config);
  }

  Future<void> removePassword(String noteId) async {
    if (kIsWeb) return;
    await _storage.delete(key: _key(noteId));
  }

  String _randomSalt() {
    final random = Random.secure();
    final bytes = Uint8List.fromList(List<int>.generate(16, (_) => random.nextInt(256)));
    return base64UrlEncode(bytes);
  }

  String _hash(String password, String salt) => sha256.convert(utf8.encode('$salt:$password')).toString();

  Future<void> _writeLocked(String noteId, bool locked, Map<String, dynamic> source) async {
    final copy = <String, dynamic>{...source, 'locked': locked};
    await _storage.write(key: _key(noteId), value: jsonEncode(copy));
  }
}
