import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sqflite/sqflite.dart';

import '../../models/printing.dart';
import '../../models/ygo_card.dart';
import '../api/ygoprodeck_client.dart';
import '../db/dao/card_dao.dart';
import '../db/dao/printing_dao.dart';
import '../db/database.dart';

part 'card_repository.g.dart';

/// Progress of a sync run, as a fraction between 0 and 1.
class SyncProgress {
  const SyncProgress(this.fraction);

  final double fraction;
}

class CardRepository {
  CardRepository({
    required this._cardDao,
    required this._printingDao,
    required this._database,
    YgoProdeckClient? client,
  }) : _client = client ?? YgoProdeckClient();

  final CardDao _cardDao;
  final PrintingDao _printingDao;
  final Database _database;
  final YgoProdeckClient _client;

  Future<YgoCard?> getByPasscode(String passcode) =>
      _cardDao.getByPasscode(passcode);

  Future<List<YgoCard>> searchByName(String query, {int limit = 20}) =>
      _cardDao.searchByName(query, limit: limit);

  Future<List<Printing>> getPrintingsForPasscode(String passcode) =>
      _printingDao.getForPasscode(passcode);

  /// Fetches the full YGOPRODeck dump and writes it in a single
  /// transaction, so a failure partway through leaves no partial state.
  /// Progress is emitted as a fraction between 0 and 1.
  Stream<SyncProgress> sync() async* {
    yield const SyncProgress(0);
    final fetched = await _client.fetchAllCards();
    yield const SyncProgress(0.5);

    await _database.transaction((txn) async {
      final txnCardDao = CardDao(txn);
      final txnPrintingDao = PrintingDao(txn);
      await txnCardDao.insertAll(fetched.map((f) => f.card).toList());
      await txnPrintingDao.insertAll(
        fetched.expand((f) => f.printings).toList(),
      );
      await txn.insert('meta', {
        'key': 'last_sync',
        'value': DateTime.now().millisecondsSinceEpoch.toString(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });

    yield const SyncProgress(1);
  }
}

@riverpod
Future<CardRepository> cardRepository(Ref ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return CardRepository(
    cardDao: CardDao(db),
    printingDao: PrintingDao(db),
    database: db,
  );
}
