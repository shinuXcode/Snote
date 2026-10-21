import 'package:flutter_test/flutter_test.dart';
import 'package:snote/data/local/schema.dart';

void main() {
  test('local schema excludes remote synchronization structures', () {
    expect(databaseVersion, 9);
    expect(createNotesTable, isNot(contains('sync_state')));
    expect(createAttachmentsTable, isNot(contains('remote_path')));
  });
}
