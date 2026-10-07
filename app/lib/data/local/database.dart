import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'schema.dart';

class SnoteDatabase {
  static Database? _db;

  static Future<Database> open() async {
    if (_db?.isOpen == true) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    _db = await openDatabase(
      p.join(dir.path, 'snote.db'),
      version: databaseVersion,
      onCreate: (db, _) async {
        await db.execute(createFoldersTable);
        await db.execute(createNotesTable);
        await db.execute(createPagesTable);
        await db.execute(createAttachmentsTable);
        await db.execute(createSyncQueueTable);
      },
      onUpgrade: (db, oldVersion, _) async {
        if (oldVersion < 5) {
          try { await db.execute('ALTER TABLE attachments ADD COLUMN metadata_json TEXT'); } catch (_) {}
        }
      },
      onOpen: (db) async {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_notes_folder ON notes(folder_id, updated_at)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_folders_parent ON folders(parent_id, name)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_attachments_note ON attachments(note_id, created_at)');
      },
    );
    return _db!;
  }
}
