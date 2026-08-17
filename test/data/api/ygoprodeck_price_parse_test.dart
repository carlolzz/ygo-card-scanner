import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/data/api/ygoprodeck_client.dart';

/// The pricing half of a `cardinfo.php` entry, parsed offline.
///
/// Pure functions rather than a mocked Dio because a wrong parse here does not
/// crash — it reports a plausible, wrong valuation. Same reasoning as
/// `card_quad.dart` and `frame_quality.dart`.
void main() {
  final fetchedAt = DateTime.fromMillisecondsSinceEpoch(1700000000000);

  group('parsePrice', () {
    // The API sends every figure as a *string*, which is the whole reason this
    // function exists rather than a cast.
    test('reads the string the API actually sends', () {
      expect(parsePrice('0.29'), 0.29);
      expect(parsePrice('123.45'), 123.45);
    });

    test('accepts a number too, in case the API ever sends one', () {
      expect(parsePrice(1.5), 1.5);
      expect(parsePrice(2), 2.0);
    });

    // A great many sets report "0.00", which means YGOPRODeck has no figure
    // rather than that the card is free. Folding it into null here is what lets
    // every display site and the collection total share one rule.
    test('zero means unknown, not free', () {
      expect(parsePrice('0.00'), isNull);
      expect(parsePrice('0'), isNull);
      expect(parsePrice(0), isNull);
      expect(parsePrice('-1.00'), isNull);
    });

    test('anything unreadable is unknown', () {
      expect(parsePrice(null), isNull);
      expect(parsePrice(''), isNull);
      expect(parsePrice('n/a'), isNull);
      expect(parsePrice(double.nan), isNull);
      expect(parsePrice(double.infinity), isNull);
    });
  });

  group('parsePricingEntry', () {
    test('reads every vendor and every set', () {
      final pricing = parsePricingEntry({
        'id': 89631139,
        'name': 'Blue-Eyes White Dragon',
        'card_prices': [
          {
            'cardmarket_price': '0.29',
            'tcgplayer_price': '1.15',
            'ebay_price': '2.99',
            'amazon_price': '3.49',
            'coolstuffinc_price': '0.99',
          },
        ],
        'card_sets': [
          {
            'set_name': 'Legend of Blue Eyes White Dragon',
            'set_code': 'LOB-001',
            'set_rarity': 'Ultra Rare',
            'set_price': '236.85',
          },
          {
            'set_name': 'Starter Deck: Kaiba',
            'set_code': 'SDK-001',
            'set_rarity': 'Ultra Rare',
            'set_price': '0.00',
          },
        ],
      }, fetchedAt: fetchedAt);

      expect(pricing.card.passcode, '89631139');
      expect(pricing.card.cardmarket, 0.29);
      expect(pricing.card.tcgplayer, 1.15);
      expect(pricing.card.ebay, 2.99);
      expect(pricing.card.amazon, 3.49);
      expect(pricing.card.coolstuffinc, 0.99);
      expect(pricing.card.updatedAt, fetchedAt);

      expect(pricing.sets, hasLength(2));
      expect(pricing.sets.first.setLabel, 'LOB-001 · Legend of Blue Eyes White Dragon');
      expect(pricing.sets.first.rarity, 'Ultra Rare');
      expect(pricing.sets.first.price, 236.85);
      // The set exists and is worth showing; only its price is unknown.
      expect(pricing.sets.last.setCode, 'SDK-001');
      expect(pricing.sets.last.price, isNull);
    });

    // The passcode is the key everything else joins on, and the API sends it as
    // a number while `cards.passcode` is TEXT.
    test('the id becomes a string passcode', () {
      final pricing = parsePricingEntry({'id': 44095762}, fetchedAt: fetchedAt);
      expect(pricing.card.passcode, '44095762');
    });

    // A card with no market data at all reads as unpriced, not as worth zero —
    // which is what keeps it out of the collection total *and* counted in the
    // "N cards have no price" line beside it.
    test('a card with no prices is unpriced, not free', () {
      final pricing = parsePricingEntry({
        'id': 44095762,
        'card_sets': <Object?>[],
      }, fetchedAt: fetchedAt);

      expect(pricing.card.cardmarket, isNull);
      expect(pricing.card.tcgplayer, isNull);
      expect(pricing.sets, isEmpty);
    });

    test('a malformed card_prices array does not throw', () {
      expect(
        parsePricingEntry({
          'id': 1,
          'card_prices': ['not a map'],
        }, fetchedAt: fetchedAt).card.cardmarket,
        isNull,
      );
      expect(
        parsePricingEntry({
          'id': 1,
          'card_sets': [42],
        }, fetchedAt: fetchedAt).sets,
        isEmpty,
      );
    });
  });
}
