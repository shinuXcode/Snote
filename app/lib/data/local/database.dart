import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'database_factory.dart';
import 'schema.dart';

class SnoteDatabase {
  static Database? _db;

  static Future<Database> open() async {
    if (_db?.isOpen == true) return _db!;

    await initializeDatabaseFactory();
    final String databasePath;
    if (kIsWeb) {
      // The web factory stores this logical path in IndexedDB; path_provider's
      // native documents directory is not available in browser runtimes.
      databasePath = 'snote.db';
    } else {
      final dir = await getApplicationDocumentsDirectory();
      databasePath = p.join(dir.path, 'snote.db');
    }
    _db = await openDatabase(
      databasePath,
      version: databaseVersion,
      onConfigure: (db) async {
        try { await db.execute('PRAGMA foreign_keys = ON'); } catch (_) {}
        try { await db.execute('PRAGMA busy_timeout = 5000'); } catch (_) {}
        try {
          await db.rawQuery('PRAGMA journal_mode = WAL');
          await db.execute('PRAGMA synchronous = NORMAL');
        } catch (_) {}
      },
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
          'CREATE INDEX IF NOT EXISTS idx_notes_owner_deleted_updated '
          'ON notes(owner_id, deleted_at, updated_at DESC)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_folders_owner_deleted_parent_order '
          'ON folders(owner_id, deleted_at, parent_id, sort_order, name)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_notes_owner_folder_updated '
          'ON notes(owner_id, folder_id, updated_at DESC)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_notes_owner_title '
          'ON notes(owner_id, title COLLATE NOCASE)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_notes_title ON notes(title COLLATE NOCASE)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_pages_note ON pages(note_id, page_index)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_folders_parent '
          'ON folders(parent_id, sort_order, name)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_folders_owner_parent_order '
          'ON folders(owner_id, parent_id, sort_order, name)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_attachments_note '
          'ON attachments(note_id, created_at)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_app_notifications_owner_created '
          'ON app_notifications(owner_id, created_at DESC)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_folder_covers_created '
          'ON folder_covers(created_at DESC)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_sync_queue_owner_entity '
          'ON sync_queue(owner_id, entity_type, entity_id, created_at)',
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
