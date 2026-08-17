import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ygo_scanner/core/constants.dart';
import 'package:ygo_scanner/data/api/ygoprodeck_client.dart';
import 'package:ygo_scanner/data/db/dao/card_dao.dart';
import 'package:ygo_scanner/data/db/dao/card_price_dao.dart';
import 'package:ygo_scanner/data/db/dao/collection_dao.dart';
import 'package:ygo_scanner/data/db/database.dart';
import 'package:ygo_scanner/data/repositories/price_repository.dart';
import 'package:ygo_scanner/data/seed/fake_collection_seed.dart';
import 'package:ygo_scanner/features/statistics/statistics_screen.dart';
import 'package:ygo_scanner/models/card_prices.dart';

import '../../data/db/test_db.dart';
import '../../support/widget_test_harness.dart';

/// Prices every card asked for at a flat figure, so the totals are arithmetic
/// the test can state rather than fixture bookkeeping.
class _FlatClient extends YgoProdeckClient {
  _FlatClient({this.knows = true});

  /// €1 and $10 a copy, so a total is the copy count and ten times it — which
  /// also proves the two currencies are never folded together.
  static const cardmarket = 1.0;
  static const tcgplayer = 10.0;

  /// False models the API recognising nothing — every card unpriced.
  final bool knows;

  @override
  Future<List<CardPricing>> fetchPrices(List<String> passcodes) async => [
    if (knows)
      for (final passcode in passcodes)
        CardPricing(
          card: CardPrices(
            passcode: passcode,
            cardmarket: cardmarket,
            tcgplayer: tcgplayer,
            updatedAt: DateTime.now(),
          ),
          sets: const [],
        ),
  ];
}

class _OfflineClient extends YgoProdeckClient {
  @override
  Future<List<CardPricing>> fetchPrices(List<String> passcodes) async =>
      throw Exception('offline');
}

void main() {
  late Database testDb;

  setUp(() async {
    testDb = await openInMemoryTestDb();
    await seedFakeCollectionIfEmpty(testDb);
  });

  tearDown(() async {
    await testDb.close();
  });

  /// The screen is a lazy `ListView` and this section sits near its end, so at
  /// the default 600pt height it is never built and `ensureVisible` cannot find
  /// it — the same trap the export/import actions carry.
  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// [scopeKey] forces a genuinely new [ProviderScope] when a test opens the
  /// screen twice: without it Flutter reuses the element, the container
  /// survives, and `CollectionValueController` keeps the state the first run
  /// left it in — so the Calculate button would not be there to tap again.
  Future<void> openStatistics(
    WidgetTester tester, {
    required YgoProdeckClient client,
    String scopeKey = 'scope',
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        key: ValueKey(scopeKey),
        overrides: [
          appDatabaseProvider.overrideWith((ref) async => testDb),
          priceRepositoryProvider.overrideWith(
            (ref) async => PriceRepository(
              priceDao: CardPriceDao(testDb),
              collectionDao: CollectionDao(testDb),
              cardDao: CardDao(testDb),
              client: client,
            ),
          ),
        ],
        child: const MaterialApp(home: StatisticsScreen()),
      ),
    );
    await pumpUntilSettled(tester);
  }

  Future<void> tapCalculate(WidgetTester tester) async {
    final button = find.text(AppStrings.statisticsValueButton);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await pumpUntilSettled(tester);
  }

  // Never on open: valuing a collection is a burst of network requests, so the
  // section starts as a button and nothing has been fetched until it is tapped.
  testWidgets('starts as a button, having asked the API nothing', (
    tester,
  ) async {
    await tester.runAsync(() async {
      useTallViewport(tester);
      await openStatistics(tester, client: _FlatClient());

      expect(find.text(AppStrings.statisticsValueButton), findsOneWidget);
      expect(find.text(AppStrings.statisticsValueCardmarketLabel), findsNothing);
      expect(await CardPriceDao(testDb).get('89631139'), isNull);
    });
  });

  testWidgets('reports two totals, in two currencies, never one sum', (
    tester,
  ) async {
    await tester.runAsync(() async {
      useTallViewport(tester);
      await openStatistics(tester, client: _FlatClient());
      await tapCalculate(tester);

      final copies = await CollectionDao(testDb).totalCardCount();
      expect(find.text(AppStrings.statisticsValueCardmarketLabel), findsOneWidget);
      expect(find.text(AppStrings.statisticsValueTcgplayerLabel), findsOneWidget);
      expect(find.text('€${copies.toStringAsFixed(2)}'), findsOneWidget);
      expect(find.text('\$${(copies * 10).toStringAsFixed(2)}'), findsOneWidget);
    });
  });

  // The honesty line: a total assembled from part of a collection has to say
  // so, and it is hidden entirely when there is nothing to warn about.
  testWidgets('says how many cards had no price', (tester) async {
    await tester.runAsync(() async {
      useTallViewport(tester);
      await openStatistics(tester, client: _FlatClient(knows: false));
      await tapCalculate(tester);

      final distinct = await CollectionDao(testDb).distinctCardCount();
      expect(
        find.text(AppStrings.statisticsValueUnpriced(distinct)),
        findsOneWidget,
      );
    });
  });

  testWidgets('a fully priced collection carries no warning', (tester) async {
    await tester.runAsync(() async {
      useTallViewport(tester);
      await openStatistics(tester, client: _FlatClient());
      await tapCalculate(tester);

      expect(find.textContaining('no price'), findsNothing);
    });
  });

  // Non-blocking, unlike the first-launch sync gate: the user can retry or
  // simply walk away, and the rest of the statistics screen keeps working.
  testWidgets('offline reports a failure and offers a retry', (tester) async {
    await tester.runAsync(() async {
      useTallViewport(tester);
      await openStatistics(tester, client: _OfflineClient());
      await tapCalculate(tester);

      expect(find.text(AppStrings.statisticsValueErrorMessage), findsOneWidget);
      expect(find.text(AppStrings.pricesRetryButton), findsOneWidget);
      // The rest of the screen is untouched.
      expect(find.text(AppStrings.statisticsTotalCopiesLabel), findsOneWidget);
    });
  });

  // The TTL is what makes re-opening this screen free. A second calculate must
  // reuse the rows the first one wrote rather than re-requesting them.
  testWidgets('a second calculation reuses the cache', (tester) async {
    await tester.runAsync(() async {
      useTallViewport(tester);
      await openStatistics(tester, client: _FlatClient());
      await tapCalculate(tester);

      // Everything is cached now, so even a client that cannot answer produces
      // the same totals. A fresh scope, so this really is a second run rather
      // than the first one's state still on screen.
      await openStatistics(
        tester,
        client: _OfflineClient(),
        scopeKey: 'second',
      );
      await tapCalculate(tester);

      final copies = await CollectionDao(testDb).totalCardCount();
      expect(find.text('€${copies.toStringAsFixed(2)}'), findsOneWidget);
      expect(find.text(AppStrings.statisticsValueErrorMessage), findsNothing);
    });
  });

  // The breakdown export writes the figures already on screen, so it only
  // exists once there are some. Presence is all that is asserted: tapping it
  // reaches the real OS share sheet, which nothing here mocks.
  group('the value export button', () {
    testWidgets('is absent until a calculation succeeds', (tester) async {
      await tester.runAsync(() async {
        useTallViewport(tester);
        await openStatistics(tester, client: _FlatClient());

        expect(find.text(AppStrings.statisticsValueExportButton), findsNothing);
      });
    });

    testWidgets('appears beside the totals', (tester) async {
      await tester.runAsync(() async {
        useTallViewport(tester);
        await openStatistics(tester, client: _FlatClient());
        await tapCalculate(tester);

        expect(
          find.text(AppStrings.statisticsValueExportButton),
          findsOneWidget,
        );
      });
    });

    // A failed calculation has no figures to write, so the button must not be
    // offered there either — the error branch replaces the result entirely.
    testWidgets('is absent after a failure', (tester) async {
      await tester.runAsync(() async {
        useTallViewport(tester);
        await openStatistics(tester, client: _OfflineClient());
        await tapCalculate(tester);

        expect(find.text(AppStrings.statisticsValueExportButton), findsNothing);
      });
    });
  });
}
