const databaseVersion = 5;

const createNotesTable = '''
CREATE TABLE notes (
  id TEXT PRIMARY KEY,
  owner_id TEXT NOT NULL DEFAULT 'local',
  title TEXT NOT NULL,
  folder_id TEXT,
  note_type TEXT NOT NULL,
  content_json TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER,
  version INTEGER NOT NULL DEFAULT 1,
  sync_state TEXT NOT NULL DEFAULT 'pending'
)''';

const createFoldersTable = '''
CREATE TABLE folders (
  id TEXT PRIMARY KEY,
  owner_id TEXT NOT NULL DEFAULT 'local',
  parent_id TEXT,
  name TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER
)''';

const createPagesTable = '''
CREATE TABLE pages (
  id TEXT PRIMARY KEY,
  note_id TEXT NOT NULL,
  page_index INTEGER NOT NULL,
  width REAL NOT NULL,
  height REAL NOT NULL,
  background_type TEXT,
  stroke_file TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)''';

const createAttachmentsTable = '''
CREATE TABLE attachments (
  id TEXT PRIMARY KEY,
  note_id TEXT NOT NULL,
  type TEXT NOT NULL,
  local_path TEXT NOT NULL,
  remote_path TEXT,
  size INTEGER,
  metadata_json TEXT,
  created_at INTEGER NOT NULL
)''';

const createSyncQueueTable = '''
CREATE TABLE sync_queue (
  id TEXT PRIMARY KEY,
  owner_id TEXT NOT NULL DEFAULT 'local',
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  operation TEXT NOT NULL,
  payload_path TEXT,
  created_at INTEGER NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  last_error TEXT
)''';
