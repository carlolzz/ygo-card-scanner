/// Each entry is the ordered list of DDL statements that take the schema
/// from version (key - 1) to version (key). Statements execute in list
/// order. This map is append-only: once a version is committed, fix
/// mistakes by adding version N+1, never by editing an existing entry.
const Map<int, List<String>> kMigrations = {
  1: [
    '''
    CREATE TABLE cards (
      passcode      TEXT PRIMARY KEY,
      name          TEXT NOT NULL,
      type          TEXT,
      frame_type    TEXT,
      attribute     TEXT,
      race          TEXT,
      atk           INTEGER,
      def           INTEGER,
      level         INTEGER,
      description   TEXT,
      image_url     TEXT,
      archetype     TEXT
    )
    ''',
    'CREATE INDEX idx_cards_name ON cards(name)',
    '''
    CREATE TABLE printings (
      id            INTEGER PRIMARY KEY AUTOINCREMENT,
      passcode      TEXT NOT NULL REFERENCES cards(passcode) ON DELETE CASCADE,
      set_code      TEXT,
      set_name      TEXT,
      rarity        TEXT,
      UNIQUE(passcode, set_code, rarity)
    )
    ''',
    'CREATE INDEX idx_printings_passcode ON printings(passcode)',
    '''
    CREATE TABLE collection_entries (
      id            INTEGER PRIMARY KEY AUTOINCREMENT,
      passcode      TEXT NOT NULL REFERENCES cards(passcode),
      printing_id   INTEGER REFERENCES printings(id),
      condition     TEXT NOT NULL,
      edition       TEXT NOT NULL DEFAULT 'UNLIMITED',
      language      TEXT NOT NULL DEFAULT 'EN',
      quantity      INTEGER NOT NULL DEFAULT 1 CHECK(quantity > 0),
      notes         TEXT,
      created_at    INTEGER NOT NULL,
      updated_at    INTEGER NOT NULL,
      UNIQUE(passcode, printing_id, condition, edition, language)
    )
    ''',
    'CREATE INDEX idx_entries_passcode ON collection_entries(passcode)',
    'CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT)',
  ],
  2: ['ALTER TABLE cards ADD COLUMN local_image_path TEXT'],
};

int get kSchemaVersion => kMigrations.keys.reduce((a, b) => a > b ? a : b);
