import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class NoteLockService {
  const NoteLockService();

  FlutterSecureStorage get _storage => const FlutterSecureStorage();
  String _key(String noteId) => 'snote.note-lock.' + noteId;

  Future<Map<String, dynamic>?> _read(String noteId) async {
    final raw = await _storage.read(key: _key(noteId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? decoded.cast<String, dynamic>() : null;
    } catch (_) { return null; }
  }

  Future<bool> hasPassword(String noteId) async => await _read(noteId) != null;
  Future<bool> isLocked(String noteId) async => (await _read(noteId))?['locked'] == true;

  Future<void> setPassword(String noteId, String password) async {
    final clean = password.trim();
    if (clean.length < 4) throw const FormatException('Password must contain at least 4 characters.');
    final salt = _salt();
    await _storage.write(key: _key(noteId), value: jsonEncode({
      'version': 1, 'salt': salt, 'hash': _hash(clean, salt), 'locked': true,
    }));
  }

  Future<bool> unlock(String noteId, String password) async {
    final config = await _read(noteId);
    if (config == null) return false;
    final salt = config['salt']?.toString();
    final expected = config['hash']?.toString();
    if (salt == null || expected == null) return false;
    final ok = _hash(password, salt) == expected;
    if (ok) await _storage.write(key: _key(noteId), value: jsonEncode({...config, 'locked': false}));
    return ok;
  }

  Future<void> lock(String noteId) async {
    final config = await _read(noteId);
    if (config == null) throw StateError('Set a password before locking this note.');
    await _storage.write(key: _key(noteId), value: jsonEncode({...config, 'locked': true}));
  }

  Future<void> removePassword(String noteId) => _storage.delete(key: _key(noteId));

  String _salt() {
    final random = Random.secure();
    return base64UrlEncode(Uint8List.fromList(List.generate(16, (_) => random.nextInt(256))));
  }

  String _hash(String password, String salt) =>
      sha256.convert(utf8.encode(salt + ':' + password)).toString();
}
