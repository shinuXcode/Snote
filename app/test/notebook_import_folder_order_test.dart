import 'package:flutter_test/flutter_test.dart';
import 'package:snote/data/local/notebook_import_folder_order.dart';

void main() {
  test('orders parent folders before children regardless of export order', () {
    final folders = <Map<String, Object?>>[
      {'id': 'child', 'parentId': 'parent', 'name': 'Child'},
      {'id': 'parent', 'parentId': null, 'name': 'Parent'},
      {'id': 'grandchild', 'parentId': 'child', 'name': 'Grandchild'},
    ];

    final ordered = orderImportedFolders(folders);

    expect(ordered.map((folder) => folder['id']).toList(), [
      'parent',
      'child',
      'grandchild',
    ]);
    expect(folders.first['id'], 'child');
  });

  test('leaves missing parents for fallback handling by the importer', () {
    final ordered = orderImportedFolders([
      {'id': 'child', 'parentId': 'missing', 'name': 'Child'},
      {'id': 'root', 'parentId': null, 'name': 'Root'},
    ]);

    expect(ordered.first['id'], 'child');
    expect(ordered.first['parentId'], 'missing');
  });

  test('breaks cyclic parent references instead of looping forever', () {
    final ordered = orderImportedFolders([
      {'id': 'a', 'parentId': 'b', 'name': 'A'},
      {'id': 'b', 'parentId': 'a', 'name': 'B'},
    ]);

    expect(ordered, hasLength(2));
    expect(ordered.first['parentId'], isNull);
    expect(ordered.last['parentId'], ordered.first['id']);
  });
}
