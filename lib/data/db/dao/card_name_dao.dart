import 'package:sqflite/sqflite.dart';

/// One card's name in one language, as stored in `card_names`.
class CardName {
  const CardName({
    required this.passcode,
    required this.language,
    required this.name,
  });

  final String passcode;

  /// This app's two-letter code (`IT`), the same vocabulary as
  /// `collection_entries.language` — not YGOPRODeck's (`it`).
  final String language;

  final String name;

  Map<String, Object?> toMap() => {
    'passcode': passcode,
    'language': language,
    'name': name,
  };
}

/// Localized card names, loaded from a bundled asset rather than the network.
///
/// The search itself lives on [CardDao] (`searchByLocalizedName`), because it
/// joins `cards` and returns cards — this DAO only owns getting the names in
/// and reporting whether they are there.
class CardNameDao {
  const CardNameDao(this._db);

  /// A [DatabaseExecutor] rather than a [Database] so the initial load can run
  /// inside one transaction, like [CardDao.insertAll] does during a sync.
  final DatabaseExecutor _db;

  /// Writes every name, replacing any row already there for the same
  /// (passcode, language).
  ///
  /// `replace` rather than `ignore` so regenerating the asset with corrected
  /// translations actually corrects the database — the loader only calls this
  /// when the asset's version has moved, so the cost is paid once.
  Future<void> insertAll(List<CardName> names) async {
    final batch = _db.batch();
    for (final name in names) {
      batch.insert(
        'card_names',
        name.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<int> countFor(String language) async {
    final result = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM card_names WHERE language = ?',
      [language],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
