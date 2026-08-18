import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ygo_scanner/data/db/dao/card_dao.dart';
import 'package:ygo_scanner/data/db/dao/printing_dao.dart';
import 'package:ygo_scanner/data/db/dao/printing_price_dao.dart';
import 'package:ygo_scanner/models/card_prices.dart';
import 'package:ygo_scanner/models/printing.dart';
import 'package:ygo_scanner/models/ygo_card.dart';

import 'test_db.dart';

void main() {
  late Database db;
  late CardDao cardDao;
  late PrintingDao printingDao;
  late PrintingPriceDao dao;

  const blueEyes = YgoCard(passcode: '89631139', name: 'Blue-Eyes White Dragon');

  final stamp = DateTime.fromMillisecondsSinceEpoch(1700000000000);

  late int lobId;
  late int sdkId;

  setUp(() async {
    db = await openInMemoryTestDb();
    cardDao = CardDao(db);
    printingDao = PrintingDao(db);
    dao = PrintingPriceDao(db);

    await cardDao.insertAll([blueEyes]);
    await printingDao.insertAll(const [
      Printing(
        passcode: '89631139',
        setCode: 'LOB-001',
        setName: 'Legend of Blue Eyes White Dragon',
        rarity: 'Ultra Rare',
      ),
      Printing(
        passcode: '89631139',
        setCode: 'SDK-001',
        setName: 'Starter Deck: Kaiba',
        rarity: 'Ultra Rare',
      ),
    ]);
    final printings = await printingDao.getForPasscode('89631139');
    lobId = printings.firstWhere((p) => p.setCode == 'LOB-001').id!;
    sdkId = printings.firstWhere((p) => p.setCode == 'SDK-001').id!;
  });

  tearDown(() async {
    await db.close();
  });

  test('upsertAll then get round-trips every column', () async {
    await dao.upsertAll([
      PrintingPrice(printingId: lobId, price: 236.85, updatedAt: stamp),
    ]);

    final row = await dao.get(lobId);

    expect(row, isNotNull);
    expect(row!.printingId, lobId);
    expect(row.price, 236.85);
    expect(row.updatedAt, stamp);
  });

  // The distinction the whole table rests on. A null price says "we asked, and
  // YGOPRODeck had no figure for this printing" — which is what stops its card
  // being re-fetched on every valuation forever. An absent row says "never
  // asked". Conflating them is either an endless refetch or a printing that is
  // silently never priced.
  test('a null price is a stored answer, not an absent row', () async {
    await dao.upsertAll([
      PrintingPrice(printingId: lobId, price: null, updatedAt: stamp),
    ]);

    final asked = await dao.get(lobId);
    expect(asked, isNotNull, reason: 'the row exists');
    expect(asked!.price, isNull);
    expect(asked.updatedAt, stamp, reason: 'it records when we asked');

    expect(await dao.get(sdkId), isNull, reason: 'never asked');
  });

  // Same reasoning as `CardPriceDao`: a price row is wholly derived from one API
  // response, so a re-fetch replaces it rather than merging.
  test('upserting the same printing replaces the whole row', () async {
    final later = stamp.add(const Duration(days: 1));
    await dao.upsertAll([
      PrintingPrice(printingId: lobId, price: 236.85, updatedAt: stamp),
    ]);
    await dao.upsertAll([
      PrintingPrice(printingId: lobId, price: null, updatedAt: later),
    ]);

    final row = await dao.get(lobId);

    expect(row!.price, isNull, reason: 'replaced, not merged');
    expect(row.updatedAt, later);
  });

  group('getForPrintings', () {
    test('returns one row per priced printing', () async {
      await dao.upsertAll([
        PrintingPrice(printingId: lobId, price: 236.85, updatedAt: stamp),
        PrintingPrice(printingId: sdkId, price: 4.5, updatedAt: stamp),
      ]);

      final rows = await dao.getForPrintings([lobId, sdkId]);

      expect(rows, hasLength(2));
      expect(
        {for (final row in rows) row.printingId: row.price},
        {lobId: 236.85, sdkId: 4.5},
      );
    });

    test('skips printings with no cached row', () async {
      await dao.upsertAll([
        PrintingPrice(printingId: lobId, price: 1, updatedAt: stamp),
      ]);

      final rows = await dao.getForPrintings([lobId, sdkId]);

      expect(rows.map((r) => r.printingId), [lobId]);
    });

    // `IN ()` is not valid SQL, and a collection logged entirely without sets
    // reaches this with nothing to look up.
    test('an empty list is not a query at all', () async {
      expect(await dao.getForPrintings(const []), isEmpty);
    });
  });

  // **The correctness of the whole table rests on this.** `printings.id` is
  // AUTOINCREMENT and `printings.passcode` cascades from `cards`, which
  // `CardDao.insertAll` replaces wholesale — so a re-sync re-keys every
  // printing. A price row that outlived its printing would quietly describe a
  // different one, at a different set and rarity.
  test('re-syncing a card clears its printings\' cached prices', () async {
    await dao.upsertAll([
      PrintingPrice(printingId: lobId, price: 236.85, updatedAt: stamp),
    ]);
    expect(await dao.get(lobId), isNotNull);

    await cardDao.insertAll([blueEyes]);

    expect(await dao.get(lobId), isNull);
    expect(
      await printingDao.getForPasscode('89631139'),
      isEmpty,
      reason: 'the printings went with the card, taking their prices',
    );
  });

  test('a price for an unknown printing is rejected by the foreign key', () {
    expect(
      () => dao.upsertAll([
        PrintingPrice(printingId: 999999, price: 1, updatedAt: stamp),
      ]),
      throwsA(isA<DatabaseException>()),
    );
  });
}
