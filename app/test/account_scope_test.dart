import 'package:flutter_test/flutter_test.dart';
import 'package:snote/core/config/account_scope.dart';

void main() {
  test('production notes always use the local owner scope', () {
    expect(SnoteAccountScope.ownerId, SnoteAccountScope.localOwner);
    expect(SnoteAccountScope.isCloudAccount, isFalse);
  });
}
