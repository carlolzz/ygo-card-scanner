import '../repositories/price_repository.dart';
import 'csv_writer.dart';

/// Pure, offline-testable CSV serialization of a collection's value breakdown:
/// what each card is worth, and what the copies of it are worth together.
///
/// **One row per distinct card, not per collection entry.** That is the
/// granularity the prices actually have — YGOPRODeck's card-level figure is the
/// lowest across a card's printings, so condition, edition and set are
/// invisible to it. A per-entry file would repeat one unit price across rows
/// and read as if a Near Mint 1st Edition were priced separately from a Played
/// one. Join this file to a collection export on `passcode` for that detail.
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
  'quantity',
  'cardmarket_eur',
  'tcgplayer_usd',
  'cardmarket_eur_total',
  'tcgplayer_usd_total',
  'priced_at',
];

/// Writes [value]'s per-card lines, in the order the repository sorted them.
///
/// Two currencies in separate columns and never a sum of them: Cardmarket
/// reports euros and TCGplayer dollars, and this app carries no exchange rate.
/// The currency lives in the column *name* — a cell holds a bare number, so a
/// spreadsheet or pandas reads it as one.
///
/// An unknown price is an **empty cell**, not a zero: the API's own "0.00"
/// means "no figure", which `parsePrice` has already folded into null, and
/// writing 0 would let a card with no price drag an average down as if it were
/// worthless.
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
        '${line.quantity}',
        _money(line.cardmarketEur),
        _money(line.tcgplayerUsd),
        _money(_total(line.cardmarketEur, line.quantity)),
        _money(_total(line.tcgplayerUsd, line.quantity)),
        line.pricedAt?.toUtc().toIso8601String() ?? '',
      ]),
    );
  }
  return buffer.toString();
}

/// Two decimals and nothing else — deliberately *not* `core/money.dart`'s
/// `formatEur`/`formatUsd`, which embed a currency symbol and render an em dash
/// for a missing figure. Both are right on screen and wrong in a column
/// something else has to parse.
String _money(double? value) => value == null ? '' : value.toStringAsFixed(2);

double? _total(double? unit, int quantity) =>
    unit == null ? null : unit * quantity;
