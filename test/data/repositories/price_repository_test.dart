import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ygo_scanner/data/api/ygoprodeck_client.dart';
import 'package:ygo_scanner/data/db/dao/card_dao.dart';
import 'package:ygo_scanner/data/db/dao/card_price_dao.dart';
import 'package:ygo_scanner/data/db/dao/collection_dao.dart';
import 'package:ygo_scanner/data/db/dao/printing_dao.dart';
import 'package:ygo_scanner/data/db/dao/printing_price_dao.dart';
import 'package:ygo_scanner/data/repositories/price_repository.dart';
import 'package:ygo_scanner/models/card_condition.dart';
import 'package:ygo_scanner/models/card_edition.dart';
import 'package:ygo_scanner/models/card_prices.dart';
import 'package:ygo_scanner/models/collection_entry.dart';
import 'package:ygo_scanner/models/printing.dart';
import 'package:ygo_scanner/models/ygo_card.dart';

import '../db/test_db.dart';

const _blueEyes = YgoCard(passcode: '89631139', name: 'Blue-Eyes White Dragon');
const _mirrorForce = YgoCard(passcode: '44095762', name: 'Mirror Force');
const _darkMagician = YgoCard(passcode: '46986414', name: 'Dark Magician');

/// Records what was asked for, so the chunking and the "only fetch what is
/// stale" rule can both be asserted from outside. Subclassing the real client
/// mirrors `_FakeCardRepository` in the sync tests; its Dio is never touched.
class _FakeClient extends YgoProdeckClient {
  _FakeClient(this.prices, {this.sets = const {}});

  /// passcode -> (cardmarket, tcgplayer). A passcode absent here is one the API
  /// does not recognise. These are the **card-level floor** figures.
  final Map<String, (double?, double?)> prices;

  /// passcode -> the `card_sets` entries the API reports for it, each
  /// `(setCode, rarity, setPrice)`. Empty by default, which makes every line
  /// fall back to the card floor — the pre-step-26 behaviour, so the older
  /// assertions in this file double as the fallback regression suite.
  final Map<String, List<(String?, String?, double?)>> sets;

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
            sets: [
              for (final set in sets[passcode] ?? const <(String?, String?, double?)>[])
                SetPrice(setCode: set.$1, rarity: set.$2, price: set.$3),
            ],
          ),
    ];
  }
}

void main() {
  late Database db;
  late CardPriceDao priceDao;
  late PrintingPriceDao printingPriceDao;
  late CollectionDao collectionDao;
  late PrintingDao printingDao;
  late CardDao cardDao;

  Future<void> own(
    String passcode,
    int quantity, {
    String language = 'EN',
    int? printingId,
  }) => collectionDao.addOrIncrement(
    CollectionEntry(
      passcode: passcode,
      printingId: printingId,
      condition: CardCondition.nearMint,
      edition: CardEdition.unlimited,
      language: language,
      quantity: quantity,
      createdAt: 1000,
      updatedAt: 1000,
    ),
  );

  /// Inserts a printing and hands back its id, which is what the collection
  /// entries and the `printing_prices` rows are keyed on.
  Future<int> printing(
    String passcode, {
    required String setCode,
    required String rarity,
  }) async {
    await printingDao.insertAll([
      Printing(passcode: passcode, setCode: setCode, rarity: rarity),
    ]);
    final rows = await printingDao.getForPasscode(passcode);
    return rows.firstWhere((p) => p.setCode == setCode).id!;
  }

  PriceRepository repositoryWith(_FakeClient client) => PriceRepository(
    priceDao: priceDao,
    printingPriceDao: printingPriceDao,
    collectionDao: collectionDao,
    printingDao: printingDao,
    cardDao: cardDao,
    client: client,
  );

  setUp(() async {
    db = await openInMemoryTestDb();
    priceDao = CardPriceDao(db);
    printingPriceDao = PrintingPriceDao(db);
    collectionDao = CollectionDao(db);
    printingDao = PrintingDao(db);
    cardDao = CardDao(db);
    await cardDao.insertAll([_blueEyes, _mirrorForce, _darkMagician]);
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

  // The per-printing rows behind the two totals, which the breakdown screen
  // shows and the value export writes. They are built in the same pass that
  // accumulates the totals, so the file and the screen cannot disagree — these
  // assertions are what pin that.
  group('the value breakdown', () {
    test('carries each card with its name and copies owned', () async {
      await own('89631139', 3);
      await own('89631139', 2, language: 'DE');
      final client = _FakeClient({'89631139': (1.5, 10.0)});

      final value = await repositoryWith(client).collectionValue();

      final line = value.lines.single;
      expect(line.passcode, '89631139');
      expect(line.name, 'Blue-Eyes White Dragon');
      expect(line.quantity, 5, reason: 'both languages, one card');
      expect(line.cardmarketEur, 1.5);
      expect(line.tcgplayerUsd, 10.0);
      expect(line.usdBasis, PriceBasis.cardFloor, reason: 'no set recorded');
      expect(line.printingId, isNull);
      expect(line.pricedAt, isNotNull);
    });

    // The whole reason to keep the rows: `unpricedCards` says how many cards
    // the totals leave out, and only the breakdown can say which.
    test('includes unpriced cards, carrying nulls', () async {
      await own('89631139', 1);
      await own('46986414', 4);
      final client = _FakeClient({'89631139': (1.0, 10.0)});

      final value = await repositoryWith(client).collectionValue();

      final unpriced = value.lines.singleWhere((l) => l.passcode == '46986414');
      expect(unpriced.name, 'Dark Magician');
      expect(unpriced.quantity, 4);
      expect(unpriced.cardmarketEur, isNull);
      expect(unpriced.tcgplayerUsd, isNull);
      expect(unpriced.usdBasis, PriceBasis.none);
      expect(unpriced.pricedAt, isNull);
      expect(value.lines, hasLength(2), reason: 'priced or not, every card');
    });

    // If the lines and the totals could ever disagree, the exported file would
    // quietly contradict the figures the user is looking at.
    test('the lines add up to the totals', () async {
      await own('89631139', 3);
      await own('44095762', 2);
      await own('46986414', 1);
      final client = _FakeClient({
        '89631139': (1.0, 10.0),
        '44095762': (2.5, 20.0),
      });

      final value = await repositoryWith(client).collectionValue();

      double sum(double? Function(CollectionValueLine) price) => value.lines
          .map((l) => (price(l) ?? 0) * l.quantity)
          .fold(0.0, (a, b) => a + b);

      expect(sum((l) => l.cardmarketEur), value.cardmarketEur);
      expect(sum((l) => l.tcgplayerUsd), value.tcgplayerUsd);
    });

    test('is sorted by name', () async {
      await own('89631139', 1); // Blue-Eyes White Dragon
      await own('44095762', 1); // Mirror Force
      await own('46986414', 1); // Dark Magician
      final client = _FakeClient(const {});

      final value = await repositoryWith(client).collectionValue();

      expect(value.lines.map((l) => l.name), [
        'Blue-Eyes White Dragon',
        'Dark Magician',
        'Mirror Force',
      ]);
    });

    test('an empty collection has no lines', () async {
      final value = await repositoryWith(_FakeClient(const {})).collectionValue();
      expect(value.lines, isEmpty);
    });
  });

  // The point of step 26. YGOPRODeck's card-level figure is documented as the
  // lowest across every version of a card — €0.02 for Blue-Eyes, Dark Magician
  // and Mirror Force alike — while `card_sets[].set_price` puts a CT13-EN008
  // Blue-Eyes at $74.49. Both arrive in the same response.
  group('pricing by printing', () {
    test('a printing with a set_price beats the card floor', () async {
      final ct13 = await printing(
        '89631139',
        setCode: 'CT13-EN008',
        rarity: 'Ultra Rare',
      );
      await own('89631139', 2, printingId: ct13);
      final client = _FakeClient(
        {'89631139': (0.02, 0.15)},
        sets: {
          '89631139': [('CT13-EN008', 'Ultra Rare', 74.49)],
        },
      );

      final value = await repositoryWith(client).collectionValue();

      final line = value.lines.single;
      expect(line.tcgplayerUsd, 74.49);
      expect(line.usdBasis, PriceBasis.printing);
      expect(line.setCode, 'CT13-EN008');
      expect(line.rarity, 'Ultra Rare');
      expect(value.tcgplayerUsd, 2 * 74.49);
      // Euros have no per-printing figure and never will — the floor stands.
      expect(line.cardmarketEur, 0.02);
      expect(value.cardmarketEur, 2 * 0.02);
    });

    test('copies logged without a set use the card floor', () async {
      await own('89631139', 2);
      final client = _FakeClient(
        {'89631139': (0.02, 0.15)},
        sets: {
          '89631139': [('CT13-EN008', 'Ultra Rare', 74.49)],
        },
      );

      final value = await repositoryWith(client).collectionValue();

      final line = value.lines.single;
      expect(line.tcgplayerUsd, 0.15);
      expect(line.usdBasis, PriceBasis.cardFloor);
      expect(line.setCode, isNull);
    });

    // `parsePrice` folds the API's very common "0.00" into null, so a printing
    // the API lists with no figure is not a free card — it falls back, and the
    // card still counts as priced.
    test('a printing with no figure falls back without being unpriced', () async {
      final sdk = await printing(
        '89631139',
        setCode: 'SDK-001',
        rarity: 'Ultra Rare',
      );
      await own('89631139', 1, printingId: sdk);
      final client = _FakeClient(
        {'89631139': (0.02, 0.15)},
        sets: {
          '89631139': [('SDK-001', 'Ultra Rare', null)],
        },
      );

      final value = await repositoryWith(client).collectionValue();

      expect(value.lines.single.usdBasis, PriceBasis.cardFloor);
      expect(value.lines.single.tcgplayerUsd, 0.15);
      expect(value.pricedCards, 1);
      expect(value.unpricedCards, 0);
    });

    test('two printings of one card price differently', () async {
      final ct13 = await printing(
        '89631139',
        setCode: 'CT13-EN008',
        rarity: 'Ultra Rare',
      );
      final lob = await printing(
        '89631139',
        setCode: 'LOB-001',
        rarity: 'Ultra Rare',
      );
      await own('89631139', 1, printingId: ct13);
      await own('89631139', 3, printingId: lob);
      final client = _FakeClient(
        {'89631139': (0.02, 0.15)},
        sets: {
          '89631139': [
            ('CT13-EN008', 'Ultra Rare', 74.49),
            ('LOB-001', 'Ultra Rare', 236.85),
          ],
        },
      );

      final value = await repositoryWith(client).collectionValue();

      expect(value.lines, hasLength(2));
      expect(
        {for (final l in value.lines) l.setCode: l.tcgplayerUsd},
        {'CT13-EN008': 74.49, 'LOB-001': 236.85},
      );
      expect(value.tcgplayerUsd, 1 * 74.49 + 3 * 236.85);
      // One card, two lines — the counts are per card and must not follow the
      // grain of the lines.
      expect(value.pricedCards, 1);
      expect(value.lines.length, 2);
      expect(value.printingPricedLines, 2);
    });

    // Rarity is half the key on purpose: matching on set code alone would give
    // a Common the Secret Rare's price, an order of magnitude wrong with
    // nothing on screen to suggest it.
    test('the same set at another rarity does not match', () async {
      final common = await printing(
        '89631139',
        setCode: 'LOB-001',
        rarity: 'Common',
      );
      await own('89631139', 1, printingId: common);
      final client = _FakeClient(
        {'89631139': (0.02, 0.15)},
        sets: {
          '89631139': [('LOB-001', 'Ultra Rare', 236.85)],
        },
      );

      final value = await repositoryWith(client).collectionValue();

      expect(value.lines.single.usdBasis, PriceBasis.cardFloor);
      expect(value.lines.single.tcgplayerUsd, 0.15);
    });

    test('a set the app does not store is simply ignored', () async {
      await own('89631139', 1);
      final client = _FakeClient(
        {'89631139': (0.02, 0.15)},
        sets: {
          '89631139': [('NEVER-HEARD-OF', 'Secret Rare', 999.0)],
        },
      );

      final value = await repositoryWith(client).collectionValue();

      expect(value.tcgplayerUsd, 0.15);
    });

    // Any deterministic rule would do; an unstated "last one seen" is how two
    // runs report two different totals. Lowest matches every other floor
    // convention in this app.
    test('duplicate set entries take the lowest price', () async {
      final lob = await printing(
        '89631139',
        setCode: 'LOB-001',
        rarity: 'Ultra Rare',
      );
      await own('89631139', 1, printingId: lob);
      final client = _FakeClient(
        {'89631139': (0.02, 0.15)},
        sets: {
          '89631139': [
            ('LOB-001', 'Ultra Rare', 236.85),
            ('LOB-001', 'Ultra Rare', 180.00),
          ],
        },
      );

      final value = await repositoryWith(client).collectionValue();

      expect(value.lines.single.tcgplayerUsd, 180.00);
    });

    test('the lines still add up to the totals', () async {
      final ct13 = await printing(
        '89631139',
        setCode: 'CT13-EN008',
        rarity: 'Ultra Rare',
      );
      await own('89631139', 2, printingId: ct13);
      await own('89631139', 1);
      await own('44095762', 4);
      final client = _FakeClient(
        {'89631139': (0.02, 0.15), '44095762': (0.02, 0.65)},
        sets: {
          '89631139': [('CT13-EN008', 'Ultra Rare', 74.49)],
        },
      );

      final value = await repositoryWith(client).collectionValue();

      double sum(double? Function(CollectionValueLine) price) => value.lines
          .map((l) => (price(l) ?? 0) * l.quantity)
          .fold(0.0, (a, b) => a + b);

      expect(sum((l) => l.cardmarketEur), closeTo(value.cardmarketEur, 1e-9));
      expect(sum((l) => l.tcgplayerUsd), closeTo(value.tcgplayerUsd, 1e-9));
    });
  });

  group('the printing price cache', () {
    test('fetched set prices are written through', () async {
      final ct13 = await printing(
        '89631139',
        setCode: 'CT13-EN008',
        rarity: 'Ultra Rare',
      );
      await own('89631139', 1, printingId: ct13);
      final client = _FakeClient(
        {'89631139': (0.02, 0.15)},
        sets: {
          '89631139': [('CT13-EN008', 'Ultra Rare', 74.49)],
        },
      );

      await repositoryWith(client).collectionValue();

      expect((await printingPriceDao.get(ct13))!.price, 74.49);
    });

    // **The reason a null-price row is written at all.** Without it the
    // freshness check could never be satisfied for a printing the API has no
    // figure for, and its card would be re-fetched on every single valuation,
    // forever. Verified to fail if `_matchSetPrices` skips unmatched printings.
    test('a second run makes no request even for figureless printings', () async {
      final sdk = await printing(
        '89631139',
        setCode: 'SDK-001',
        rarity: 'Ultra Rare',
      );
      await own('89631139', 1, printingId: sdk);
      final client = _FakeClient(
        {'89631139': (0.02, 0.15)},
        sets: {
          '89631139': [('SDK-001', 'Ultra Rare', null)],
        },
      );
      final repository = repositoryWith(client);

      await repository.collectionValue();
      expect(client.requestCount, 1);

      await repository.collectionValue();
      expect(client.requestCount, 1, reason: 'nothing left to ask about');
    });

    // A card-level row can be fresh while one of its printings has never been
    // priced — both halves arrive together, so a miss on either is a miss.
    test('a card is re-fetched when a printing has no cached row', () async {
      final ct13 = await printing(
        '89631139',
        setCode: 'CT13-EN008',
        rarity: 'Ultra Rare',
      );
      await own('89631139', 1, printingId: ct13);
      await priceDao.upsertAll([
        CardPrices(
          passcode: '89631139',
          cardmarket: 0.02,
          tcgplayer: 0.15,
          updatedAt: DateTime.now(),
        ),
      ]);
      final client = _FakeClient(
        {'89631139': (0.02, 0.15)},
        sets: {
          '89631139': [('CT13-EN008', 'Ultra Rare', 74.49)],
        },
      );

      final value = await repositoryWith(client).collectionValue();

      expect(client.requestCount, 1);
      expect(value.lines.single.tcgplayerUsd, 74.49);
    });

    // The stamp beside the totals has to describe all of them, and a line can
    // now draw its dollars from one table and its euros from the other.
    test('asOf spans both price tables', () async {
      final old = _millisecondPrecision(
        DateTime.now().subtract(const Duration(hours: 12)),
      );
      final ct13 = await printing(
        '89631139',
        setCode: 'CT13-EN008',
        rarity: 'Ultra Rare',
      );
      await own('89631139', 1, printingId: ct13);
      await priceDao.upsertAll([
        CardPrices(
          passcode: '89631139',
          cardmarket: 0.02,
          tcgplayer: 0.15,
          updatedAt: DateTime.now(),
        ),
      ]);
      await printingPriceDao.upsertAll([
        PrintingPrice(printingId: ct13, price: 74.49, updatedAt: old),
      ]);

      final value = await repositoryWith(_FakeClient(const {}))
          .collectionValue();

      expect(value.asOf, old, reason: 'the older of the two figures used');
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
        printingPriceDao: printingPriceDao,
        collectionDao: collectionDao,
        printingDao: printingDao,
        cardDao: cardDao,
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
