import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores the local device's 256-bit sync key in Keychain/KeyStore-backed
/// secure storage. Cross-device key exchange and recovery are separate flows.
class SyncDeviceKeyStore {
  SyncDeviceKeyStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _storageKey = 'snotee.sync.device_key.v1';
  final FlutterSecureStorage _storage;

  Future<List<int>> loadOrCreate() async {
    final existing = await _storage.read(key: _storageKey);
    if (existing != null) {
      final decoded = base64Decode(existing);
      if (decoded.length != 32) {
        throw const FormatException('Stored sync device key is invalid.');
      }
      return decoded;
    }
    final random = math.Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    await _storage.write(key: _storageKey, value: base64Encode(bytes));
    return bytes;
  }

  Future<void> delete() => _storage.delete(key: _storageKey);
}
