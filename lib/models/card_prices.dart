import 'package:freezed_annotation/freezed_annotation.dart';

part 'card_prices.freezed.dart';

/// One card's market prices, as YGOPRODeck reports them in `card_prices`.
///
/// Maps to the `card_prices` table (schema v3). Every figure is documented by
/// the API as "the lowest price found across multiple versions of that card",
/// so this is a floor for the *card*, not a valuation of a particular printing
/// in a particular grade — [SetPrice] is the only per-printing figure the API
/// offers, and it exists in one currency only.
///
/// **[cardmarket] is EUR; every other field is USD.** They are deliberately not
/// reconciled anywhere: the collection total is reported as two separate
/// figures rather than one mixed sum, because this app carries no exchange rate
/// and inventing one would silently turn an estimate into a wrong number.
@freezed
abstract class CardPrices with _$CardPrices {
  const CardPrices._();

  const factory CardPrices({
    required String passcode,

    /// Cardmarket, in **euros**.
    double? cardmarket,

    /// TCGplayer, in US dollars.
    double? tcgplayer,
    double? ebay,
    double? amazon,
    double? coolstuffinc,

    /// When this row was fetched. Drives the TTL in `PriceRepository` and the
    /// "prices as of …" stamp the UI shows, so a cached figure is never
    /// presented as if it were live.
    required DateTime updatedAt,
  }) = _CardPrices;

  factory CardPrices.fromMap(Map<String, Object?> map) => CardPrices(
    passcode: map['passcode'] as String,
    cardmarket: (map['cardmarket'] as num?)?.toDouble(),
    tcgplayer: (map['tcgplayer'] as num?)?.toDouble(),
    ebay: (map['ebay'] as num?)?.toDouble(),
    amazon: (map['amazon'] as num?)?.toDouble(),
    coolstuffinc: (map['coolstuffinc'] as num?)?.toDouble(),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
  );

  Map<String, Object?> toMap() => {
    'passcode': passcode,
    'cardmarket': cardmarket,
    'tcgplayer': tcgplayer,
    'ebay': ebay,
    'amazon': amazon,
    'coolstuffinc': coolstuffinc,
    'updated_at': updatedAt.millisecondsSinceEpoch,
  };
}

/// What one set/rarity printing of a card sells for, from `card_sets[].set_price`.
///
/// **Never persisted** — it lives with the model rather than in a DAO because
/// there is no table behind it. The `printings` rows the sync already stores
/// carry the same set code, name and rarity; only the price is transient, and
/// it is read live whenever a card's Prices tab is opened.
///
/// [price] is USD, and it is the *only* currency available per printing —
/// YGOPRODeck reports Cardmarket at the card level and nowhere else.
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
