import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

enum SyncChangePackKind { snapshot, delta }

/// Versioned, immutable logical payload. The payload is encrypted before it is
/// handed to any SyncTransport implementation.
class SyncChangePack {
  const SyncChangePack({
    required this.packId,
    required this.deviceId,
    required this.kind,
    required this.fromSequence,
    required this.toSequence,
    required this.vectorClock,
    required this.operations,
    this.baseCheckpoint,
    this.snapshot,
  });

  static const int schemaVersion = 1;
  static const String format = 'snotee-encrypted-sync-pack-v1';
  static final AesGcm _cipher = AesGcm.with256bits();

  final String packId;
  final String deviceId;
  final SyncChangePackKind kind;
  final int fromSequence;
  final int toSequence;
  final String? baseCheckpoint;
  final Map<String, int> vectorClock;
  final List<Map<String, dynamic>> operations;
  final Map<String, dynamic>? snapshot;

  Map<String, dynamic> toPayload() {
    _validate();
    return {
      'schemaVersion': schemaVersion,
      'packId': packId,
      'deviceId': deviceId,
      'kind': kind.name,
      'fromSequence': fromSequence,
      'toSequence': toSequence,
      'baseCheckpoint': baseCheckpoint,
      'vectorClock': vectorClock,
      'operations': operations,
      'snapshot': snapshot,
    };
  }

  void _validate() {
    if (packId.isEmpty || packId.length > 180 ||
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$').hasMatch(packId)) {
      throw const FormatException('Invalid sync change-pack ID.');
    }
    if (deviceId.isEmpty || deviceId.length > 180) {
      throw const FormatException('Invalid sync device ID.');
    }
    if (fromSequence < 0 || toSequence < fromSequence) {
      throw const FormatException('Invalid sync sequence range.');
    }
    if (kind == SyncChangePackKind.snapshot && snapshot == null) {
      throw const FormatException('A snapshot pack must contain a snapshot payload.');
    }
    final operationIds = <String>{};
    final sequences = <int>{};
    for (final operation in operations) {
      final id = operation['operationId']?.toString() ?? '';
      final sequence = operation['sequence'];
      final entityType = operation['entityType']?.toString() ?? '';
      final entityId = operation['entityId']?.toString() ?? '';
      if (id.isEmpty || entityType.isEmpty || entityId.isEmpty ||
          sequence is! int || sequence < 1 ||
          !operationIds.add(id) || !sequences.add(sequence)) {
        throw const FormatException('Change pack contains an invalid or duplicate operation.');
      }
      if (sequence < fromSequence || sequence > toSequence) {
        throw const FormatException('Operation sequence falls outside the declared pack range.');
      }
    }
    for (final entry in vectorClock.entries) {
      if (entry.key.isEmpty || entry.value < 0) {
        throw const FormatException('Invalid vector clock entry.');
      }
    }
  }

  /// AES-256-GCM encrypts the entire manifest and operation/snapshot payload.
  /// Only this returned ciphertext envelope may be passed to remote storage.
  Future<Uint8List> encrypt(List<int> rawKey) async {
    if (rawKey.length != 32) {
      throw ArgumentError('Sync encryption key must contain exactly 32 bytes.');
    }
    final random = math.Random.secure();
    final nonce = List<int>.generate(12, (_) => random.nextInt(256));
    final cleartext = utf8.encode(jsonEncode(toPayload()));
    final box = await _cipher.encrypt(
      cleartext,
      secretKey: SecretKey(rawKey),
      nonce: nonce,
      aad: utf8.encode(format),
    );
    return Uint8List.fromList(utf8.encode(jsonEncode({
      'format': format,
      'cipher': 'aes-256-gcm',
      'nonce': base64Encode(box.nonce),
      'mac': base64Encode(box.mac.bytes),
      'ciphertext': base64Encode(box.cipherText),
    })));
  }

  static Future<SyncChangePack> decrypt(
    List<int> encryptedEnvelope,
    List<int> rawKey,
  ) async {
    if (rawKey.length != 32) {
      throw ArgumentError('Sync encryption key must contain exactly 32 bytes.');
    }
    try {
      final envelope = jsonDecode(utf8.decode(encryptedEnvelope));
      if (envelope is! Map ||
          envelope['format'] != format ||
          envelope['cipher'] != 'aes-256-gcm') {
        throw const FormatException('Unsupported encrypted sync change pack.');
      }
      final nonce = base64Decode(envelope['nonce']?.toString() ?? '');
      final mac = Mac(base64Decode(envelope['mac']?.toString() ?? ''));
      final ciphertext = base64Decode(envelope['ciphertext']?.toString() ?? '');
      if (nonce.length != 12 || mac.bytes.length != 16 || ciphertext.isEmpty) {
        throw const FormatException('Malformed encrypted sync change pack.');
      }
      final cleartext = await _cipher.decrypt(
        SecretBox(ciphertext, nonce: nonce, mac: mac),
        secretKey: SecretKey(rawKey),
        aad: utf8.encode(format),
      );
      final payload = jsonDecode(utf8.decode(cleartext));
      if (payload is! Map || payload['schemaVersion'] != schemaVersion) {
        throw const FormatException('Unsupported sync change-pack schema.');
      }
      final clock = payload['vectorClock'];
      final operations = payload['operations'];
      if (clock is! Map || operations is! List) {
        throw const FormatException('Invalid sync change-pack payload.');
      }
      final pack = SyncChangePack(
        packId: payload['packId']?.toString() ?? '',
        deviceId: payload['deviceId']?.toString() ?? '',
        kind: SyncChangePackKind.values.firstWhere(
          (value) => value.name == payload['kind'],
          orElse: () => throw const FormatException('Unknown change-pack kind.'),
        ),
        fromSequence: payload['fromSequence'] as int? ?? -1,
        toSequence: payload['toSequence'] as int? ?? -1,
        baseCheckpoint: payload['baseCheckpoint']?.toString(),
        vectorClock: clock.cast<String, dynamic>().map<String, int>(
          (key, value) => MapEntry(key, value as int),
        ),
        operations: operations.map((value) {
          if (value is! Map) throw const FormatException('Invalid operation record.');
          return value.cast<String, dynamic>();
        }).toList(growable: false),
        snapshot: payload['snapshot'] is Map
            ? (payload['snapshot'] as Map).cast<String, dynamic>()
            : null,
      );
      pack._validate();
      return pack;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Sync change-pack authentication or decoding failed.');
    }
  }
}
