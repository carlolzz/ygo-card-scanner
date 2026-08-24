import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ygo_scanner/data/db/database.dart';

import 'test_db.dart';

void main() {
  late Database db;

  setUp(() async {
    db = await openInMemoryTestDb();
  });

  tearDown(() async {
    await db.close();
  });

  test('migration runs clean and creates all tables and indices', () async {
    final rows = await db.query(
      'sqlite_master',
      columns: ['type', 'name'],
      where: "type IN ('table', 'index')",
    );
    final names = rows.map((r) => r['name'] as String).toSet();

    expect(
      names,
      containsAll(<String>[
        'cards',
        'printings',
        'collection_entries',
        'card_prices',
        'printing_prices',
        'card_names',
        'meta',
        'idx_cards_name',
        'idx_printings_passcode',
        'idx_entries_passcode',
        'idx_card_names_name',
      ]),
    );
  });

  test('schema version is recorded via sqflite and in meta', () async {
    final versionResult = await db.rawQuery('PRAGMA user_version');
    expect(versionResult.first['user_version'], 5);

    final metaResult = await db.query(
      'meta',
      where: 'key = ?',
      whereArgs: ['schema_version'],
    );
    expect(metaResult.single['value'], '5');
  });

  test('foreign keys are enforced on this connection', () async {
    final result = await db.rawQuery('PRAGMA foreign_keys');
    expect(result.first['foreign_keys'], 1);
  });

  test('v2 adds cards.local_image_path', () async {
    final columns = await db.rawQuery('PRAGMA table_info(cards)');
    expect(columns.map((c) => c['name']), contains('local_image_path'));
  });

  // v3 created this table with five vendor columns; v4 dropped and recreated it
  // with two. A fresh install replays both, so this is what it ends up with.
  test('v4 leaves card_prices with only the two vendors in use', () async {
    final columns = await db.rawQuery('PRAGMA table_info(card_prices)');

    expect(columns.map((c) => c['name']), <String>[
      'passcode',
      'cardmarket',
      'tcgplayer',
      'updated_at',
    ]);
  });

  test('v4 adds the printing_prices cache', () async {
    final columns = await db.rawQuery('PRAGMA table_info(printing_prices)');

    expect(columns.map((c) => c['name']), <String>[
      'printing_id',
      'price',
      'updated_at',
    ]);
  });

  test('upgrading from v1 to v2 preserves existing rows', () async {
    // singleInstance: false — otherwise sqflite would hand back the
    // already-open (and already-v2) `db` from setUp for the same
    // in-memory path, instead of a genuinely fresh v1 connection.
    final v1Db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: AppDatabase.onConfigure,
        onCreate: AppDatabase.onCreate,
        singleInstance: false,
      ),
    );
    await v1Db.insert('cards', {
      'passcode': '89631139',
      'name': 'Blue-Eyes White Dragon',
    });

    await AppDatabase.onUpgrade(v1Db, 1, 2);

    final rows = await v1Db.query('cards');
    expect(rows, hasLength(1));
    expect(rows.single['name'], 'Blue-Eyes White Dragon');
    expect(rows.single['local_image_path'], isNull);

    final columns = await v1Db.rawQuery('PRAGMA table_info(cards)');
    expect(columns.map((c) => c['name']), contains('local_image_path'));

    await v1Db.close();
  });

  test('upgrading from v2 to v3 preserves existing rows', () async {
    final v2Db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 2,
        onConfigure: AppDatabase.onConfigure,
        onCreate: AppDatabase.onCreate,
        singleInstance: false,
      ),
    );
    await v2Db.insert('cards', {
      'passcode': '89631139',
      'name': 'Blue-Eyes White Dragon',
      'local_image_path': '/cards/89631139.jpg',
    });

    await AppDatabase.onUpgrade(v2Db, 2, 3);

    final rows = await v2Db.query('cards');
    expect(rows, hasLength(1));
    expect(rows.single['local_image_path'], '/cards/89631139.jpg');

    // The new table starts empty — prices are fetched on demand, never
    // backfilled by the migration.
    expect(await v2Db.query('card_prices'), isEmpty);

    await v2Db.close();
  });

  // v4 **drops** `card_prices` rather than altering it, which is only safe
  // because it is a pure re-fetchable cache. The cards, printings and — above
  // all — the user's own collection rows must come through untouched.
  test(
    'upgrading from v3 to v4 keeps user data and empties the cache',
    () async {
      final v3Db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 3,
          onConfigure: AppDatabase.onConfigure,
          onCreate: AppDatabase.onCreate,
          singleInstance: false,
        ),
      );
      await v3Db.insert('cards', {
        'passcode': '89631139',
        'name': 'Blue-Eyes White Dragon',
      });
      final printingId = await v3Db.insert('printings', {
        'passcode': '89631139',
        'set_code': 'LOB-001',
        'set_name': 'Legend of Blue Eyes White Dragon',
        'rarity': 'Ultra Rare',
      });
      await v3Db.insert('collection_entries', {
        'passcode': '89631139',
        'printing_id': printingId,
        'condition': 'NEAR_MINT',
        'edition': 'UNLIMITED',
        'language': 'EN',
        'quantity': 3,
        'created_at': 1700000000000,
        'updated_at': 1700000000000,
      });
      await v3Db.insert('card_prices', {
        'passcode': '89631139',
        'cardmarket': 0.02,
        'tcgplayer': 0.15,
        'ebay': 5.95,
        'amazon': 3.90,
        'coolstuffinc': 0.99,
        'updated_at': 1700000000000,
      });

      await AppDatabase.onUpgrade(v3Db, 3, 4);

      expect(await v3Db.query('cards'), hasLength(1));
      expect(await v3Db.query('printings'), hasLength(1));
      final entries = await v3Db.query('collection_entries');
      expect(entries, hasLength(1), reason: 'user data survives');
      expect(entries.single['quantity'], 3);

      // Dropped and recreated: every row is re-fetchable, and a re-sync already
      // empties this table through the cascade.
      expect(await v3Db.query('card_prices'), isEmpty);
      expect(await v3Db.query('printing_prices'), isEmpty);

      final columns = await v3Db.rawQuery('PRAGMA table_info(card_prices)');
      expect(columns.map((c) => c['name']), isNot(contains('ebay')));

      await v3Db.close();
    },
  );

  test('v5 adds card_names, keyed on (passcode, language)', () async {
    final columns = await db.rawQuery('PRAGMA table_info(card_names)');
    expect(columns.map((c) => c['name']), <String>[
      'passcode',
      'language',
      'name',
    ]);

    await db.insert('card_names', {
      'passcode': '89631139',
      'language': 'IT',
      'name': 'Drago Bianco Occhi Blu',
    });
    // The same card in two languages is two rows; the same card twice in one
    // language is a conflict the composite primary key catches.
    await db.insert('card_names', {
      'passcode': '89631139',
      'language': 'FR',
      'name': 'Dragon Blanc aux Yeux Bleus',
    });
    expect(await db.query('card_names'), hasLength(2));
    await expectLater(
      db.insert('card_names', {
        'passcode': '89631139',
        'language': 'IT',
        'name': 'duplicate',
      }),
      throwsA(isA<DatabaseException>()),
    );
  });

  // Load-bearing, and the opposite of every other child table here: a re-sync
  // replaces every `cards` row, and these names come from a bundled asset
  // rather than the response, so they must NOT go with it.
  test('card_names has no cascade from cards', () async {
    await db.insert('cards', {
      'passcode': '89631139',
      'name': 'Blue-Eyes White Dragon',
    });
    await db.insert('card_names', {
      'passcode': '89631139',
      'language': 'IT',
      'name': 'Drago Bianco Occhi Blu',
    });

    // Exactly what `CardDao.insertAll` does on every sync.
    await db.insert('cards', {
      'passcode': '89631139',
      'name': 'Blue-Eyes White Dragon',
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    expect(await db.query('card_names'), hasLength(1));
  });

  test('upgrading from v4 to v5 keeps user data', () async {
    final v4Db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 4,
        onConfigure: AppDatabase.onConfigure,
        onCreate: AppDatabase.onCreate,
        singleInstance: false,
      ),
    );
    await v4Db.insert('cards', {
      'passcode': '89631139',
      'name': 'Blue-Eyes White Dragon',
    });
    await v4Db.insert('collection_entries', {
      'passcode': '89631139',
      'condition': 'NEAR_MINT',
      'edition': 'UNLIMITED',
      'language': 'EN',
      'quantity': 2,
      'created_at': 1700000000000,
      'updated_at': 1700000000000,
    });

    await AppDatabase.onUpgrade(v4Db, 4, 5);

    final entries = await v4Db.query('collection_entries');
    expect(entries, hasLength(1));
    expect(entries.single['quantity'], 2);
    // Starts empty: the asset is imported on first use, not by the migration.
    expect(await v4Db.query('card_names'), isEmpty);

    await v4Db.close();
  });
}
