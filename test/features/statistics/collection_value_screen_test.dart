import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/core/constants.dart';
import 'package:ygo_scanner/core/money.dart';
import 'package:ygo_scanner/data/repositories/price_repository.dart';
import 'package:ygo_scanner/features/statistics/collection_value_screen.dart';

CollectionValueLine _line({
  String passcode = '89631139',
  String name = 'Blue-Eyes White Dragon',
  int? printingId,
  String? setCode,
  String? setName,
  String? rarity,
  int quantity = 1,
  double? cardmarketEur,
  double? tcgplayerUsd,
  PriceBasis usdBasis = PriceBasis.none,
}) => CollectionValueLine(
  passcode: passcode,
  name: name,
  printingId: printingId,
  setCode: setCode,
  setName: setName,
  rarity: rarity,
  quantity: quantity,
  cardmarketEur: cardmarketEur,
  tcgplayerUsd: tcgplayerUsd,
  usdBasis: usdBasis,
  pricedAt: DateTime.utc(2026, 8, 17, 9),
);

CollectionValue _value(
  List<CollectionValueLine> lines, {
  double cardmarketEur = 0,
  double tcgplayerUsd = 0,
  int pricedCards = 0,
  int unpricedCards = 0,
}) => CollectionValue(
  cardmarketEur: cardmarketEur,
  tcgplayerUsd: tcgplayerUsd,
  pricedCards: pricedCards,
  unpricedCards: unpricedCards,
  asOf: DateTime.utc(2026, 8, 17, 9),
  lines: lines,
);

void main() {
  /// No `ProviderScope`, no `runAsync`, no database — the screen is a pure
  /// function of the value handed to it, which is the whole reason it takes one
  /// through `extra` rather than watching a provider.
  Future<void> pumpBreakdown(WidgetTester tester, CollectionValue value) async {
    await tester.pumpWidget(
      MaterialApp(home: CollectionValueScreen(value: value)),
    );
    await tester.pump();
  }

  testWidgets('renders one row per line', (tester) async {
    await pumpBreakdown(
      tester,
      _value([
        _line(
          setCode: 'CT13-EN008',
          setName: '2016 Mega-Tins',
          rarity: 'Ultra Rare',
          quantity: 2,
          tcgplayerUsd: 74.49,
          usdBasis: PriceBasis.printing,
        ),
        _line(
          passcode: '46986414',
          name: 'Dark Magician',
          tcgplayerUsd: 0.30,
          usdBasis: PriceBasis.cardFloor,
        ),
      ]),
    );

    expect(find.text('Blue-Eyes White Dragon'), findsOneWidget);
    expect(find.text('Dark Magician'), findsOneWidget);
    expect(find.text('CT13-EN008 · 2016 Mega-Tins'), findsOneWidget);
    expect(find.text('Ultra Rare'), findsOneWidget);
    expect(find.text('×2'), findsOneWidget);
    // The *line* total, not the unit price: two copies at $74.49.
    expect(find.text(r'$148.98'), findsOneWidget);
  });

  // The distinction the whole valuation rests on, and the one thing the numbers
  // alone cannot convey — a $0.30 figure looks the same whether it is a real
  // per-printing price or the floor standing in for one.
  group('the card-floor tag', () {
    testWidgets('marks a row that fell back', (tester) async {
      await pumpBreakdown(
        tester,
        _value([_line(tcgplayerUsd: 0.15, usdBasis: PriceBasis.cardFloor)]),
      );

      expect(
        find.text(AppStrings.valueBreakdownCardFloorTag),
        findsOneWidget,
      );
    });

    testWidgets('is absent when the printing priced itself', (tester) async {
      await pumpBreakdown(
        tester,
        _value([
          _line(
            setCode: 'CT13-EN008',
            tcgplayerUsd: 74.49,
            usdBasis: PriceBasis.printing,
          ),
        ]),
      );

      expect(find.text(AppStrings.valueBreakdownCardFloorTag), findsNothing);
    });
  });

  // Copies logged without a set say so: it is the reason they fell back, and a
  // blank line would read as missing data rather than as a choice never made.
  testWidgets('a line with no printing says so', (tester) async {
    await pumpBreakdown(
      tester,
      _value([_line(tcgplayerUsd: 0.15, usdBasis: PriceBasis.cardFloor)]),
    );

    expect(find.text(AppStrings.valueBreakdownNoSet), findsOneWidget);
  });

  // A card nobody quoted is not a worthless card, and a zero would say it was.
  testWidgets('an unpriced line shows a dash, never a zero', (tester) async {
    await pumpBreakdown(tester, _value([_line(quantity: 3)]));

    expect(find.text(kNoPrice), findsWidgets);
    expect(find.text(r'$0.00'), findsNothing);
    expect(find.text('€0.00'), findsNothing);
  });

  testWidgets('the header carries the totals it was given', (tester) async {
    await pumpBreakdown(
      tester,
      _value(
        [_line(tcgplayerUsd: 1, usdBasis: PriceBasis.printing)],
        cardmarketEur: 12.34,
        tcgplayerUsd: 567.89,
        pricedCards: 1,
        unpricedCards: 2,
      ),
    );

    expect(find.text('€12.34'), findsOneWidget);
    expect(find.text(r'$567.89'), findsOneWidget);
    expect(find.text(AppStrings.statisticsValueUnpriced(2)), findsOneWidget);
    expect(
      find.text(AppStrings.statisticsValuePrintingPriced(1, 1)),
      findsOneWidget,
    );
  });

  group('sorting', () {
    final cheap = _line(
      name: 'Aaa Cheap Card',
      quantity: 1,
      tcgplayerUsd: 1,
      usdBasis: PriceBasis.printing,
    );
    final dear = _line(
      name: 'Zzz Dear Card',
      quantity: 2,
      tcgplayerUsd: 50,
      usdBasis: PriceBasis.printing,
    );
    final unpriced = _line(name: 'Mmm Unpriced Card');

    // Ranked on the line *total*, not the unit price: the question this screen
    // answers is where the collection's value sits, and four copies of a $10
    // card outrank one copy of a $30 one.
    test('by value ranks on the line total, unpriced last', () {
      final sorted = sortValueLines(
        [cheap, unpriced, dear],
        ValueSortMode.byValue,
      );

      expect(sorted.map((l) => l.name), [
        'Zzz Dear Card',
        'Aaa Cheap Card',
        'Mmm Unpriced Card',
      ]);
    });

    // The repository already sorted by name for the export's sake, so this mode
    // is the identity — and must not disturb the order it was handed.
    test('by name keeps the order it was given', () {
      final given = [cheap, unpriced, dear];
      expect(
        sortValueLines(given, ValueSortMode.byName).map((l) => l.name),
        given.map((l) => l.name),
      );
    });

    test('never mutates the caller\'s list', () {
      final given = [cheap, unpriced, dear];
      sortValueLines(given, ValueSortMode.byValue);
      expect(given.map((l) => l.name), [
        'Aaa Cheap Card',
        'Mmm Unpriced Card',
        'Zzz Dear Card',
      ]);
    });
  });
}
