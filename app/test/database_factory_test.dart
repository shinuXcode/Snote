import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:snote/data/local/database_factory.dart';

void main() {
  test('initializes a working SQLite factory on Linux and Windows', () async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.linux &&
            defaultTargetPlatform != TargetPlatform.windows)) {
      return;
    }

    await initializeDatabaseFactory();
    final database = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('CREATE TABLE smoke_test (value INTEGER NOT NULL)');
      },
    );
    try {
      await database.insert('smoke_test', {'value': 42});
      final rows = await database.query('smoke_test');
      expect(rows.single['value'], 42);
    } finally {
      await database.close();
    }
  });
}
