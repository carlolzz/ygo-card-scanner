import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/core/constants.dart';
import 'package:ygo_scanner/core/money.dart';
import 'package:ygo_scanner/features/card_search/card_detail_screen.dart';
import 'package:ygo_scanner/features/pricing/card_prices_view.dart';
import 'package:ygo_scanner/features/pricing/price_providers.dart';
import 'package:ygo_scanner/models/card_prices.dart';
import 'package:ygo_scanner/models/ygo_card.dart';

const _card = YgoCard(
  passcode: '89631139',
  name: 'Blue-Eyes White Dragon',
  type: 'Normal Monster',
  race: 'Dragon',
  attribute: 'LIGHT',
  level: 8,
  atk: 3000,
  def: 2500,
  description: 'This legendary dragon is a powerful engine of destruction.',
  localImagePath: 'no-such-file.jpg',
);

final _pricing = CardPricing(
  card: CardPrices(
    passcode: _card.passcode,
    cardmarket: 0.29,
    tcgplayer: 1.15,
    ebay: 2.99,
    updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
  ),
  sets: const [
    SetPrice(
      setCode: 'LOB-001',
      setName: 'Legend of Blue Eyes White Dragon',
      rarity: 'Ultra Rare',
      price: 236.85,
    ),
    // A set the API carries no figure for — very common, and it must still be
    // listed. The set existing is information; only its price is missing.
    SetPrice(setCode: 'SDK-001', setName: 'Starter Deck: Kaiba', rarity: 'Ultra Rare'),
  ],
);

void main() {
  /// Pumps the view with the pricing provider resolved to [pricing] — or
  /// throwing, for the offline case. Passing the value rather than an override
  /// keeps every test off the network without naming Riverpod's `Override`
  /// type, which `flutter_riverpod` does not re-export.
  Future<void> pumpPrices(
    WidgetTester tester, {
    CardPricing? pricing,
    bool fails = false,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cardPricingProvider(_card.passcode).overrideWith((ref) async {
            if (fails) throw Exception('offline');
            return pricing;
          }),
        ],
        child: MaterialApp(
          home: Scaffold(body: CardPricesView(passcode: _card.passcode)),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows every vendor, each in its own currency', (tester) async {
    await pumpPrices(tester, pricing: _pricing);

    expect(find.text(AppStrings.pricesCardmarket), findsOneWidget);
    expect(find.text('€0.29'), findsOneWidget);
    expect(find.text(r'$1.15'), findsOneWidget);
    expect(find.text(r'$2.99'), findsOneWidget);
    // Amazon and CoolStuffInc carried nothing — a dash, never a zero.
    expect(find.text(kNoPrice), findsWidgets);
  });

  testWidgets('lists every printing, priced or not', (tester) async {
    await pumpPrices(tester, pricing: _pricing);

    expect(
      find.text('LOB-001 · Legend of Blue Eyes White Dragon'),
      findsOneWidget,
    );
    expect(find.text(r'$236.85'), findsOneWidget);
    expect(find.text('SDK-001 · Starter Deck: Kaiba'), findsOneWidget);
  });

  // The two halves are different measurements — card-level "lowest across
  // versions" against a per-printing figure that exists in dollars only — and
  // saying so is what stops the table implying a Cardmarket price per set.
  testWidgets('both halves say what they are', (tester) async {
    await pumpPrices(tester, pricing: _pricing);

    expect(find.text(AppStrings.pricesCardLevelNote), findsOneWidget);
    expect(find.text(AppStrings.pricesBySetNote), findsOneWidget);
  });

  // Not an error: it is a fact about the card, so it must not offer a Retry
  // that cannot possibly help.
  testWidgets('a card the API does not know says so, without a retry', (
    tester,
  ) async {
    await pumpPrices(tester);

    expect(find.text(AppStrings.pricesUnknownCard), findsOneWidget);
    expect(find.text(AppStrings.pricesRetryButton), findsNothing);
  });

  // This case only reaches the error branch because both pricing providers set
  // `retry: _noRetry`. Riverpod 3 retries a failed provider by default and
  // holds it in `AsyncLoading` *carrying* the error while it waits, so
  // `.when(error:)` never fires and an offline device sits on a spinner. If
  // this test starts finding a `CircularProgressIndicator`, that annotation has
  // been dropped.
  testWidgets('offline shows the message and a working retry', (tester) async {
    await pumpPrices(tester, fails: true);

    expect(find.text(AppStrings.pricesErrorMessage), findsOneWidget);
    expect(find.text(AppStrings.pricesRetryButton), findsOneWidget);
    // The exception itself is never shown — it tells the user nothing they can
    // act on.
    expect(find.textContaining('Exception'), findsNothing);
  });

  group('the card detail screen', () {
    Future<void> pumpDetail(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cardPricingProvider(
              _card.passcode,
            ).overrideWith((ref) async => _pricing),
            cardPriceProvider(
              _card.passcode,
            ).overrideWith((ref) async => _pricing.card),
          ],
          child: const MaterialApp(home: CardDetailScreen(card: _card)),
        ),
      );
      await tester.pump();
    }

    // The Details tab is answered entirely from the local database; only Prices
    // needs the network. Splitting them is what keeps a card's effect text
    // readable offline.
    testWidgets('opens on the details tab', (tester) async {
      await pumpDetail(tester);

      expect(find.text(AppStrings.collectionCardAttributeLabel), findsOneWidget);
      expect(find.text('Dragon'), findsOneWidget);
      expect(find.text('3000 / 2500'), findsOneWidget);
      // Prices is a tab away, not on this one.
      expect(find.text(AppStrings.pricesMarketSection), findsNothing);
    });

    testWidgets('the prices tab shows the breakdown', (tester) async {
      await pumpDetail(tester);

      await tester.tap(find.text(AppStrings.cardTabPrices));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.pricesMarketSection), findsOneWidget);
      expect(find.text(r'$236.85'), findsOneWidget);
    });

    // The "button to see the pricing" the details page carries: it is a link
    // into the tab beside it rather than a second destination.
    testWidgets('the estimate row jumps to the prices tab', (tester) async {
      await pumpDetail(tester);

      expect(find.text(AppStrings.pricesSeeAll), findsOneWidget);
      await tester.tap(find.text(AppStrings.pricesSeeAll));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.pricesMarketSection), findsOneWidget);
    });

    // An estimate is a bonus. A card with no price at all must leave the
    // details tab looking finished, not broken.
    testWidgets('an unpriced card simply has no estimate row', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cardPricingProvider(
              _card.passcode,
            ).overrideWith((ref) async => null),
            cardPriceProvider(_card.passcode).overrideWith((ref) async => null),
          ],
          child: const MaterialApp(home: CardDetailScreen(card: _card)),
        ),
      );
      await tester.pump();

      expect(find.text(AppStrings.pricesSeeAll), findsNothing);
      expect(find.text('Dragon'), findsOneWidget);
    });
  });
}
