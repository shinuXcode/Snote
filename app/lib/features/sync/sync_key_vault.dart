import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Local half of Snote's end-to-end encryption key lifecycle.
///
/// The returned recovery material is a bearer secret. It must only be shown
/// once, transferred out-of-band, and never logged or uploaded with sync data.
/// Remote device revocation must also be committed to the provider's signed
/// device manifest; deleting this local key alone cannot revoke another device.
class SyncKeyVault {
  SyncKeyVault({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _activeKeyName = 'snote.sync.active_key.v1';
  static const _keyVersionName = 'snote.sync.key_version.v1';
  static const _deviceIdName = 'snote.sync.device_id.v1';

  final FlutterSecureStorage _storage;
  final Random _secureRandom = Random.secure();

  Future<SyncVaultKey?> readActiveKey() async {
    final encoded = await _storage.read(key: _activeKeyName);
    if (encoded == null || encoded.isEmpty) return null;
    final bytes = base64Url.decode(base64Url.normalize(encoded));
    if (bytes.length != 32) {
      throw const FormatException('Stored sync key has an invalid length.');
    }
    final version = int.tryParse(
          await _storage.read(key: _keyVersionName) ?? '',
        ) ??
        1;
    return SyncVaultKey(
      keyBytes: bytes,
      version: version,
      deviceId: await _ensureDeviceId(),
    );
  }

  /// Creates a fresh key only when this device has not already been paired.
  /// The returned recovery string must be delivered to the user exactly once.
  Future<SyncKeyCreation> createIfMissing() async {
    final current = await readActiveKey();
    if (current != null) {
      return SyncKeyCreation(key: current, recoveryKey: null, created: false);
    }
    final bytes = _randomBytes(32);
    final recovery = base64UrlEncode(bytes).replaceAll('=', '');
    final deviceId = await _ensureDeviceId();
    await _writeKey(bytes, version: 1);
    return SyncKeyCreation(
      key: SyncVaultKey(keyBytes: bytes, version: 1, deviceId: deviceId),
      recoveryKey: recovery,
      created: true,
    );
  }

  /// Imports user-held recovery material. Import never overwrites an existing
  /// key; callers must explicitly rotate or revoke first.
  Future<SyncVaultKey> importRecoveryKey(String recoveryKey) async {
    if (await _storage.read(key: _activeKeyName) != null) {
      throw StateError('A sync key already exists on this device.');
    }
    final normalized = recoveryKey.trim();
    final bytes = base64Url.decode(
      base64Url.normalize(normalized),
    );
    if (bytes.length != 32) {
      throw const FormatException('Recovery key must decode to exactly 32 bytes.');
    }
    await _writeKey(bytes, version: 1);
    return SyncVaultKey(
      keyBytes: bytes,
      version: 1,
      deviceId: await _ensureDeviceId(),
    );
  }

  /// Rotates the local active key. The caller must publish a re-encrypted
  /// snapshot/key-rotation envelope before considering other devices updated.
  /// This method intentionally does not claim remote devices were rotated.
  Future<SyncKeyCreation> rotate() async {
    final current = await readActiveKey();
    if (current == null) {
      throw StateError('Cannot rotate a sync key before one has been created.');
    }
    final bytes = _randomBytes(32);
    final version = current.version + 1;
    await _writeKey(bytes, version: version);
    return SyncKeyCreation(
      key: SyncVaultKey(
        keyBytes: bytes,
        version: version,
        deviceId: current.deviceId,
      ),
      recoveryKey: base64UrlEncode(bytes).replaceAll('=', ''),
      created: true,
    );
  }

  /// Removes local access. Provider-side device revocation is a separate,
  /// mandatory operation and must be confirmed by the sync coordinator.
  Future<void> revokeLocalKey() async {
    await _storage.delete(key: _activeKeyName);
    await _storage.delete(key: _keyVersionName);
  }

  Future<String> _ensureDeviceId() async {
    final existing = await _storage.read(key: _deviceIdName);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = base64UrlEncode(_randomBytes(18)).replaceAll('=', '');
    await _storage.write(key: _deviceIdName, value: id);
    return id;
  }

  Future<void> _writeKey(List<int> bytes, {required int version}) async {
    if (bytes.length != 32) {
      throw ArgumentError.value(bytes.length, 'bytes.length', 'Expected 32 bytes.');
    }
    await _storage.write(
      key: _activeKeyName,
      value: base64UrlEncode(bytes).replaceAll('=', ''),
    );
    await _storage.write(key: _keyVersionName, value: '$version');
  }

  List<int> _randomBytes(int length) =>
      List<int>.generate(length, (_) => _secureRandom.nextInt(256));
}

class SyncVaultKey {
  const SyncVaultKey({
    required this.keyBytes,
    required this.version,
    required this.deviceId,
  });

  final List<int> keyBytes;
  final int version;
  final String deviceId;
}

class SyncKeyCreation {
  const SyncKeyCreation({
    required this.key,
    required this.recoveryKey,
    required this.created,
  });

  final SyncVaultKey key;
  final String? recoveryKey;
  final bool created;
}
