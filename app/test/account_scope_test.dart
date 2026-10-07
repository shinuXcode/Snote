import 'package:flutter_test/flutter_test.dart';

import 'package:snote/core/config/account_scope.dart';

void main() {
  test('local mode is isolated from authenticated account mode', () {
    SnoteAccountScope.setAuthenticatedUser(null);
    expect(SnoteAccountScope.ownerId, SnoteAccountScope.localOwner);
    expect(SnoteAccountScope.isCloudAccount, isFalse);

    SnoteAccountScope.setAuthenticatedUser(' user-123 ');
    expect(SnoteAccountScope.ownerId, 'user-123');
    expect(SnoteAccountScope.isCloudAccount, isTrue);

    SnoteAccountScope.setAuthenticatedUser('   ');
    expect(SnoteAccountScope.ownerId, SnoteAccountScope.localOwner);
    expect(SnoteAccountScope.isCloudAccount, isFalse);
  });
}
