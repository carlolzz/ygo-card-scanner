import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ygo_scanner/data/db/dao/meta_dao.dart';

import 'test_db.dart';

void main() {
  late Database db;
  late MetaDao dao;

  setUp(() async {
    db = await openInMemoryTestDb();
    dao = MetaDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('get returns null for an absent key', () async {
    expect(await dao.get('last_sync'), isNull);
  });

  test('set then get round-trips a value', () async {
    await dao.set('last_sync', '12345');
    expect(await dao.get('last_sync'), '12345');
  });

  test('set overwrites an existing key', () async {
    await dao.set('last_sync', '111');
    await dao.set('last_sync', '222');
    expect(await dao.get('last_sync'), '222');
  });
}
