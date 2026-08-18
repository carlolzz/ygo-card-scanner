import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../models/card_prices.dart';
import '../api/ygoprodeck_client.dart';
import '../../models/printing.dart';
import '../db/dao/card_dao.dart';
import '../db/dao/card_price_dao.dart';
import '../db/dao/collection_dao.dart';
import '../db/dao/printing_dao.dart';
import '../db/dao/printing_price_dao.dart';
import '../db/database.dart';

part 'price_repository.g.dart';

/// How long a cached price row is reused before it is re-fetched.
///
/// A day, matching how fast these figures actually move and keeping a repeated
/// "what is my collection worth" free. YGOPRODeck caches its own responses for
/// two days, so a shorter TTL here would mostly re-download identical numbers.
const Duration kPriceTtl = Duration(hours: 24);

/// Where a line's US dollar figure came from.
///
/// The distinction is the whole point of pricing by printing, so it is carried
/// on every line and surfaced in both the breakdown screen and the CSV: a total
/// built mostly from [cardFloor] is barely better than the card-level one this
/// replaced, and the user has no way to tell without being shown.
enum PriceBasis {
  /// This printing's own `set_price`, at its set and rarity. The real figure.
  printing,

  /// The card-level TCGplayer floor — the copies carry no printing, or the
  /// printing has no usable `set_price`.
  cardFloor,

  /// No US dollar figure at all.
  none,
}

/// What a whole collection is worth, at the granularities the API supports.
///
/// **Two totals, never one.** [cardmarketEur] and [tcgplayerUsd] are different
/// currencies from different marketplaces; there is no exchange rate in this
/// app and adding one would present a guess as a measurement.
///
/// **They are also no longer the same kind of figure, and that asymmetry is
/// permanent.** [tcgplayerUsd] prices each copy at the set and rarity actually
/// recorded, falling back to the card-level floor only where none is;
/// [cardmarketEur] is *always* that floor, because YGOPRODeck reports
/// Cardmarket at the card level and nowhere else. Since the card-level figure
/// is documented as "the lowest price found across multiple versions of that
/// card" — and is €0.02 for Blue-Eyes White Dragon, Dark Magician and Mirror
/// Force alike — the euro total is close to `€0.02 x copies` and must be
/// labelled as a floor wherever it is shown.
///
/// Condition and edition are invisible to both. [unpricedCards] and
/// [printingPricedLines] are the honesty checks.
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

  /// Distinct **passcodes** that contributed at least one figure to a total.
  final int pricedCards;

  /// Distinct **passcodes** the API had no usable price for. Counted, not
  /// hidden: a total assembled from half a collection has to say so.
  ///
  /// Note that [pricedCards] + [unpricedCards] is the number of distinct cards
  /// owned, which since step 26 is **smaller** than `lines.length` — a card
  /// held as three printings is one card and three lines. The counts stay per
  /// card because the strings beside them say "cards", because the fetch is
  /// bounded by passcodes, and because `CollectionValueController` derives its
  /// progress from them and would otherwise contradict itself.
  final int unpricedCards;

  /// The **oldest** price used, so the stamp shown beside the totals describes
  /// the whole of them rather than the most recently refreshed corner. Spans
  /// both price tables — a line can draw its dollars from a printing row and
  /// its euros from a card row, fetched at different times.
  final DateTime? asOf;

  /// One line per `(card, printing)` owned, priced or not, sorted by name.
  ///
  /// Kept rather than discarded into the two totals because it is what the
  /// breakdown screen shows and the value export writes, and building it here
  /// means those numbers *are* the displayed numbers — no second fetch, no
  /// second pass over the cache, and no way for them to disagree.
  ///
  /// **Unpriced lines are present**, carrying nulls. They are the detail behind
  /// [unpricedCards]: a total that admits it covers only part of a collection
  /// should be able to say which part.
  final List<CollectionValueLine> lines;

  /// How many lines are priced at their own printing rather than the card
  /// floor. The measure of how much this valuation is worth trusting.
  int get printingPricedLines =>
      lines.where((line) => line.usdBasis == PriceBasis.printing).length;
}

/// One printing's contribution to a [CollectionValue].
///
/// **One line per `(passcode, printingId)`**, with [quantity] summed over every
/// entry holding it. That is the grain the prices have since schema v4: the
/// dollar figure comes from `card_sets[].set_price`, which is per set *and*
/// rarity, so a card held as two printings is two lines with genuinely
/// different unit prices. Condition, edition and language are summed away — no
/// price source distinguishes them.
///
/// A null [printingId] is the group of copies logged without a set. It is a
/// real line, priced at the card floor.
class CollectionValueLine {
  const CollectionValueLine({
    required this.passcode,
    required this.name,
    required this.printingId,
    required this.setCode,
    required this.setName,
    required this.rarity,
    required this.quantity,
    required this.cardmarketEur,
    required this.tcgplayerUsd,
    required this.usdBasis,
    required this.pricedAt,
  });

  final String passcode;
  final String name;

  /// The `printings.id` these copies were logged against, null when none was.
  final int? printingId;

  /// The printing's set code, name and rarity, for display and the export. All
  /// null when [printingId] is.
  final String? setCode;
  final String? setName;
  final String? rarity;

  /// Copies of this printing, across every condition, edition and language.
  final int quantity;

  /// Unit price in euros — **always** the card-level floor, since no per-set
  /// euro figure exists. Null when the API had none.
  final double? cardmarketEur;

  /// Unit price in US dollars, from whichever source [usdBasis] names.
  final double? tcgplayerUsd;

  /// Whether [tcgplayerUsd] is this printing's own figure or the card floor.
  final PriceBasis usdBasis;

  /// The **oldest** stamp among the figures that actually fed this line, null
  /// when there are none.
  final DateTime? pricedAt;

  /// "SET-CODE · Set Name", matching `Printing.setLabel` so a printing reads
  /// identically here and on the collection detail screen. Empty when this line
  /// carries no printing.
  String get setLabel => [setCode, setName].whereType<String>().join(' · ');
}

/// Market prices: fetched from YGOPRODeck, cached in `card_prices` (per card)
/// and `printing_prices` (per set and rarity).
///
/// Both come back in the **same** response, so caching the per-set half costs
/// no extra requests — it was simply being discarded until step 26. That is
/// what makes a real valuation possible: the card-level figure is documented as
/// the lowest across every version of a card and is €0.02 for most of them,
/// while `card_sets[].set_price` puts a CT13-EN008 Blue-Eyes at $74.49.
class PriceRepository {
  PriceRepository({
    required this._priceDao,
    required this._printingPriceDao,
    required this._collectionDao,
    required this._printingDao,
    required this._cardDao,
    YgoProdeckClient? client,
  })
    // Injectable so this repository's tests run offline against a fake, the
    // same seam `CardRepository` uses for the same reason.
    : _client = client ?? YgoProdeckClient();

  final CardPriceDao _priceDao;
  final PrintingPriceDao _printingPriceDao;
  final CollectionDao _collectionDao;

  /// For the set code, name and rarity behind each line, and to know which
  /// printings of a fetched card need a price row written.
  final PrintingDao _printingDao;

  /// Only for card *names*, which a value breakdown needs and none of the
  /// other DAOs carries.
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
    if (cached != null && _isFresh(cached.updatedAt)) return cached;
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
    final groups = await _collectionDao.quantityByPasscodeAndPrinting();
    // Distinct cards, not distinct groups: this is what the API is asked for,
    // what `onProgress` counts and what the "N cards have no price" line means.
    final passcodes = {for (final g in groups) g.passcode}.toList();
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

    // Every printing of every owned card, in one round trip. Two jobs: it gives
    // the lines their set code, name and rarity, and it is the list of rows a
    // fetched `SetPrice` can be matched onto.
    final printings = <int, Printing>{
      for (final printing in await _printingDao.getForPasscodes(passcodes))
        if (printing.id != null) printing.id!: printing,
    };
    final ownedPrintingIds = {
      for (final g in groups)
        if (g.printingId != null) g.printingId!,
    }.toList();

    final knownCards = <String, CardPrices>{};
    final knownPrintings = <int, PrintingPrice>{};
    if (!forceRefresh) {
      for (final row in await _priceDao.getForPasscodes(passcodes)) {
        if (_isFresh(row.updatedAt)) knownCards[row.passcode] = row;
      }
      for (final row in await _printingPriceDao.getForPrintings(
        ownedPrintingIds,
      )) {
        if (_isFresh(row.updatedAt)) knownPrintings[row.printingId] = row;
      }
    }

    // Owned printings, grouped by card, so a card can be judged stale because
    // one of its printings has never been priced even though its card-level row
    // is fresh. Both halves arrive in the same response, so a miss on either is
    // a miss on the card.
    final ownedPrintingsByPasscode = <String, List<int>>{};
    for (final g in groups) {
      if (g.printingId != null) {
        (ownedPrintingsByPasscode[g.passcode] ??= []).add(g.printingId!);
      }
    }

    final missing = [
      for (final passcode in passcodes)
        if (!knownCards.containsKey(passcode) ||
            (ownedPrintingsByPasscode[passcode] ?? const <int>[]).any(
              (id) => !knownPrintings.containsKey(id),
            ))
          passcode,
    ];
    onProgress?.call(knownCards.length, total);

    for (var i = 0; i < missing.length; i += kPriceChunkSize) {
      final chunk = missing.sublist(
        i,
        (i + kPriceChunkSize).clamp(0, missing.length),
      );
      final fetched = await _client.fetchPrices(chunk);
      // Both tables are written before the next chunk, keeping the "written as
      // it lands" rule: an interrupted run leaves its progress behind.
      await _priceDao.upsertAll([for (final p in fetched) p.card]);
      final printingRows = <PrintingPrice>[];
      for (final p in fetched) {
        knownCards[p.card.passcode] = p.card;
        final matched = _matchSetPrices(p, printings);
        for (final row in matched) {
          printingRows.add(row);
          knownPrintings[row.printingId] = row;
        }
      }
      await _printingPriceDao.upsertAll(printingRows);
      onProgress?.call(knownCards.length, total);
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
    final pricedPasscodes = <String>{};
    DateTime? asOf;
    final lines = <CollectionValueLine>[];
    for (final group in groups) {
      final cardPrices = knownCards[group.passcode];
      final printing = group.printingId == null
          ? null
          : printings[group.printingId];
      final printingPrice = group.printingId == null
          ? null
          : knownPrintings[group.printingId];

      // Euros are always the card-level floor: YGOPRODeck reports Cardmarket at
      // the card level and nowhere else.
      final eurUnit = cardPrices?.cardmarket;

      // Dollars prefer this printing's own figure. `parsePrice` has already
      // folded the API's very common "0.00" into null, so a null price here
      // means "no figure for this printing" and the card floor is the answer.
      final double? usdUnit;
      final PriceBasis basis;
      if (printingPrice?.price != null) {
        usdUnit = printingPrice!.price;
        basis = PriceBasis.printing;
      } else if (cardPrices?.tcgplayer != null) {
        usdUnit = cardPrices!.tcgplayer;
        basis = PriceBasis.cardFloor;
      } else {
        usdUnit = null;
        basis = PriceBasis.none;
      }

      // The stamps that actually fed this line, oldest first — a line can draw
      // its dollars from a printing row fetched today and its euros from a card
      // row fetched yesterday.
      DateTime? pricedAt;
      void note(DateTime? stamp) {
        if (stamp == null) return;
        if (pricedAt == null || stamp.isBefore(pricedAt!)) pricedAt = stamp;
      }

      if (eurUnit != null) note(cardPrices!.updatedAt);
      if (basis == PriceBasis.printing) note(printingPrice!.updatedAt);
      if (basis == PriceBasis.cardFloor) note(cardPrices!.updatedAt);

      if (eurUnit != null || usdUnit != null) {
        pricedPasscodes.add(group.passcode);
        cardmarket += (eurUnit ?? 0) * group.quantity;
        tcgplayer += (usdUnit ?? 0) * group.quantity;
        if (asOf == null || pricedAt!.isBefore(asOf)) asOf = pricedAt;
      }

      lines.add(
        CollectionValueLine(
          passcode: group.passcode,
          name: names[group.passcode] ?? '',
          printingId: group.printingId,
          setCode: printing?.setCode,
          setName: printing?.setName,
          rarity: printing?.rarity,
          quantity: group.quantity,
          cardmarketEur: eurUnit,
          tcgplayerUsd: usdUnit,
          usdBasis: basis,
          pricedAt: pricedAt,
        ),
      );
    }
    // By name, then set code, then printing id: the grouping comes back in
    // whatever order SQLite chose, and both the breakdown screen and the export
    // are easier to read — and to diff against an earlier export — when a
    // card's printings sit together under its name. The id is the tie-break
    // that makes the order total, so two runs cannot differ.
    lines.sort((a, b) {
      final byName = a.name.compareTo(b.name);
      if (byName != 0) return byName;
      final bySet = (a.setCode ?? '').compareTo(b.setCode ?? '');
      if (bySet != 0) return bySet;
      return (a.printingId ?? -1).compareTo(b.printingId ?? -1);
    });

    return CollectionValue(
      cardmarketEur: cardmarket,
      tcgplayerUsd: tcgplayer,
      pricedCards: pricedPasscodes.length,
      unpricedCards: total - pricedPasscodes.length,
      asOf: asOf,
      lines: lines,
    );
  }

  /// One fetched card's `card_sets` figures, resolved onto the `printings` rows
  /// this app stores.
  ///
  /// **Matched on the exact `(passcode, set_code, rarity)` triple** — the
  /// `printings` UNIQUE key. Both sides come from the same three fields of the
  /// same endpoint (`_parseEntry` and `parsePricingEntry` read `set_code` and
  /// `set_rarity` identically), so string equality is an identity here, not an
  /// approximation, and none of `resolveImportRow`'s case-and-space ladder
  /// applies — that exists because a *human* typed the CSV. `set_name` is
  /// deliberately excluded: it is not part of the UNIQUE key, so a set renamed
  /// between syncs would otherwise stop matching.
  ///
  /// **A row is returned for every owned printing of the card, including those
  /// with no figure**, carrying a null price. That is what records "asked, and
  /// there was nothing" — without it the freshness check could never be
  /// satisfied for those printings and the card would be re-fetched on every
  /// valuation forever.
  ///
  /// Where two `card_sets` entries collapse onto one printing (the same set and
  /// rarity listed twice, which `PrintingDao.insertAll` stores once), the
  /// **lowest** non-null price wins. Any deterministic rule would do; an
  /// unstated "last one seen" is how two runs report two different totals.
  List<PrintingPrice> _matchSetPrices(
    CardPricing pricing,
    Map<int, Printing> printings,
  ) {
    final byKey = <({String? setCode, String? rarity}), double?>{};
    for (final set in pricing.sets) {
      final key = (setCode: set.setCode, rarity: set.rarity);
      final existing = byKey[key];
      if (!byKey.containsKey(key) ||
          (set.price != null && (existing == null || set.price! < existing))) {
        byKey[key] = set.price;
      }
    }

    final now = DateTime.now();
    return [
      for (final printing in printings.values)
        if (printing.passcode == pricing.card.passcode)
          PrintingPrice(
            printingId: printing.id!,
            price: byKey[(setCode: printing.setCode, rarity: printing.rarity)],
            updatedAt: now,
          ),
    ];
  }

  bool _isFresh(DateTime updatedAt) =>
      DateTime.now().difference(updatedAt) < kPriceTtl;
}

@riverpod
Future<PriceRepository> priceRepository(Ref ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return PriceRepository(
    priceDao: CardPriceDao(db),
    printingPriceDao: PrintingPriceDao(db),
    collectionDao: CollectionDao(db),
    printingDao: PrintingDao(db),
    cardDao: CardDao(db),
  );
}
