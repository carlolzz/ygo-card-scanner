import 'package:dio/dio.dart';

import '../../models/card_prices.dart';
import '../../models/printing.dart';
import '../../models/ygo_card.dart';

/// A card plus all of its printings, as parsed from a single YGOPRODeck
/// `cardinfo.php` entry.
class YgoProdeckCard {
  const YgoProdeckCard({required this.card, required this.printings});

  final YgoCard card;
  final List<Printing> printings;
}

/// Thin wrapper over the YGOPRODeck REST API. Card JSON parsing (as opposed
/// to the SQLite mapping on [YgoCard]/[Printing]) lives here, since the two
/// shapes differ.
class YgoProdeckClient {
  YgoProdeckClient({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://db.ygoprodeck.com/api/v7',
              // Dio's receiveTimeout is the gap *between* two received chunks,
              // not the total duration, so this is safe for [fetchAllCards]'s
              // ~15 MB download while still bounding a connection that stalls.
              // Without them a dead network leaves the first-launch gate — and
              // the price fetch — on a spinner that never ends.
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
            ),
          );

  final Dio _dio;

  /// Fetches the full card database in one request (~13k entries) and
  /// flattens each entry's nested `card_sets` into printing rows.
  ///
  /// Fetch once, not per-card — the API is rate-limited to roughly 20
  /// requests/second.
  Future<List<YgoProdeckCard>> fetchAllCards({
    void Function(int received, int total)? onReceiveProgress,
  }) async {
    final response = await _dio.get<Map<String, Object?>>(
      '/cardinfo.php',
      onReceiveProgress: onReceiveProgress,
    );
    final data = response.data?['data'] as List<Object?>? ?? const [];
    return data
        .map((entry) => _parseEntry(entry! as Map<String, Object?>))
        .toList();
  }

  /// Market prices for up to a few dozen cards in one request.
  ///
  /// `cardinfo.php?id=` takes comma-separated passcodes; chunking is the
  /// caller's job (see `PriceRepository`, which uses [kPriceChunkSize]) so the
  /// rate limit is reasoned about in one place.
  ///
  /// Returns **only the cards the API recognised**, and an empty list rather
  /// than throwing when it recognises none: `?id=` with no match answers HTTP
  /// 400 (`{"error": "No card matching your query"}`), which is a normal
  /// outcome for alt-art passcodes and for a database the sync has since moved
  /// past — not a failure worth aborting a whole collection's valuation over.
  /// Any other Dio failure (offline, timeout, 5xx) still propagates, because
  /// that one the user needs to be told about.
  Future<List<CardPricing>> fetchPrices(List<String> passcodes) async {
    if (passcodes.isEmpty) return const [];
    final Response<Map<String, Object?>> response;
    try {
      response = await _dio.get<Map<String, Object?>>(
        '/cardinfo.php',
        queryParameters: {'id': passcodes.join(',')},
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 400) return const [];
      rethrow;
    }
    final data = response.data?['data'] as List<Object?>? ?? const [];
    return [
      for (final entry in data)
        if (entry is Map<String, Object?>) parsePricingEntry(entry),
    ];
  }

  YgoProdeckCard _parseEntry(Map<String, Object?> json) {
    final passcode = json['id'].toString();

    final card = YgoCard(
      passcode: passcode,
      name: json['name']! as String,
      type: json['type'] as String?,
      frameType: json['frameType'] as String?,
      attribute: json['attribute'] as String?,
      race: json['race'] as String?,
      atk: (json['atk'] as num?)?.toInt(),
      def: (json['def'] as num?)?.toInt(),
      level: (json['level'] as num?)?.toInt(),
      description: json['desc'] as String?,
      imageUrl: _firstImageUrl(json['card_images']),
      archetype: json['archetype'] as String?,
    );

    final sets = json['card_sets'] as List<Object?>? ?? const [];
    final printings = sets
        .map((s) => s! as Map<String, Object?>)
        .map(
          (s) => Printing(
            passcode: passcode,
            setCode: s['set_code'] as String?,
            setName: s['set_name'] as String?,
            rarity: s['set_rarity'] as String?,
          ),
        )
        .toList();

    return YgoProdeckCard(card: card, printings: printings);
  }

  /// The first artwork's URL, preferring the smaller full-card variant
  /// (`image_url_small`) to save on-device storage, and falling back to the
  /// full-resolution `image_url` when a card has no small variant. Both are the
  /// whole card (unlike `image_url_cropped`, which is the art box only).
  String? _firstImageUrl(Object? images) {
    if (images is! List || images.isEmpty) return null;
    final first = images.first;
    if (first is! Map<String, Object?>) return null;
    return (first['image_url_small'] ?? first['image_url']) as String?;
  }
}

/// How many passcodes go into one `cardinfo.php?id=` request.
///
/// The API allows 20 requests/second, so even a 900-distinct-card collection is
/// 18 sequential requests here — well inside the limit without any throttling.
/// Kept modest so one failed chunk costs little and the URL stays short.
const int kPriceChunkSize = 50;

/// Pulls the pricing out of one `cardinfo.php` entry.
///
/// A top-level function rather than a method so it is host-testable against a
/// literal response map, with no network and no mock adapter — the same reason
/// `card_quad.dart` and `frame_quality.dart` keep their decisions out of the
/// classes that cannot be tested. A silently wrong parse here does not crash:
/// it reports a plausible, wrong valuation.
///
/// **The `sets:` half is the valuable one.** `card_prices` is documented as the
/// lowest figure across every version of a card and is €0.02 for most of them;
/// `card_sets[].set_price` is per set and rarity and is what the collection
/// valuation prices a copy at. Both arrive in the same response, so reading the
/// per-set figures costs nothing extra. `ebay_price`, `amazon_price` and
/// `coolstuffinc_price` are deliberately not read — see [CardPrices].
CardPricing parsePricingEntry(
  Map<String, Object?> json, {
  DateTime? fetchedAt,
}) {
  final passcode = json['id'].toString();
  // `card_prices` is an array by shape but carries a single element in
  // practice; missing it entirely leaves every figure null, which reads as
  // "unpriced" rather than as zero.
  final prices = json['card_prices'] as List<Object?>? ?? const [];
  final first = prices.isEmpty ? null : prices.first;
  final p = first is Map<String, Object?> ? first : const <String, Object?>{};

  final sets = json['card_sets'] as List<Object?>? ?? const [];

  return CardPricing(
    card: CardPrices(
      passcode: passcode,
      cardmarket: parsePrice(p['cardmarket_price']),
      tcgplayer: parsePrice(p['tcgplayer_price']),
      updatedAt: fetchedAt ?? DateTime.now(),
    ),
    sets: [
      for (final s in sets)
        if (s is Map<String, Object?>)
          SetPrice(
            setCode: s['set_code'] as String?,
            setName: s['set_name'] as String?,
            rarity: s['set_rarity'] as String?,
            price: parsePrice(s['set_price']),
          ),
    ],
  );
}

/// One price field, from the **string** the API actually sends (`"0.29"`).
///
/// Null for anything unusable *and for zero*: a great many sets report
/// `"0.00"`, which means YGOPRODeck has no figure rather than that the card is
/// free. Folding both into null is what lets every display site and the
/// collection total share one rule — show a dash, and count the card as
/// unpriced — instead of each deciding separately whether 0 is a price.
double? parsePrice(Object? value) {
  if (value == null) return null;
  final parsed = value is num ? value.toDouble() : double.tryParse('$value');
  if (parsed == null || parsed <= 0 || !parsed.isFinite) return null;
  return parsed;
}
