import 'package:sqflite/sqflite.dart';

import '../../../models/ygo_card.dart';

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
