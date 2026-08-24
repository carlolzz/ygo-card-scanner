import 'package:sqflite/sqflite.dart';

import '../../../models/card_search_hit.dart';
import '../../../models/ygo_card.dart';
import 'sql_chunks.dart';

class CardDao {
  const CardDao(this._db);

  /// A [DatabaseExecutor] rather than a [Database] so this DAO can run
  /// inside an existing transaction (e.g. during a YGOPRODeck sync) as well
  /// as standalone.
  final DatabaseExecutor _db;

  Future<void> insertAll(List<YgoCard> cards) async {
    final batch = _db.batch();
    for (final card in cards) {
      batch.insert(
        'cards',
        card.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<YgoCard?> getByPasscode(String passcode) async {
    final rows = await _db.query(
      'cards',
      where: 'passcode = ?',
      whereArgs: [passcode],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return YgoCard.fromMap(rows.first);
  }

  /// Batched [getByPasscode]: one round trip for many passcodes.
  ///
  /// Returns **only the rows that exist** — a passcode with no `cards` row is
  /// simply absent, the same information a null from [getByPasscode] carries —
  /// and in **unspecified order** (SQLite returns rowid order for an `IN`
  /// predicate). Callers that need a particular order must index the result by
  /// passcode and walk their own list; see `PHashArtMatcher.match`, which has to
  /// preserve Hamming rank.
  ///
  /// The placeholder list is built from the argument's **length only**, never
  /// from its contents, so the query stays fully parameterized.
  Future<List<YgoCard>> getByPasscodes(List<String> passcodes) async {
    // `IN ()` is not valid SQL, and an empty candidate list is a normal case
    // (nothing detected in the frame).
    if (passcodes.isEmpty) return const [];
    // Split so a whole-collection lookup cannot exceed SQLite's bound
    // parameter limit — see `sql_chunks.dart`.
    final result = <YgoCard>[];
    for (final chunk in sqlChunks(passcodes)) {
      final placeholders = List.filled(chunk.length, '?').join(', ');
      final rows = await _db.query(
        'cards',
        where: 'passcode IN ($placeholders)',
        whereArgs: chunk,
      );
      result.addAll(rows.map(YgoCard.fromMap));
    }
    return result;
  }

  /// Ranks prefix matches ('query%') above substring-only matches
  /// ('%query%') so a search for "Blue-Eyes" surfaces "Blue-Eyes White
  /// Dragon" before "Toon Blue-Eyes White Dragon".
  Future<List<YgoCard>> searchByName(String query, {int limit = 20}) async {
    final rows = await _db.rawQuery(
      '''
      SELECT * FROM cards
      WHERE name LIKE '%' || ? || '%'
      ORDER BY
        CASE WHEN name LIKE ? || '%' THEN 0 ELSE 1 END,
        name
      LIMIT ?
      ''',
      [query, query, limit],
    );
    return rows.map(YgoCard.fromMap).toList();
  }

  /// [searchByName] against `card_names` instead of `cards.name`, for searching
  /// in a language the sync never fetches.
  ///
  /// The ranking is deliberately identical — prefix matches above
  /// substring-only ones — but computed on the *localized* name, which is the
  /// only string the user typed against. Ordering on `c.name` here would rank
  /// Italian results by their English names, which reads as no order at all.
  ///
  /// An inner join, so a card the shipped asset has no translation for is
  /// absent rather than listed under its English name: the file covers ~11.6k
  /// of ~14.6k cards, and silently mixing the two languages in one result list
  /// would make it impossible to tell which is which.
  Future<List<CardSearchHit>> searchByLocalizedName(
    String query, {
    required String language,
    int limit = 20,
  }) async {
    final rows = await _db.rawQuery(
      '''
      SELECT c.*, n.name AS localized_name
      FROM cards c
      JOIN card_names n
        ON n.passcode = c.passcode AND n.language = ?
      WHERE n.name LIKE '%' || ? || '%'
      ORDER BY
        CASE WHEN n.name LIKE ? || '%' THEN 0 ELSE 1 END,
        n.name
      LIMIT ?
      ''',
      [language, query, query, limit],
    );
    return [
      for (final row in rows)
        // `YgoCard.fromMap` reads the columns it knows by name and ignores the
        // extra one, so the joined row maps without a projection.
        CardSearchHit(YgoCard.fromMap(row), row['localized_name'] as String?),
    ];
  }

  Future<int> count() async {
    final result = await _db.rawQuery('SELECT COUNT(*) AS c FROM cards');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// No-op if [passcode] doesn't exist — the caller already looked the card
  /// up before deciding to download its image.
  Future<void> updateLocalImagePath(String passcode, String localPath) async {
    await _db.update(
      'cards',
      {'local_image_path': localPath},
      where: 'passcode = ?',
      whereArgs: [passcode],
    );
  }
}
