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
        'meta',
        'idx_cards_name',
        'idx_printings_passcode',
        'idx_entries_passcode',
      ]),
    );
  });

  test('schema version is recorded via sqflite and in meta', () async {
    final versionResult = await db.rawQuery('PRAGMA user_version');
    expect(versionResult.first['user_version'], 2);

    final metaResult = await db.query(
      'meta',
      where: 'key = ?',
      whereArgs: ['schema_version'],
    );
    expect(metaResult.single['value'], '2');
  });

  test('foreign keys are enforced on this connection', () async {
    final result = await db.rawQuery('PRAGMA foreign_keys');
    expect(result.first['foreign_keys'], 1);
  });

  test('v2 adds cards.local_image_path', () async {
    final columns = await db.rawQuery('PRAGMA table_info(cards)');
    expect(columns.map((c) => c['name']), contains('local_image_path'));

    final versionResult = await db.rawQuery('PRAGMA user_version');
    expect(versionResult.first['user_version'], 2);
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
}
