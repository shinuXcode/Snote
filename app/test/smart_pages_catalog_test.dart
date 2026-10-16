import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Smart Pages catalog contains 200 unique, valid templates', () async {
    final raw = await rootBundle.loadString('assets/data/smart_pages.json');
    final decoded = jsonDecode(raw);
    expect(decoded, isA<List<dynamic>>());
    final rows = decoded as List<dynamic>;
    expect(rows, hasLength(200));

    final ids = <int>{};
    final categories = <String>{};
    for (final value in rows) {
      expect(value, isA<Map<String, dynamic>>());
      final row = value as Map<String, dynamic>;
      expect(row['id'], isA<int>());
      expect(row['title'], isA<String>());
      expect((row['title'] as String).trim(), isNotEmpty);
      expect(row['category'], isA<String>());
      expect(row['isFavorite'], isFalse);
      expect(row['icon'], isA<String>());
      expect(row['thumbnailKey'], isA<String>());
      expect(ids.add(row['id'] as int), isTrue, reason: 'Duplicate template ID');
      categories.add(row['category'] as String);
    }
    expect(ids, Set<int>.from(List<int>.generate(200, (i) => i + 1)));
    expect(categories, hasLength(8));
  });
}
