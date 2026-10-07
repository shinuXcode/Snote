import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'schema.dart';

class SnoteDatabase {
  static Database? _db;

  static Future<Database> open() async {
    if (_db != null && _db!.isOpen) return _db!;

    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'snote.db');

    _db = await openDatabase(
      path,
      version: databaseVersion,
      onCreate: _create,
      onUpgrade: _upgrade,
      onOpen: (db) async {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_notes_folder ON notes(folder_id, updated_at)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_folders_parent ON folders(parent_id, name)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_attachments_note ON attachments(note_id, created_at)');
      },
    );
    return _db!;
  }

  static Future<void> _create(Database db, int version) async {
    await db.execute(createFoldersTable);
    await db.execute(createNotesTable);
    await db.execute(createPagesTable);
    await db.execute(createSyncQueueTable);
    await db.execute(createAttachmentsTable);
  }

  static Future<void> _upgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 3) {
      try {
        await db.execute('ALTER TABLE notes ADD COLUMN content_json TEXT');
      } catch (_) {}
    }
    if (oldVersion < 5) {
      try {
        await db.execute('ALTER TABLE attachments ADD COLUMN metadata_json TEXT');
      } catch (_) {}
    }
  }
}
