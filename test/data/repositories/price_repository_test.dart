import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ygo_scanner/data/api/ygoprodeck_client.dart';
import 'package:ygo_scanner/data/db/dao/card_dao.dart';
import 'package:ygo_scanner/data/db/dao/card_price_dao.dart';
import 'package:ygo_scanner/data/db/dao/collection_dao.dart';
import 'package:ygo_scanner/data/repositories/price_repository.dart';
import 'package:ygo_scanner/models/card_condition.dart';
import 'package:ygo_scanner/models/card_edition.dart';
import 'package:ygo_scanner/models/card_prices.dart';
import 'package:ygo_scanner/models/collection_entry.dart';
import 'package:ygo_scanner/models/ygo_card.dart';

import '../db/test_db.dart';

const _blueEyes = YgoCard(passcode: '89631139', name: 'Blue-Eyes White Dragon');
const _mirrorForce = YgoCard(passcode: '44095762', name: 'Mirror Force');
const _darkMagician = YgoCard(passcode: '46986414', name: 'Dark Magician');

/// Records what was asked for, so the chunking and the "only fetch what is
/// stale" rule can both be asserted from outside. Subclassing the real client
/// mirrors `_FakeCardRepository` in the sync tests; its Dio is never touched.
class _FakeClient extends YgoProdeckClient {
  _FakeClient(this.prices);

  /// passcode -> (cardmarket, tcgplayer). A passcode absent here is one the API
  /// does not recognise.
  final Map<String, (double?, double?)> prices;

  final List<List<String>> requests = [];
  int get requestCount => requests.length;

  @override
  Future<List<CardPricing>> fetchPrices(List<String> passcodes) async {
    requests.add(List.of(passcodes));
    return [
      for (final passcode in passcodes)
        if (prices.containsKey(passcode))
          CardPricing(
            card: CardPrices(
              passcode: passcode,
              cardmarket: prices[passcode]!.$1,
              tcgplayer: prices[passcode]!.$2,
              updatedAt: DateTime.now(),
            ),
            sets: const [],
          ),
    ];
  }
}

void main() {
  late Database db;
  late CardPriceDao priceDao;
  late CollectionDao collectionDao;

  Future<void> own(String passcode, int quantity, {String language = 'EN'}) =>
      collectionDao.addOrIncrement(
        CollectionEntry(
          passcode: passcode,
          condition: CardCondition.nearMint,
          edition: CardEdition.unlimited,
          language: language,
          quantity: quantity,
          createdAt: 1000,
          updatedAt: 1000,
        ),
      );

  PriceRepository repositoryWith(_FakeClient client) => PriceRepository(
    priceDao: priceDao,
    collectionDao: collectionDao,
    client: client,
  );

  setUp(() async {
    db = await openInMemoryTestDb();
    priceDao = CardPriceDao(db);
    collectionDao = CollectionDao(db);
    await CardDao(db).insertAll([_blueEyes, _mirrorForce, _darkMagician]);
  });

  tearDown(() async {
    await db.close();
  });

  group('collectionValue', () {
    test('multiplies each card by how many copies are owned', () async {
      await own('89631139', 3);
      await own('44095762', 2);
      final client = _FakeClient({
        '89631139': (1.0, 10.0),
        '44095762': (2.5, 20.0),
      });

      final value = await repositoryWith(client).collectionValue();

      expect(value.cardmarketEur, 3 * 1.0 + 2 * 2.5);
      expect(value.tcgplayerUsd, 3 * 10.0 + 2 * 20.0);
      expect(value.pricedCards, 2);
      expect(value.unpricedCards, 0);
    });

    // Passcodes are language-independent, so a card held in two languages is
    // two rows under one passcode. It must be priced once, for the total.
    test('a card held in two languages is one lookup of both copies', () async {
      await own('89631139', 3);
      await own('89631139', 2, language: 'DE');
      final client = _FakeClient({'89631139': (1.0, 10.0)});

      final value = await repositoryWith(client).collectionValue();

      expect(client.requests.single, ['89631139']);
      expect(value.cardmarketEur, 5.0);
      expect(value.pricedCards, 1);
    });

    // The honesty check: a total assembled from part of a collection has to say
    // so, rather than quietly reading as the whole thing.
    test('a card the API does not recognise is counted, not zeroed', () async {
      await own('89631139', 1);
      await own('46986414', 4);
      final client = _FakeClient({'89631139': (1.0, 10.0)});

      final value = await repositoryWith(client).collectionValue();

      expect(value.cardmarketEur, 1.0);
      expect(value.pricedCards, 1);
      expect(value.unpricedCards, 1);
    });

    // `parsePrice` folds the API's very common "0.00" into null, so a card that
    // comes back with no usable figure at all is unpriced — the same case as a
    // card the API never heard of.
    test('a recognised card with no usable figure is unpriced', () async {
      await own('89631139', 1);
      final client = _FakeClient({'89631139': (null, null)});

      final value = await repositoryWith(client).collectionValue();

      expect(value.pricedCards, 0);
      expect(value.unpricedCards, 1);
    });

    test('an empty collection is zero without a single request', () async {
      final client = _FakeClient(const {});

      final value = await repositoryWith(client).collectionValue();

      expect(value.cardmarketEur, 0);
      expect(value.tcgplayerUsd, 0);
      expect(value.pricedCards, 0);
      expect(value.unpricedCards, 0);
      expect(value.asOf, isNull);
      expect(client.requestCount, 0);
    });

    test('reports progress in distinct passcodes', () async {
      await own('89631139', 1);
      await own('44095762', 1);
      final client = _FakeClient({
        '89631139': (1.0, 1.0),
        '44095762': (1.0, 1.0),
      });
      final seen = <(int, int)>[];

      await repositoryWith(
        client,
      ).collectionValue(onProgress: (done, total) => seen.add((done, total)));

      expect(seen.first, (0, 2), reason: 'nothing cached yet');
      expect(seen.last, (2, 2));
    });
  });

  group('the cache', () {
    test('a fresh row is reused instead of re-fetched', () async {
      await own('89631139', 1);
      await priceDao.upsertAll([
        CardPrices(
          passcode: '89631139',
          cardmarket: 7,
          tcgplayer: 8,
          updatedAt: DateTime.now(),
        ),
      ]);
      final client = _FakeClient({'89631139': (99.0, 99.0)});

      final value = await repositoryWith(client).collectionValue();

      expect(client.requestCount, 0);
      expect(value.cardmarketEur, 7);
    });

    test('a row past the TTL is re-fetched', () async {
      await own('89631139', 1);
      await priceDao.upsertAll([
        CardPrices(
          passcode: '89631139',
          cardmarket: 7,
          tcgplayer: 8,
          updatedAt: DateTime.now().subtract(kPriceTtl * 2),
        ),
      ]);
      final client = _FakeClient({'89631139': (99.0, 99.0)});

      final value = await repositoryWith(client).collectionValue();

      expect(client.requestCount, 1);
      expect(value.cardmarketEur, 99);
    });

    test('forceRefresh ignores a fresh row', () async {
      await own('89631139', 1);
      await priceDao.upsertAll([
        CardPrices(
          passcode: '89631139',
          cardmarket: 7,
          tcgplayer: 8,
          updatedAt: DateTime.now(),
        ),
      ]);
      final client = _FakeClient({'89631139': (99.0, 99.0)});

      final value = await repositoryWith(
        client,
      ).collectionValue(forceRefresh: true);

      expect(client.requestCount, 1);
      expect(value.cardmarketEur, 99);
    });

    // Written per chunk, not once at the end, so an interrupted run leaves its
    // progress behind and the retry picks up where it stopped.
    test('fetched prices are written to the cache', () async {
      await own('89631139', 1);
      final client = _FakeClient({'89631139': (1.5, 2.5)});

      await repositoryWith(client).collectionValue();

      final cached = await priceDao.get('89631139');
      expect(cached, isNotNull);
      expect(cached!.cardmarket, 1.5);
    });

    // The stamp shown beside the totals describes the whole of them, so it is
    // the oldest price used rather than the most recently refreshed corner.
    test('asOf is the oldest price contributing to the total', () async {
      // Built at millisecond resolution on purpose: timestamps are stored as
      // epoch **milliseconds** (the schema's standing rule), so a
      // `DateTime.now()` carrying microseconds does not round-trip.
      final old = _millisecondPrecision(
        DateTime.now().subtract(const Duration(hours: 12)),
      );
      await own('89631139', 1);
      await own('44095762', 1);
      await priceDao.upsertAll([
        CardPrices(passcode: '89631139', cardmarket: 1, updatedAt: old),
        CardPrices(
          passcode: '44095762',
          cardmarket: 1,
          updatedAt: DateTime.now(),
        ),
      ]);

      final value = await repositoryWith(
        _FakeClient(const {}),
      ).collectionValue();

      expect(value.asOf, old);
    });
  });

  // The API takes comma-separated ids; chunking is this repository's job so the
  // rate limit is reasoned about in one place.
  test('passcodes are fetched in chunks of kPriceChunkSize', () async {
    // More owned cards than one chunk holds, without seeding that many `cards`
    // rows: `quantityByPasscode` reads `collection_entries`, and the foreign key
    // is what forces those rows to exist — so seed them.
    final many = [
      for (var i = 0; i < kPriceChunkSize + 5; i++)
        (10000000 + i).toString(),
    ];
    await CardDao(db).insertAll([
      for (final passcode in many) YgoCard(passcode: passcode, name: passcode),
    ]);
    for (final passcode in many) {
      await own(passcode, 1);
    }
    final client = _FakeClient({for (final p in many) p: (1.0, 1.0)});

    await repositoryWith(client).collectionValue();

    expect(client.requestCount, 2);
    expect(client.requests.first, hasLength(kPriceChunkSize));
    expect(client.requests.last, hasLength(5));
  });

  group('cachedOrFetch', () {
    test('fetches and caches when nothing is stored', () async {
      final client = _FakeClient({'89631139': (1.0, 2.0)});

      final prices = await repositoryWith(client).cachedOrFetch('89631139');

      expect(prices!.cardmarket, 1.0);
      expect(await priceDao.get('89631139'), isNotNull);
    });

    // An estimate is a convenience: a failure to price a card must not take
    // down the detail screen the user opened to read its effect.
    test('a stale row survives a failed refresh', () async {
      final old = _millisecondPrecision(DateTime.now().subtract(kPriceTtl * 2));
      await priceDao.upsertAll([
        CardPrices(passcode: '89631139', cardmarket: 7, updatedAt: old),
      ]);

      final prices = await PriceRepository(
        priceDao: priceDao,
        collectionDao: collectionDao,
        client: _ThrowingClient(),
      ).cachedOrFetch('89631139');

      expect(prices!.cardmarket, 7);
      expect(prices.updatedAt, old, reason: 'and it still says how old it is');
    });

    test('an unknown card with nothing cached is null', () async {
      final client = _FakeClient(const {});
      expect(await repositoryWith(client).cachedOrFetch('89631139'), isNull);
    });
  });
}

/// Timestamps are stored as epoch milliseconds, so anything finer is lost on
/// the way through the database. Trimming up front keeps the assertions about
/// *which* timestamp was chosen rather than about clock resolution.
DateTime _millisecondPrecision(DateTime t) =>
    DateTime.fromMillisecondsSinceEpoch(t.millisecondsSinceEpoch);

class _ThrowingClient extends YgoProdeckClient {
  @override
  Future<List<CardPricing>> fetchPrices(List<String> passcodes) async =>
      throw Exception('offline');
}
