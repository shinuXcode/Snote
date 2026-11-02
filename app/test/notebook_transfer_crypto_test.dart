import 'package:flutter_test/flutter_test.dart';

import '../lib/data/local/notebook_transfer_crypto.dart';

void main() {
  test('encrypted archive round-trips and authenticates its password', () async {
    final original = List<int>.generate(4096, (index) => (index * 37) % 256);
    final envelope = await NotebookTransferCrypto.encryptArchive(
      original,
      'test-backup-password',
    );

    expect(envelope['format'], 'snote-encrypted-archive-v1');
    final restored = await NotebookTransferCrypto.decryptArchive(
      envelope,
      'test-backup-password',
    );
    expect(restored, original);

    await expectLater(
      NotebookTransferCrypto.decryptArchive(envelope, 'incorrect-password'),
      throwsA(isA<FormatException>()),
    );
  });
}
