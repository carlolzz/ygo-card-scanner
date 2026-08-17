import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../models/card_prices.dart';
import '../api/ygoprodeck_client.dart';
import '../db/dao/card_dao.dart';
import '../db/dao/card_price_dao.dart';
import '../db/dao/collection_dao.dart';
import '../db/database.dart';

part 'price_repository.g.dart';

/// How long a cached price row is reused before it is re-fetched.
///
/// A day, matching how fast these figures actually move and keeping a repeated
/// "what is my collection worth" free. YGOPRODeck caches its own responses for
/// two days, so a shorter TTL here would mostly re-download identical numbers.
const Duration kPriceTtl = Duration(hours: 24);

/// What a whole collection is worth, at the two granularities the API supports.
///
/// **Two totals, never one.** [cardmarketEur] and [tcgplayerUsd] are different
/// currencies from different marketplaces; there is no exchange rate in this
/// app and adding one would present a guess as a measurement.
///
/// Both are floors rather than valuations: YGOPRODeck documents each card-level
/// figure as "the lowest price found across multiple versions of that card", so
/// condition, edition and which printing is actually in hand are all invisible
/// to it. [unpricedCards] is the honesty check — a large number there means the
/// totals describe only part of the collection.
class CollectionValue {
  const CollectionValue({
    required this.cardmarketEur,
    required this.tcgplayerUsd,
    required this.pricedCards,
    required this.unpricedCards,
    required this.asOf,
    required this.lines,
  });

  final double cardmarketEur;
  final double tcgplayerUsd;

  /// Distinct passcodes that contributed at least one figure to a total.
  final int pricedCards;

  /// Distinct passcodes the API had no usable price for. Counted, not hidden:
  /// a total assembled from half a collection has to say so.
  final int unpricedCards;

  /// The **oldest** price used, so the stamp shown beside the totals describes
  /// the whole of them rather than the most recently refreshed corner.
  final DateTime? asOf;

  /// One line per distinct card owned, priced or not, sorted by name.
  ///
  /// Kept rather than discarded into the two totals because it is what the
  /// value export writes, and building it here means the exported numbers *are*
  /// the displayed numbers — no second fetch, no second pass over the cache,
  /// and no way for the file to disagree with the screen.
  ///
  /// **Unpriced cards are present**, carrying nulls. They are the detail behind
  /// [unpricedCards]: a total that admits it covers only part of a collection
  /// should be able to say which part.
  final List<CollectionValueLine> lines;
}

/// One card's contribution to a [CollectionValue].
///
/// Prices are per **card**, not per collection entry: YGOPRODeck's card-level
/// figure is the lowest across a card's printings, so condition, edition and
/// set are all invisible to it and a copy in any of them prices the same. Hence
/// one line per passcode, with [quantity] summed over every entry holding it.
class CollectionValueLine {
  const CollectionValueLine({
    required this.passcode,
    required this.name,
    required this.quantity,
    required this.cardmarketEur,
    required this.tcgplayerUsd,
    required this.pricedAt,
  });

  final String passcode;
  final String name;

  /// Copies owned across every condition, edition and language.
  final int quantity;

  /// Unit prices, null when the API had no figure. Both null means this card
  /// contributed nothing to either total.
  final double? cardmarketEur;
  final double? tcgplayerUsd;

  /// When these figures were fetched, null when there are none.
  final DateTime? pricedAt;
}

/// Market prices: fetched from YGOPRODeck, cached card-level in `card_prices`.
///
/// Per-set prices are deliberately **not** cached. They come back in the same
/// response, but they are only ever read on one card's Prices tab, where a live
/// figure is both cheap and more useful than a stored one; the card-level row
/// is cached because valuing a collection reads hundreds of them at once.
class PriceRepository {
  PriceRepository({
    required this._priceDao,
    required this._collectionDao,
    required this._cardDao,
    YgoProdeckClient? client,
  })
    // Injectable so this repository's tests run offline against a fake, the
    // same seam `CardRepository` uses for the same reason.
    : _client = client ?? YgoProdeckClient();

  final CardPriceDao _priceDao;
  final CollectionDao _collectionDao;

  /// Only for card *names*, which a value breakdown needs and neither of the
  /// other two DAOs carries.
  final CardDao _cardDao;
  final YgoProdeckClient _client;

  /// Everything known about one card's pricing, always live.
  ///
  /// Live because the per-set table is the point of this call and those figures
  /// are not stored. The card-level half is written to the cache on the way
  /// through, so opening a card's Prices tab also warms the collection total.
  ///
  /// Null when the API does not recognise the passcode — alt-art ids and cards
  /// the sync has since moved past both land here.
  Future<CardPricing?> pricingFor(String passcode) async {
    final results = await _client.fetchPrices([passcode]);
    if (results.isEmpty) return null;
    final pricing = results.first;
    await _priceDao.upsertAll([pricing.card]);
    return pricing;
  }

  /// One card's cached prices, fetching only if there is nothing usable.
  ///
  /// Backs the estimate line on a card's details, which must not cost a request
  /// every time the screen is opened. Never throws: an estimate is a
  /// convenience, and a failure to price a card must not take down the detail
  /// screen the user opened to read its effect.
  Future<CardPrices?> cachedOrFetch(String passcode) async {
    final cached = await _priceDao.get(passcode);
    if (cached != null && _isFresh(cached)) return cached;
    try {
      final pricing = await _client.fetchPrices([passcode]);
      if (pricing.isEmpty) return cached;
      await _priceDao.upsertAll([pricing.first.card]);
      return pricing.first.card;
    } catch (_) {
      // Offline, or a transient failure. A stale figure with its own "as of"
      // stamp beats an empty row.
      return cached;
    }
  }

  /// Values the whole collection, fetching only the prices that are missing or
  /// past [kPriceTtl].
  ///
  /// [onProgress] reports `(done, total)` in distinct passcodes, so the caller
  /// can show real progress rather than an indeterminate spinner — this can be
  /// a dozen sequential requests on a large collection.
  ///
  /// Each chunk is written as it lands rather than all at the end: an
  /// interrupted or failed run then leaves its progress behind, and the retry
  /// picks up where it stopped instead of re-fetching everything.
  Future<CollectionValue> collectionValue({
    void Function(int done, int total)? onProgress,
    bool forceRefresh = false,
  }) async {
    final owned = await _collectionDao.quantityByPasscode();
    final passcodes = owned.keys.toList();
    final total = passcodes.length;
    if (total == 0) {
      return const CollectionValue(
        cardmarketEur: 0,
        tcgplayerUsd: 0,
        pricedCards: 0,
        unpricedCards: 0,
        asOf: null,
        lines: [],
      );
    }

    final known = <String, CardPrices>{};
    if (!forceRefresh) {
      for (final row in await _priceDao.getForPasscodes(passcodes)) {
        if (_isFresh(row)) known[row.passcode] = row;
      }
    }

    final missing = [
      for (final passcode in passcodes)
        if (!known.containsKey(passcode)) passcode,
    ];
    onProgress?.call(known.length, total);

    for (var i = 0; i < missing.length; i += kPriceChunkSize) {
      final chunk = missing.sublist(
        i,
        (i + kPriceChunkSize).clamp(0, missing.length),
      );
      final fetched = await _client.fetchPrices(chunk);
      await _priceDao.upsertAll([for (final p in fetched) p.card]);
      for (final p in fetched) {
        known[p.card.passcode] = p.card;
      }
      onProgress?.call(known.length, total);
    }

    // Names for the breakdown. One round trip, and only the rows that exist —
    // which for owned passcodes is all of them, since `collection_entries`
    // carries a foreign key onto `cards`.
    final names = {
      for (final card in await _cardDao.getByPasscodes(passcodes))
        card.passcode: card.name,
    };

    var cardmarket = 0.0;
    var tcgplayer = 0.0;
    var priced = 0;
    DateTime? asOf;
    final lines = <CollectionValueLine>[];
    for (final entry in owned.entries) {
      final prices = known[entry.key];
      // A card the API did not recognise, or recognised with no figure at all.
      // `parsePrice` has already folded the API's very common "0.00" into null,
      // so this is the single place that decides what "unpriced" means.
      if (prices == null ||
          (prices.cardmarket == null && prices.tcgplayer == null)) {
        // Still a line: the breakdown names the cards the totals leave out.
        lines.add(
          CollectionValueLine(
            passcode: entry.key,
            name: names[entry.key] ?? '',
            quantity: entry.value,
            cardmarketEur: null,
            tcgplayerUsd: null,
            pricedAt: null,
          ),
        );
        continue;
      }
      priced++;
      cardmarket += (prices.cardmarket ?? 0) * entry.value;
      tcgplayer += (prices.tcgplayer ?? 0) * entry.value;
      if (asOf == null || prices.updatedAt.isBefore(asOf)) {
        asOf = prices.updatedAt;
      }
      lines.add(
        CollectionValueLine(
          passcode: entry.key,
          name: names[entry.key] ?? '',
          quantity: entry.value,
          cardmarketEur: prices.cardmarket,
          tcgplayerUsd: prices.tcgplayer,
          pricedAt: prices.updatedAt,
        ),
      );
    }
    // By name, then passcode: `quantityByPasscode` groups in whatever order
    // SQLite returns, and an export is easier to read — and to diff against an
    // earlier one — when it is ordered by the column a human reads.
    lines.sort((a, b) {
      final byName = a.name.compareTo(b.name);
      return byName != 0 ? byName : a.passcode.compareTo(b.passcode);
    });

    return CollectionValue(
      cardmarketEur: cardmarket,
      tcgplayerUsd: tcgplayer,
      pricedCards: priced,
      unpricedCards: total - priced,
      asOf: asOf,
      lines: lines,
    );
  }

  bool _isFresh(CardPrices row) =>
      DateTime.now().difference(row.updatedAt) < kPriceTtl;
}

@riverpod
Future<PriceRepository> priceRepository(Ref ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return PriceRepository(
    priceDao: CardPriceDao(db),
    collectionDao: CollectionDao(db),
    cardDao: CardDao(db),
  );
}
