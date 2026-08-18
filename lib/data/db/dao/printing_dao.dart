import 'package:sqflite/sqflite.dart';

import '../../../models/printing.dart';
import 'sql_chunks.dart';

class PrintingDao {
  const PrintingDao(this._db);

  /// A [DatabaseExecutor] rather than a [Database] so this DAO can run
  /// inside an existing transaction (e.g. during a YGOPRODeck sync) as well
  /// as standalone.
  final DatabaseExecutor _db;

  Future<void> insertAll(List<Printing> printings) async {
    final batch = _db.batch();
    for (final printing in printings) {
      batch.insert(
        'printings',
        printing.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Printing>> getForPasscode(String passcode) async {
    final rows = await _db.query(
      'printings',
      where: 'passcode = ?',
      whereArgs: [passcode],
    );
    return rows.map(Printing.fromMap).toList();
  }

  /// Every printing of every listed card, for callers that would otherwise do
  /// one round trip per card — a CSV import resolving a few hundred set
  /// codes back to `printings.id`.
  ///
  /// Follows the dynamic-`IN` convention set by `CardDao.getByPasscodes`:
  /// placeholders built from the argument's **length only**, so the query stays
  /// parameterized, and an early return for the empty case because `IN ()` is
  /// invalid SQL. Order is unspecified; group by `passcode` at the call site.
  /// The list is split by [sqlChunks] so a large collection cannot exceed
  /// SQLite's bound parameter limit.
  Future<List<Printing>> getForPasscodes(List<String> passcodes) async {
    if (passcodes.isEmpty) return const [];
    final result = <Printing>[];
    for (final chunk in sqlChunks(passcodes)) {
      final placeholders = List.filled(chunk.length, '?').join(', ');
      final rows = await _db.query(
        'printings',
        where: 'passcode IN ($placeholders)',
        whereArgs: chunk,
      );
      result.addAll(rows.map(Printing.fromMap));
    }
    return result;
  }
}
