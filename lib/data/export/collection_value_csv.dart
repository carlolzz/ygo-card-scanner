import '../repositories/price_repository.dart';
import 'csv_writer.dart';

/// Pure, offline-testable CSV serialization of a collection's value breakdown:
/// what each printing is worth, and what the copies of it are worth together.
///
/// **One row per `(card, printing)` held.** That is the granularity the dollar
/// figures have: they come from `card_sets[].set_price`, which is per set *and*
/// rarity, so a card held as two printings is two rows with genuinely different
/// unit prices. Condition, edition and language are summed away, because no
/// price source distinguishes them — join this file to a collection export on
/// `passcode` for that detail.
///
/// **The two currencies are not the same kind of figure**, and the column names
/// say so. `tcgplayer_usd` is the printing's own price wherever one is known;
/// `cardmarket_eur_floor` is *always* the card-level floor, since YGOPRODeck
/// reports Cardmarket at the card level and nowhere else. `tcgplayer_basis`
/// says which rows got a real per-printing figure and which fell back.
///
/// **This is not a collection CSV and cannot be imported as one.** It has no
/// `condition` column, so `parseCollectionCsv` rejects it outright rather than
/// reading it half-way.
///
/// Escaping, quoting and the formula guard come from `csv_writer.dart`, shared
/// with the collection export.
const List<String> collectionValueCsvHeader = [
  'passcode',
  'name',
  'set_code',
  'set_name',
  'rarity',
  'quantity',
  'cardmarket_eur_floor',
  'tcgplayer_usd',
  'tcgplayer_basis',
  'cardmarket_eur_floor_total',
  'tcgplayer_usd_total',
  'priced_at',
];

/// Writes [value]'s lines, in the order the repository sorted them.
///
/// Two currencies in separate columns and never a sum of them: Cardmarket
/// reports euros and TCGplayer dollars, and this app carries no exchange rate.
/// The currency lives in the column *name* — a cell holds a bare number, so a
/// spreadsheet or pandas reads it as one.
///
/// An unknown price is an **empty cell**, not a zero: the API's own "0.00"
/// means "no figure", which `parsePrice` has already folded into null, and
/// writing 0 would let a card with no price drag an average down as if it were
/// worthless. `tcgplayer_basis` is empty on those rows for the same reason.
///
/// No trailing totals row — this file feeds spreadsheets and pandas/DuckDB,
/// where a summary line inside the data is a nuisance to strip. Note that each
/// line total is rounded to the cent independently, so summing the column can
/// land a cent or two off the figure on the Statistics screen, which sums the
/// unrounded values.
String collectionValueToCsv(CollectionValue value) {
  final buffer = StringBuffer();
  buffer.write(csvRow(collectionValueCsvHeader));
  for (final line in value.lines) {
    buffer.write(
      csvRow([
        line.passcode,
        line.name,
        line.setCode ?? '',
        line.setName ?? '',
        line.rarity ?? '',
        '${line.quantity}',
        _money(line.cardmarketEur),
        _money(line.tcgplayerUsd),
        _basis(line.usdBasis),
        _money(_total(line.cardmarketEur, line.quantity)),
        _money(_total(line.tcgplayerUsd, line.quantity)),
        line.pricedAt?.toUtc().toIso8601String() ?? '',
      ]),
    );
  }
  return buffer.toString();
}

/// Stable snake_case names, written out rather than taken from `.name`: these
/// are a file format a script parses, so they must not follow a Dart identifier
/// if one is ever renamed. [PriceBasis.none] is an empty cell, matching how
/// every other unknown is written here.
String _basis(PriceBasis basis) => switch (basis) {
  PriceBasis.printing => 'printing',
  PriceBasis.cardFloor => 'card_floor',
  PriceBasis.none => '',
};

/// Two decimals and nothing else — deliberately *not* `core/money.dart`'s
/// `formatEur`/`formatUsd`, which embed a currency symbol and render a dash
/// for a missing figure. Both are right on screen and wrong in a column
/// something else has to parse.
String _money(double? value) => value == null ? '' : value.toStringAsFixed(2);

double? _total(double? unit, int quantity) =>
    unit == null ? null : unit * quantity;
