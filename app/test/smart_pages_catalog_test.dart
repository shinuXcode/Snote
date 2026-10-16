import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Smart Pages catalog contains 200 unique templates in eight categories', () async {
    final raw = await rootBundle.loadString('assets/data/smart_pages.json');
    final decoded = jsonDecode(raw) as List<dynamic>;
    final records = decoded.cast<Map<String, dynamic>>();
    expect(records, hasLength(200));

    final ids = records.map((record) => record['id']).toSet();
    expect(ids, hasLength(200));
    expect(ids, containsAll(List<int>.generate(200, (index) => index + 1)));

    final categories = records.map((record) => record['category']).toSet();
    expect(categories, hasLength(8));
    for (final record in records) {
      expect(record['title'], isA<String>());
      expect((record['title'] as String).trim(), isNotEmpty);
      expect(record['icon'], isA<String>());
      expect(record['thumbnailKey'], isA<String>());
      expect(record['isFavorite'], isFalse);
    }
  });
}
