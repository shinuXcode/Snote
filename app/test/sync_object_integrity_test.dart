import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snote/features/sync/sync_object_integrity.dart';

void main() {
  const payload = 'encrypted-change-pack';
  final bytes = utf8.encode(payload);
  final digest = sha256.convert(bytes).toString();

  test('collects chunked bytes only after exact length and SHA-256 verification', () async {
    final verified = await SyncObjectIntegrity.collectAndVerify(
      Stream<List<int>>.fromIterable([
        bytes.sublist(0, 7),
        bytes.sublist(7, 15),
        bytes.sublist(15),
      ]),
      expectedByteLength: bytes.length,
      expectedSha256: digest,
    );
    expect(verified, bytes);
  });

  test('rejects a truncated stream', () async {
    await expectLater(
      SyncObjectIntegrity.collectAndVerify(
        Stream<List<int>>.value(bytes.sublist(0, bytes.length - 1)),
        expectedByteLength: bytes.length,
        expectedSha256: digest,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects tampered content even when byte length matches', () async {
    final tampered = [...bytes]..[0] = bytes[0] ^ 0x01;
    await expectLater(
      SyncObjectIntegrity.collectAndVerify(
        Stream<List<int>>.value(tampered),
        expectedByteLength: bytes.length,
        expectedSha256: digest,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects objects larger than the configured memory bound', () async {
    await expectLater(
      SyncObjectIntegrity.collectAndVerify(
        Stream<List<int>>.value(bytes),
        expectedByteLength: bytes.length,
        expectedSha256: digest,
        maximumBytes: bytes.length - 1,
      ),
      throwsArgumentError,
    );
  });
}
