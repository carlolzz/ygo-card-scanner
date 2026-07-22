import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ygo_scanner/data/db/dao/card_dao.dart';
import 'package:ygo_scanner/models/ygo_card.dart';

import 'test_db.dart';

void main() {
  late Database db;
  late CardDao dao;

  setUp(() async {
    db = await openInMemoryTestDb();
    dao = CardDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  const blueEyes = YgoCard(passcode: '89631139', name: 'Blue-Eyes White Dragon');
  const redEyes = YgoCard(passcode: '74677422', name: 'Red-Eyes Black Dragon');
  const toonBlueEyes = YgoCard(
    passcode: '53183600',
    name: 'Toon Blue-Eyes White Dragon',
  );

  test('insertAll then getByPasscode round-trips a card', () async {
    await dao.insertAll([blueEyes]);

    final result = await dao.getByPasscode(blueEyes.passcode);

    expect(result, blueEyes);
  });

  test('getByPasscode returns null for an unknown passcode', () async {
    final result = await dao.getByPasscode('00000000');
    expect(result, isNull);
  });

  test('count reflects the number of inserted cards', () async {
    await dao.insertAll([blueEyes, redEyes]);
    expect(await dao.count(), 2);
  });

  test('searchByName ranks prefix matches above substring-only matches', () async {
    await dao.insertAll([toonBlueEyes, redEyes, blueEyes]);

    final results = await dao.searchByName('Blue-Eyes');

    expect(results.map((c) => c.name), [
      'Blue-Eyes White Dragon',
      'Toon Blue-Eyes White Dragon',
    ]);
  });

  test('updateLocalImagePath sets the column, reflected by getByPasscode', () async {
    await dao.insertAll([blueEyes]);

    await dao.updateLocalImagePath(blueEyes.passcode, '/tmp/89631139.jpg');

    final result = await dao.getByPasscode(blueEyes.passcode);
    expect(result?.localImagePath, '/tmp/89631139.jpg');
  });

  test('updateLocalImagePath is a no-op for an unknown passcode', () async {
    await expectLater(
      dao.updateLocalImagePath('00000000', '/tmp/00000000.jpg'),
      completes,
    );
  });
}
