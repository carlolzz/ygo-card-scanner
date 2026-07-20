import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
    expect(versionResult.first['user_version'], 1);

    final metaResult = await db.query(
      'meta',
      where: 'key = ?',
      whereArgs: ['schema_version'],
    );
    expect(metaResult.single['value'], '1');
  });

  test('foreign keys are enforced on this connection', () async {
    final result = await db.rawQuery('PRAGMA foreign_keys');
    expect(result.first['foreign_keys'], 1);
  });
}
