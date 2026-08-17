import 'package:sqflite/sqflite.dart';

import '../../../models/card_prices.dart';

/// Reads and writes the `card_prices` cache (schema v3).
///
/// A cache, not a source of truth: every row can be re-fetched from YGOPRODeck,
/// and a re-sync deliberately clears the whole table through the `cards`
/// foreign key's cascade (see `migrations.dart`). Nothing here is user data.
class CardPriceDao {
  const CardPriceDao(this._db);

  /// A [DatabaseExecutor] rather than a [Database] so this DAO can run
  /// inside an existing transaction as well as standalone, matching the
  /// other DAOs.
  final DatabaseExecutor _db;

  Future<CardPrices?> get(String passcode) async {
    final rows = await _db.query(
      'card_prices',
      where: 'passcode = ?',
      whereArgs: [passcode],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return CardPrices.fromMap(rows.first);
  }

  /// Batched [get]: one round trip for many passcodes, which is what makes
  /// valuing a whole collection a handful of queries rather than one per card.
  ///
  /// Returns **only the rows that exist** — a passcode never priced is simply
  /// absent, the same information a null from [get] carries — in **unspecified
  /// order**. Callers index the result by passcode rather than relying on
  /// position.
  ///
  /// The placeholder list is built from the argument's **length only**, never
  /// from its contents, so the query stays fully parameterized. Follows
  /// `CardDao.getByPasscodes`, which set this convention.
  Future<List<CardPrices>> getForPasscodes(List<String> passcodes) async {
    // `IN ()` is not valid SQL, and an empty collection reaches this with
    // nothing to look up.
    if (passcodes.isEmpty) return const [];
    final placeholders = List.filled(passcodes.length, '?').join(', ');
    final rows = await _db.query(
      'card_prices',
      where: 'passcode IN ($placeholders)',
      whereArgs: passcodes,
    );
    return rows.map(CardPrices.fromMap).toList();
  }

  /// Writes a batch of freshly fetched rows, replacing any cached ones.
  ///
  /// `replace` rather than an upsert because a price row is wholly derived from
  /// one API response: there is no column worth preserving from the row it
  /// supersedes, and a partial merge would leave a `updated_at` stamp that
  /// described only some of the figures beside it.
  Future<void> upsertAll(List<CardPrices> prices) async {
    if (prices.isEmpty) return;
    final batch = _db.batch();
    for (final row in prices) {
      batch.insert(
        'card_prices',
        row.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }
}
