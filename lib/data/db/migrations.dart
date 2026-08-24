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
  4: [
    // Two changes, both about the same discovery: YGOPRODeck's card-level
    // figures are near-useless as a valuation. The API documents each one as
    // "the lowest price found across multiple versions of that card", and in
    // practice `cardmarket_price` is €0.02 for Blue-Eyes White Dragon, Dark
    // Magician and Mirror Force alike. The per-set `card_sets[].set_price` is
    // the real figure ($74.49 for a CT13-EN008 Blue-Eyes), it arrives in the
    // same response, and it was being thrown away.
    //
    // **1. `card_prices` loses three vendors.** eBay, Amazon and CoolStuffInc
    // were displayed on a card's Prices tab and fed nothing else; with the
    // valuation now built on TCGplayer and Cardmarket they are dead weight.
    // Dropped and recreated rather than `ALTER TABLE ... DROP COLUMN`, which
    // needs SQLite 3.35 — sqflite uses Android's *system* SQLite, and API 30
    // ships 3.28. Safe to drop outright because this table is a pure cache: a
    // re-sync already empties it through the cascade below, and every row is
    // re-fetchable.
    'DROP TABLE IF EXISTS card_prices',
    '''
    CREATE TABLE card_prices (
      passcode      TEXT PRIMARY KEY REFERENCES cards(passcode) ON DELETE CASCADE,
      cardmarket    REAL,
      tcgplayer     REAL,
      updated_at    INTEGER NOT NULL
    )
    ''',
    // **2. Per-set prices are now stored**, reversing the v3 decision. One row
    // per printing, USD only — there is no per-set Cardmarket figure and there
    // never will be, so the euro total stays a card-level floor.
    //
    // **The cascade is load-bearing for correctness, not just hygiene.**
    // `printings.id` is AUTOINCREMENT and `printings.passcode` cascades from
    // `cards`, which `CardDao.insertAll` replaces wholesale on every re-sync —
    // so a re-sync *re-keys* every printing. A price row that outlived its
    // printing would then quietly describe a different one, at a different set
    // and rarity. The cascade is what makes that impossible.
    //
    // **A NULL `price` is not the same as a missing row, and both are written.**
    // `parsePrice` folds the API's very common "0.00" into null, so a great many
    // printings genuinely have no figure; the row records that we asked, and
    // when. Without it the freshness check could never be satisfied for those
    // printings and their card would be re-fetched on every single valuation,
    // forever.
    //
    // No index: `printing_id INTEGER PRIMARY KEY` is a rowid alias, which is
    // already the fastest lookup SQLite has.
    '''
    CREATE TABLE printing_prices (
      printing_id   INTEGER PRIMARY KEY REFERENCES printings(id) ON DELETE CASCADE,
      price         REAL,
      updated_at    INTEGER NOT NULL
    )
    ''',
  ],
  5: [
    // Card names in a language other than English, so manual search can be run
    // against them. The sync fetches `cardinfo.php` with no `language`
    // parameter, so `cards.name` is English and always will be; these rows come
    // from a bundled asset (`assets/card_names_it.json`, built by
    // `tools/build_localized_names.py`) rather than from the network.
    //
    // **Deliberately NO foreign key to `cards`.** Every other child table here
    // cascades from `cards` on purpose, because `CardDao.insertAll` uses
    // `ConflictAlgorithm.replace` and a re-sync therefore deletes and
    // re-inserts every card row. That is right for `printings` and the two
    // price caches — they come from the same response and are re-fetched with
    // it. It would be wrong here: these names are shipped in the APK, not
    // fetched, so a cascade would mean re-reading and re-inserting ~11.6k rows
    // after every sync to end up exactly where we started. A name row whose
    // passcode has no `cards` row is harmless: the search joins, so it simply
    // never surfaces.
    //
    // `language` is this app's two-letter code (`IT`), the same vocabulary as
    // `collection_entries.language` and `kCardLanguages` — not YGOPRODeck's
    // (`it`), which only the build tool ever sees.
    '''
    CREATE TABLE card_names (
      passcode      TEXT NOT NULL,
      language      TEXT NOT NULL,
      name          TEXT NOT NULL,
      PRIMARY KEY (passcode, language)
    )
    ''',
    // The search predicate is `name LIKE '%q%'`, which no index can serve — but
    // the prefix half of the ranking (`name LIKE 'q%'`) and the ORDER BY can
    // use this, and it keeps a 11.6k-row scan cheap.
    'CREATE INDEX idx_card_names_name ON card_names(name)',
  ],
};

int get kSchemaVersion => kMigrations.keys.reduce((a, b) => a > b ? a : b);
