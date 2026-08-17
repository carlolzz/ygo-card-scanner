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
  3: [
    // Card-level market prices from YGOPRODeck's `card_prices`, cached so the
    // collection-value total is instant on reopen and readable offline. One row
    // per card, not per printing: the API only reports per-set prices as a
    // single USD `set_price`, and those are read live on the card's Prices tab
    // rather than stored.
    //
    // `cardmarket` is EUR; every other column is USD. They are never summed
    // together — the collection total is reported as two separate figures.
    //
    // **The cascade is load-bearing, and it means a re-sync clears this cache.**
    // `CardDao.insertAll` uses `ConflictAlgorithm.replace`, i.e. `INSERT OR
    // REPLACE`, which deletes and re-inserts each `cards` row, so every child
    // row with an `ON DELETE CASCADE` goes with it — exactly what already
    // happens to `printings` and `cards.local_image_path`. That is the wanted
    // behaviour here: prices from before a re-sync are the most stale ones.
    '''
    CREATE TABLE card_prices (
      passcode      TEXT PRIMARY KEY REFERENCES cards(passcode) ON DELETE CASCADE,
      cardmarket    REAL,
      tcgplayer     REAL,
      ebay          REAL,
      amazon        REAL,
      coolstuffinc  REAL,
      updated_at    INTEGER NOT NULL
    )
    ''',
  ],
};

int get kSchemaVersion => kMigrations.keys.reduce((a, b) => a > b ? a : b);
