import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ygo_scanner/data/db/dao/card_dao.dart';
import 'package:ygo_scanner/data/db/dao/printing_dao.dart';
import 'package:ygo_scanner/models/printing.dart';
import 'package:ygo_scanner/models/ygo_card.dart';

import 'test_db.dart';

void main() {
  late Database db;
  late CardDao cardDao;
  late PrintingDao dao;

  const blueEyes = YgoCard(passcode: '89631139', name: 'Blue-Eyes White Dragon');

  setUp(() async {
    db = await openInMemoryTestDb();
    cardDao = CardDao(db);
    dao = PrintingDao(db);
    await cardDao.insertAll([blueEyes]);
  });

  tearDown(() async {
    await db.close();
  });

  test('insertAll then getForPasscode returns all printings for a card', () async {
    await dao.insertAll([
      const Printing(passcode: '89631139', setCode: 'LOB-EN001', rarity: 'Ultra Rare'),
      const Printing(passcode: '89631139', setCode: 'SDK-001', rarity: 'Ultra Rare'),
    ]);

    final printings = await dao.getForPasscode('89631139');

    expect(printings, hasLength(2));
    expect(printings.map((p) => p.setCode), containsAll(['LOB-EN001', 'SDK-001']));
    expect(printings.every((p) => p.id != null), isTrue);
  });

  test('getForPasscode returns an empty list for a card with no printings', () async {
    final printings = await dao.getForPasscode('89631139');
    expect(printings, isEmpty);
  });
}
