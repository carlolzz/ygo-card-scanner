import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ygo_scanner/data/db/dao/card_dao.dart';
import 'package:ygo_scanner/data/db/dao/card_price_dao.dart';
import 'package:ygo_scanner/models/card_prices.dart';
import 'package:ygo_scanner/models/ygo_card.dart';

import 'test_db.dart';

void main() {
  late Database db;
  late CardDao cardDao;
  late CardPriceDao dao;

  const blueEyes = YgoCard(passcode: '89631139', name: 'Blue-Eyes White Dragon');
  const mirrorForce = YgoCard(passcode: '44095762', name: 'Mirror Force');

  final stamp = DateTime.fromMillisecondsSinceEpoch(1700000000000);

  CardPrices priced(
    String passcode, {
    double? cardmarket,
    double? tcgplayer,
    DateTime? at,
  }) => CardPrices(
    passcode: passcode,
    cardmarket: cardmarket,
    tcgplayer: tcgplayer,
    updatedAt: at ?? stamp,
  );

  setUp(() async {
    db = await openInMemoryTestDb();
    cardDao = CardDao(db);
    dao = CardPriceDao(db);
    await cardDao.insertAll([blueEyes, mirrorForce]);
  });

  tearDown(() async {
    await db.close();
  });

  test('upsertAll then get round-trips every column', () async {
    await dao.upsertAll([
      CardPrices(
        passcode: '89631139',
        cardmarket: 1.23,
        tcgplayer: 4.56,
        ebay: 7.89,
        amazon: 10.11,
        coolstuffinc: 12.13,
        updatedAt: stamp,
      ),
    ]);

    final row = await dao.get('89631139');

    expect(row, isNotNull);
    expect(row!.cardmarket, 1.23);
    expect(row.tcgplayer, 4.56);
    expect(row.ebay, 7.89);
    expect(row.amazon, 10.11);
    expect(row.coolstuffinc, 12.13);
    expect(row.updatedAt, stamp);
  });

  test('a card that has never been priced has no row', () async {
    expect(await dao.get('44095762'), isNull);
  });

  // A price row is wholly derived from one API response, so a re-fetch replaces
  // it outright rather than merging — otherwise `updated_at` would describe only
  // some of the figures beside it.
  test('upserting the same card replaces the whole row', () async {
    final later = stamp.add(const Duration(days: 1));
    await dao.upsertAll([priced('89631139', cardmarket: 1, tcgplayer: 2)]);
    await dao.upsertAll([priced('89631139', cardmarket: 9, at: later)]);

    final row = await dao.get('89631139');

    expect(row!.cardmarket, 9);
    expect(row.tcgplayer, isNull, reason: 'replaced, not merged');
    expect(row.updatedAt, later);
  });

  group('getForPasscodes', () {
    test('returns one row per priced passcode', () async {
      await dao.upsertAll([
        priced('89631139', cardmarket: 1),
        priced('44095762', cardmarket: 2),
      ]);

      final rows = await dao.getForPasscodes(['89631139', '44095762']);

      expect(rows, hasLength(2));
      expect(
        {for (final row in rows) row.passcode: row.cardmarket},
        {'89631139': 1.0, '44095762': 2.0},
      );
    });

    // The absence *is* the information — an unpriced card is simply missing,
    // exactly as `get` returns null for it. Callers index by passcode.
    test('skips passcodes with no cached row', () async {
      await dao.upsertAll([priced('89631139', cardmarket: 1)]);

      final rows = await dao.getForPasscodes(['89631139', '44095762']);

      expect(rows.map((r) => r.passcode), ['89631139']);
    });

    // `IN ()` is not valid SQL, and an empty collection reaches this with
    // nothing to look up.
    test('an empty list is not a query at all', () async {
      expect(await dao.getForPasscodes(const []), isEmpty);
    });
  });

  // The whole reason the table carries a foreign key. `CardDao.insertAll` uses
  // `ConflictAlgorithm.replace`, so a re-sync deletes and re-inserts every
  // `cards` row — and the cascade takes the prices with it. Prices from before a
  // re-sync are the most stale ones, so this is the wanted behaviour, but it is
  // surprising enough to pin.
  test('re-syncing a card clears its cached prices', () async {
    await dao.upsertAll([priced('89631139', cardmarket: 1)]);
    expect(await dao.get('89631139'), isNotNull);

    await cardDao.insertAll([blueEyes]);

    expect(await dao.get('89631139'), isNull);
  });

  test('a price for an unknown card is rejected by the foreign key', () async {
    expect(
      () => dao.upsertAll([priced('00000000', cardmarket: 1)]),
      throwsA(isA<DatabaseException>()),
    );
  });
}
