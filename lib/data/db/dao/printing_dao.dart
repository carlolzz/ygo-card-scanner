import 'package:sqflite/sqflite.dart';

import '../../../models/printing.dart';

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
}
