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
        await db.execute(createAppNotificationsTable);
        await db.execute(createFolderCoversTable);
      },
      onUpgrade: (db, oldVersion, _) async {
        if (oldVersion < 5) {
          await _addColumnIfMissing(
            db,
            table: 'attachments',
            column: 'metadata_json',
            declaration: 'TEXT',
          );
        }
        if (oldVersion < 6) {
          await _addColumnIfMissing(
            db,
            table: 'folders',
            column: 'color_value',
            declaration: 'INTEGER NOT NULL DEFAULT 4284187897',
          );
          await _addColumnIfMissing(
            db,
            table: 'folders',
            column: 'icon_key',
            declaration: "TEXT NOT NULL DEFAULT 'folder'",
          );
          await _addColumnIfMissing(
            db,
            table: 'folders',
            column: 'sort_order',
            declaration: 'INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute(createAppNotificationsTable);
        }
        if (oldVersion < 7) {
          await db.execute(createFolderCoversTable);
        }
      },
      onOpen: (db) async {
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_notes_folder ON notes(folder_id, updated_at)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_folders_parent '
          'ON folders(parent_id, sort_order, name)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_attachments_note '
          'ON attachments(note_id, created_at)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_app_notifications_owner_created '
          'ON app_notifications(owner_id, created_at DESC)',
        );
      },
    );
    return _db!;
  }

  static Future<void> _addColumnIfMissing(
    DatabaseExecutor db, {
    required String table,
    required String column,
    required String declaration,
  }) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    if (columns.any((row) => row['name'] == column)) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $column $declaration');
  }
}
