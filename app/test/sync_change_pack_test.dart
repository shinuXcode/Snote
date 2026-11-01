import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:snote/features/sync/sync_change_pack.dart';

void main() {
  final key = List<int>.generate(32, (index) => index + 1);

  SyncChangePack samplePack() => SyncChangePack(
        packId: 'pack-deviceA-1',
        deviceId: 'deviceA',
        kind: SyncChangePackKind.delta,
        fromSequence: 1,
        toSequence: 2,
        baseCheckpoint: 'checkpoint-0',
        vectorClock: const {'deviceA': 2, 'deviceB': 4},
        operations: const [
          {
            'operationId': 'op-1',
            'sequence': 1,
            'entityType': 'note',
            'entityId': 'note-1',
            'operation': 'upsert',
          },
          {
            'operationId': 'op-2',
            'sequence': 2,
            'entityType': 'attachment',
            'entityId': 'attachment-1',
            'operation': 'create',
          },
        ],
      );

  test('encrypts the full change pack and round-trips after authentication', () async {
    final pack = samplePack();
    final encrypted = await pack.encrypt(key);
    final envelopeText = utf8.decode(encrypted);
    expect(envelopeText, isNot(contains('note-1')));
    expect(envelopeText, isNot(contains('checkpoint-0')));

    final decoded = await SyncChangePack.decrypt(encrypted, key);
    expect(decoded.packId, pack.packId);
    expect(decoded.deviceId, pack.deviceId);
    expect(decoded.fromSequence, 1);
    expect(decoded.toSequence, 2);
    expect(decoded.vectorClock, {'deviceA': 2, 'deviceB': 4});
    expect(decoded.operations, hasLength(2));
  });

  test('rejects ciphertext tampering', () async {
    final encrypted = await samplePack().encrypt(key);
    final envelope = jsonDecode(utf8.decode(encrypted)) as Map<String, dynamic>;
    final ciphertext = base64Decode(envelope['ciphertext'] as String);
    ciphertext[0] ^= 0x01;
    envelope['ciphertext'] = base64Encode(ciphertext);

    await expectLater(
      SyncChangePack.decrypt(utf8.encode(jsonEncode(envelope)), key),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects duplicate operation identifiers and sequence numbers', () {
    final invalid = SyncChangePack(
      packId: 'pack-invalid',
      deviceId: 'deviceA',
      kind: SyncChangePackKind.delta,
      fromSequence: 1,
      toSequence: 2,
      vectorClock: const {'deviceA': 2},
      operations: const [
        {'operationId': 'same', 'sequence': 1, 'entityType': 'note', 'entityId': 'n1'},
        {'operationId': 'same', 'sequence': 1, 'entityType': 'note', 'entityId': 'n2'},
      ],
    );
    expect(() => invalid.toPayload(), throwsFormatException);
  });

  test('requires a 256-bit key', () async {
    await expectLater(samplePack().encrypt([1, 2, 3]), throwsArgumentError);
  });
}
