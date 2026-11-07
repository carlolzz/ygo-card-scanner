import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ygo_scanner/core/constants.dart';
import 'package:ygo_scanner/core/theme/tokens.dart';
import 'package:ygo_scanner/data/db/dao/card_dao.dart';
import 'package:ygo_scanner/data/db/dao/collection_dao.dart';
import 'package:ygo_scanner/data/db/dao/printing_dao.dart';
import 'package:ygo_scanner/data/db/database.dart';
import 'package:ygo_scanner/features/collection/collection_detail_screen.dart';
import 'package:ygo_scanner/features/collection/collection_providers.dart';
import 'package:ygo_scanner/features/pricing/price_providers.dart';
import 'package:ygo_scanner/models/card_condition.dart';
import 'package:ygo_scanner/models/card_edition.dart';
import 'package:ygo_scanner/models/card_language.dart';
import 'package:ygo_scanner/models/card_prices.dart';
import 'package:ygo_scanner/models/collection_entry.dart';
import 'package:ygo_scanner/models/printing.dart';
import 'package:ygo_scanner/models/ygo_card.dart';

import '../../data/db/test_db.dart';
import '../../support/widget_test_harness.dart';

const _mirrorForce = YgoCard(
  passcode: '44095762',
  name: 'Mirror Force',
  type: 'Trap Card',
  frameType: 'trap',
  race: 'Normal',
  description: 'When an opponent\'s monster declares an attack.',
);

OwnedCopy _copy(
  CardCondition condition, {
  String language = 'EN',
  String? setCode,
}) => OwnedCopy(
  entry: CollectionEntry(
    passcode: _mirrorForce.passcode,
    condition: condition,
    language: language,
    createdAt: 0,
    updatedAt: 0,
  ),
  printing: setCode == null
      ? null
      : Printing(passcode: _mirrorForce.passcode, setCode: setCode),
);

void main() {
  late Database testDb;
  late CollectionDao collectionDao;
  late int metalRaidersId;

  setUp(() async {
    testDb = await openInMemoryTestDb();
    collectionDao = CollectionDao(testDb);
    await CardDao(testDb).insertAll([_mirrorForce]);
    await PrintingDao(testDb).insertAll([
      Printing(
        passcode: _mirrorForce.passcode,
        setCode: 'MRD-EN094',
        setName: 'Metal Raiders',
        rarity: 'Super Rare',
      ),
    ]);
    metalRaidersId = (await PrintingDao(
      testDb,
    ).getForPasscode(_mirrorForce.passcode)).single.id!;
  });

  tearDown(() async {
    await testDb.close();
  });

  /// Two entries for one card: 2 copies from a known set, 3 logged with no set.
  Future<void> logTwoEntries() async {
    await collectionDao.addOrIncrement(
      CollectionEntry(
        passcode: _mirrorForce.passcode,
        printingId: metalRaidersId,
        condition: CardCondition.nearMint,
        edition: CardEdition.first,
        language: 'EN',
        quantity: 2,
        notes: 'From the binder',
        createdAt: 1,
        updatedAt: 1,
      ),
    );
    await collectionDao.addOrIncrement(
      CollectionEntry(
        passcode: _mirrorForce.passcode,
        condition: CardCondition.played,
        language: 'DE',
        quantity: 3,
        createdAt: 2,
        updatedAt: 2,
      ),
    );
  }

  /// Opens the detail screen on the entry with [printingId], stubbing the price
  /// so nothing reaches the network.
  Future<void> openDetail(WidgetTester tester, {int? printingId}) async {
    final entryWithCard = (await collectionDao.getAll()).firstWhere(
      (e) => e.entry.printingId == printingId,
    );
    final prices = CardPrices(
      passcode: _mirrorForce.passcode,
      cardmarket: 0.29,
      tcgplayer: 1.15,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((ref) async => testDb),
          cardPriceProvider(
            _mirrorForce.passcode,
          ).overrideWith((ref) async => prices),
          cardPricingProvider(_mirrorForce.passcode).overrideWith(
            (ref) async => CardPricing(card: prices, sets: const []),
          ),
        ],
        child: MaterialApp(
          home: CollectionDetailScreen(entryWithCard: entryWithCard),
        ),
      ),
    );
    await pumpUntilSettled(tester);
  }

  Future<void> openTab(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await pumpUntilSettled(tester);
  }

  /// Text inside the tab's list, since the Details tab beside it can carry the
  /// same labels while it animates out.
  Finder inBlock(String text) =>
      find.descendant(of: find.byType(ListView), matching: find.text(text));

  group('the Copies tab', () {
    testWidgets('sums every copy across entries, with the total first', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await logTwoEntries();
        await openDetail(tester, printingId: metalRaidersId);
        await openTab(tester, AppStrings.cardTabCopies);

        expect(find.text(AppStrings.collectionCopiesTotal(5)), findsOneWidget);
      });
    });

    testWidgets('each entry shows everything recorded about it', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.runAsync(() async {
        await logTwoEntries();
        await openDetail(tester, printingId: metalRaidersId);
        await openTab(tester, AppStrings.cardTabCopies);

        expect(inBlock(CardCondition.nearMint.label), findsOneWidget);
        expect(inBlock('MRD-EN094 · Metal Raiders'), findsOneWidget);
        expect(inBlock('Super Rare'), findsOneWidget);
        expect(inBlock(CardEdition.first.label), findsOneWidget);
        expect(inBlock('From the binder'), findsOneWidget);
        expect(inBlock(AppStrings.collectionCopiesNotesLabel), findsOneWidget);
        expect(
          inBlock(AppStrings.collectionCopiesAddedLabel),
          findsNWidgets(2),
        );
        expect(inBlock(CardCondition.played.label), findsOneWidget);
        // Twice each: the per-language breakdown, and the entry's own block.
        expect(inBlock('×2'), findsNWidgets(2));
        expect(inBlock('×3'), findsNWidgets(2));
        expect(inBlock(languageLabel('DE')), findsNWidgets(2));
      });
    });

    testWidgets('a copy logged without a set says so', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.runAsync(() async {
        await logTwoEntries();
        await openDetail(tester, printingId: metalRaidersId);
        await openTab(tester, AppStrings.cardTabCopies);

        expect(inBlock(AppStrings.collectionCopiesNoSet), findsOneWidget);
      });
    });

    // The app bar's edit and delete act on the one row the screen was opened on,
    // which is ambiguous with several rows on screen unless it is marked.
    testWidgets('only the entry the screen was opened on is marked', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.runAsync(() async {
        await logTwoEntries();
        await openDetail(tester, printingId: metalRaidersId);
        await openTab(tester, AppStrings.cardTabCopies);

        expect(inBlock(AppStrings.collectionCopiesThisEntry), findsOneWidget);
        // The marker sits on the Near Mint block, which sorts first.
        expect(
          tester.getTopLeft(inBlock(AppStrings.collectionCopiesThisEntry)).dy,
          lessThan(tester.getTopLeft(inBlock(CardCondition.played.label)).dy),
        );
      });
    });

    testWidgets('a quantity change on Details reaches the Copies tab', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await logTwoEntries();
        final entryWithCard = (await collectionDao.getAll()).firstWhere(
          (e) => e.entry.printingId == metalRaidersId,
        );
        final container = ProviderContainer(
          overrides: [appDatabaseProvider.overrideWith((ref) async => testDb)],
        );
        addTearDown(container.dispose);
        // Holds the provider alive, which is the case that goes stale: tap +
        // then swipe straight across, and the tab has already read the old count
        // when the write lands. Left to itself the provider is disposed whenever
        // the tab is off screen, and simply re-reads, which would hide this.
        final copies = container.listen(
          ownedCopiesProvider(_mirrorForce.passcode),
          (_, _) {},
        );
        addTearDown(copies.close);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: CollectionDetailScreen(entryWithCard: entryWithCard),
            ),
          ),
        );
        await pumpUntilSettled(tester);
        await openTab(tester, AppStrings.cardTabCopies);
        expect(find.text(AppStrings.collectionCopiesTotal(5)), findsOneWidget);

        await openTab(tester, AppStrings.cardTabDetails);
        final add = find.byIcon(Icons.add_circle_outline);
        await tester.ensureVisible(add);
        await pumpUntilSettled(tester);
        await tester.tap(add);
        await pumpUntilSettled(tester);

        await openTab(tester, AppStrings.cardTabCopies);
        expect(find.text(AppStrings.collectionCopiesTotal(6)), findsOneWidget);
      });
    });
  });

  group('sortOwnedCopies', () {
    test('orders by grade, then set with no set last, then language', () {
      final sorted = sortOwnedCopies([
        _copy(CardCondition.played, setCode: 'AAA-001'),
        _copy(CardCondition.nearMint),
        _copy(CardCondition.nearMint, setCode: 'ZZZ-001'),
        _copy(CardCondition.nearMint, setCode: 'AAA-001', language: 'IT'),
        _copy(CardCondition.nearMint, setCode: 'AAA-001', language: 'DE'),
      ]);

      expect(
        [
          for (final c in sorted)
            '${c.entry.condition.shortCode} ${c.printing?.setCode} '
                '${c.entry.language}',
        ],
        [
          'NM AAA-001 DE',
          'NM AAA-001 IT',
          'NM ZZZ-001 EN',
          'NM null EN',
          'PL AAA-001 EN',
        ],
      );
    });

    test('leaves the list it was given alone', () {
      final copies = [
        _copy(CardCondition.played),
        _copy(CardCondition.nearMint),
      ];
      sortOwnedCopies(copies);
      expect(copies.first.entry.condition, CardCondition.played);
    });
  });

  group('the Details tab', () {
    // The Copies tab sits between the two now, so the old index would land there
    // with no error at all. Nothing else on this screen covers the link.
    testWidgets('the price estimate still links to the Prices tab', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await logTwoEntries();
        await openDetail(tester, printingId: metalRaidersId);

        await tester.tap(find.text(AppStrings.pricesSeeAll));
        await pumpUntilSettled(tester);

        expect(find.text(AppStrings.pricesMarketSection), findsOneWidget);
        expect(find.text(AppStrings.collectionCopiesTotal(5)), findsNothing);
      });
    });

    testWidgets('leaves room between the card effect and the set', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await logTwoEntries();
        await openDetail(tester, printingId: metalRaidersId);

        final effectBottom = tester
            .getBottomLeft(find.text(_mirrorForce.description!))
            .dy;
        final setTop = tester
            .getTopLeft(find.text(AppStrings.collectionSetLabel))
            .dy;
        expect(setTop - effectBottom, greaterThanOrEqualTo(AppSpacing.md));
      });
    });
  });
}
