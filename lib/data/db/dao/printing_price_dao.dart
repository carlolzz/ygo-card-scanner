import 'package:sqflite/sqflite.dart';

import '../../../models/card_prices.dart';
import 'sql_chunks.dart';

/// Reads and writes the `printing_prices` cache (schema v4).
///
/// A cache, not a source of truth, exactly like `CardPriceDao`: every row can
/// be re-fetched from YGOPRODeck, and a re-sync deliberately clears the whole
/// table through the `printings` → `cards` cascade. Nothing here is user data.
///
/// **The cascade matters more here than it does for card prices.**
/// `printings.id` is AUTOINCREMENT and a re-sync replaces every `cards` row, so
/// the printings are re-keyed. A price row that survived that would quietly
/// describe a *different* printing, at a different set and rarity — a wrong
/// number with nothing on screen to suggest it. See `migrations.dart`.
class PrintingPriceDao {
  const PrintingPriceDao(this._db);

  /// A [DatabaseExecutor] rather than a [Database] so this DAO can run
  /// inside an existing transaction as well as standalone, matching the
  /// other DAOs.
  final DatabaseExecutor _db;

  Future<PrintingPrice?> get(int printingId) async {
    final rows = await _db.query(
      'printing_prices',
      where: 'printing_id = ?',
      whereArgs: [printingId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PrintingPrice.fromMap(rows.first);
  }

  /// Batched [get]: one round trip for many printings, which is what keeps
  /// valuing a whole collection a handful of queries.
  ///
  /// Returns **only the rows that exist**, in **unspecified order** — callers
  /// index by `printingId` rather than relying on position. A missing row and a
  /// row with a null `price` mean different things and must not be conflated:
  /// see [PrintingPrice].
  ///
  /// Placeholders are built from the argument's **length only**, never its
  /// contents, following `CardDao.getByPasscodes`; the list is split by
  /// [sqlChunks] so a large collection cannot exceed SQLite's parameter limit.
  Future<List<PrintingPrice>> getForPrintings(List<int> printingIds) async {
    // `IN ()` is not valid SQL, and a collection logged entirely without sets
    // reaches this with nothing to look up.
    if (printingIds.isEmpty) return const [];
    final result = <PrintingPrice>[];
    for (final chunk in sqlChunks(printingIds)) {
      final placeholders = List.filled(chunk.length, '?').join(', ');
      final rows = await _db.query(
        'printing_prices',
        where: 'printing_id IN ($placeholders)',
        whereArgs: chunk,
      );
      result.addAll(rows.map(PrintingPrice.fromMap));
    }
    return result;
  }

  /// Writes a batch of freshly fetched rows, replacing any cached ones.
  ///
  /// `replace` rather than a merge, for `CardPriceDao.upsertAll`'s reason: a
  /// price row is wholly derived from one API response, so there is nothing in
  /// the row it supersedes worth preserving, and a partial merge would leave an
  /// `updated_at` stamp describing only half of it.
  ///
  /// Rows carrying a **null price are expected and must be written**. They
  /// record that the printing was asked about and found to have no figure,
  /// which is what stops its card being re-fetched on every valuation forever.
  Future<void> upsertAll(List<PrintingPrice> prices) async {
    if (prices.isEmpty) return;
    final batch = _db.batch();
    for (final row in prices) {
      batch.insert(
        'printing_prices',
        row.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }
}
