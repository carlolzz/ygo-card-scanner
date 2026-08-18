import 'package:freezed_annotation/freezed_annotation.dart';

part 'card_prices.freezed.dart';

/// One card's **card-level** market prices, from YGOPRODeck's `card_prices`.
///
/// Maps to the `card_prices` table (schema v4). Both figures are documented by
/// the API as "the lowest price found across multiple versions of that card",
/// and that is not a figure of speech: `cardmarket_price` is €0.02 for
/// Blue-Eyes White Dragon, Dark Magician and Mirror Force alike. So this is a
/// **floor for the card**, not a valuation of the printing in hand.
///
/// [PrintingPrice] is the real per-printing figure and is what the collection
/// valuation uses wherever a set is recorded; this row is the fallback for
/// copies logged without one, and the only source there is for euros.
///
/// **[cardmarket] is EUR, [tcgplayer] is USD.** They are deliberately not
/// reconciled anywhere: the collection total is reported as two separate
/// figures rather than one mixed sum, because this app carries no exchange rate
/// and inventing one would silently turn an estimate into a wrong number.
///
/// eBay, Amazon and CoolStuffInc were carried here until step 26. They were
/// displayed on a card's Prices tab and fed nothing else, so they went with the
/// v4 migration rather than linger as columns nothing reads.
@freezed
abstract class CardPrices with _$CardPrices {
  const CardPrices._();

  const factory CardPrices({
    required String passcode,

    /// Cardmarket, in **euros**.
    double? cardmarket,

    /// TCGplayer, in US dollars.
    double? tcgplayer,

    /// When this row was fetched. Drives the TTL in `PriceRepository` and the
    /// "prices as of …" stamp the UI shows, so a cached figure is never
    /// presented as if it were live.
    required DateTime updatedAt,
  }) = _CardPrices;

  factory CardPrices.fromMap(Map<String, Object?> map) => CardPrices(
    passcode: map['passcode'] as String,
    cardmarket: (map['cardmarket'] as num?)?.toDouble(),
    tcgplayer: (map['tcgplayer'] as num?)?.toDouble(),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
  );

  Map<String, Object?> toMap() => {
    'passcode': passcode,
    'cardmarket': cardmarket,
    'tcgplayer': tcgplayer,
    'updated_at': updatedAt.millisecondsSinceEpoch,
  };
}

/// One printing's price, cached in the `printing_prices` table (schema v4).
///
/// The persisted form of a [SetPrice], keyed on `printings.id` once the
/// API's set code and rarity have been matched back to a row this app stores.
///
/// **A null [price] is a real answer, not a missing one.** `parsePrice` folds
/// the API's very common `"0.00"` into null, so most printings have no figure;
/// the row records that we asked and when, which is what stops its card being
/// re-fetched on every valuation forever. A printing with no row at all has
/// never been asked about.
@freezed
abstract class PrintingPrice with _$PrintingPrice {
  const PrintingPrice._();

  const factory PrintingPrice({
    required int printingId,

    /// US dollars, or null when the API had no usable figure for this printing.
    double? price,

    required DateTime updatedAt,
  }) = _PrintingPrice;

  factory PrintingPrice.fromMap(Map<String, Object?> map) => PrintingPrice(
    printingId: map['printing_id'] as int,
    price: (map['price'] as num?)?.toDouble(),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
  );

  Map<String, Object?> toMap() => {
    'printing_id': printingId,
    'price': price,
    'updated_at': updatedAt.millisecondsSinceEpoch,
  };
}

/// What one set/rarity printing of a card sells for, from `card_sets[].set_price`.
///
/// **The figure the collection valuation is actually built on** since step 26.
/// It is per set *and* rarity, so it reflects the card in hand in a way the
/// card-level [CardPrices] floor cannot: a CT13-EN008 Blue-Eyes is $74.49 here
/// and $0.15 there.
///
/// The API's wire form. It is matched back to a `printings.id` on the exact
/// `(passcode, set_code, rarity)` triple — the `printings` UNIQUE key — and
/// persisted as a [PrintingPrice]. Both sides come from the same fields of the
/// same endpoint, so that match is an identity rather than a heuristic.
///
/// [price] is USD, and it is the *only* currency available per printing —
/// YGOPRODeck reports Cardmarket at the card level and nowhere else, which is
/// why the collection's euro total remains a floor.
class SetPrice {
  const SetPrice({
    this.setCode,
    this.setName,
    this.rarity,
    this.price,
  });

  final String? setCode;
  final String? setName;
  final String? rarity;

  /// US dollars, or null when the API carried no usable figure. A great many
  /// sets report `"0.00"`, which means "unknown" rather than "free" — see
  /// `parsePrice`, which folds both into null.
  final double? price;

  /// "SET-CODE · Set Name", matching `Printing.setLabel` so the same printing
  /// reads identically on the Prices tab and on the collection detail screen.
  String get setLabel => [setCode, setName].whereType<String>().join(' · ');
}

/// Everything the API knows about one card's pricing: the card-level row that
/// gets cached, plus the per-set figures that do not.
class CardPricing {
  const CardPricing({required this.card, required this.sets});

  final CardPrices card;
  final List<SetPrice> sets;
}
