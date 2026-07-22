import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sqflite/sqflite.dart';

import '../../models/printing.dart';
import '../../models/ygo_card.dart';
import '../api/card_image_downloader.dart';
import '../api/ygoprodeck_client.dart';
import '../db/dao/card_dao.dart';
import '../db/dao/meta_dao.dart';
import '../db/dao/printing_dao.dart';
import '../db/database.dart';

part 'card_repository.g.dart';

enum SyncPhase { fetching, writing }

/// Progress of a sync run: an overall fraction between 0 and 1, plus which
/// phase produced it (see [CardRepository.sync]).
class SyncProgress {
  const SyncProgress(this.fraction, this.phase);

  final double fraction;
  final SyncPhase phase;
}

/// Number of cards written per batch during [CardRepository.sync]'s write
/// phase — small enough to report meaningful incremental progress, large
/// enough to keep the number of batched statements low.
const _syncWriteChunkSize = 1000;

class CardRepository {
  CardRepository({
    required this._cardDao,
    required this._printingDao,
    required this._metaDao,
    required this._database,
    YgoProdeckClient? client,
    CardImageDownloader? imageDownloader,
  }) : _client = client ?? YgoProdeckClient(),
       _imageDownloader = imageDownloader ?? CardImageDownloader();

  final CardDao _cardDao;
  final PrintingDao _printingDao;
  final MetaDao _metaDao;
  final Database _database;
  final YgoProdeckClient _client;
  final CardImageDownloader _imageDownloader;

  Future<YgoCard?> getByPasscode(String passcode) =>
      _cardDao.getByPasscode(passcode);

  Future<List<YgoCard>> searchByName(String query, {int limit = 20}) =>
      _cardDao.searchByName(query, limit: limit);

  Future<List<Printing>> getPrintingsForPasscode(String passcode) =>
      _printingDao.getForPasscode(passcode);

  /// Downloads [passcode]'s art to local storage the first time it's
  /// needed, and never again — subsequent calls no-op once a local file
  /// exists. Never throws: a network/disk failure here must not surface
  /// past this method, since whatever triggered it (adding to the
  /// collection) already succeeded.
  Future<void> ensureImageDownloaded(String passcode) async {
    try {
      final card = await _cardDao.getByPasscode(passcode);
      if (card == null || card.imageUrl == null) return;
      if (card.localImagePath != null &&
          await File(card.localImagePath!).exists()) {
        return;
      }
      final path = await _imageDownloader.download(passcode, card.imageUrl!);
      await _cardDao.updateLocalImagePath(passcode, path);
    } catch (_) {
      // Best-effort: retried on the next addOrIncrement for this passcode.
    }
  }

  /// `true` if no real sync has ever completed — either signal missing
  /// (no `last_sync` stamp, or an empty `cards` table) means the app needs
  /// to run [sync] before it has any real data to work with.
  Future<bool> needsSync() async {
    final lastSync = await _metaDao.get('last_sync');
    if (lastSync == null) return true;
    return await _cardDao.count() == 0;
  }

  /// Fetches the full YGOPRODeck dump and writes it in a single
  /// transaction, so a failure partway through leaves no partial state —
  /// only progress *reporting* is granular, not the atomicity of the write.
  ///
  /// Progress is reported in two phases: fetching (real download progress
  /// via Dio, 0-70%) and writing (chunked batch inserts, 70-100%).
  Stream<SyncProgress> sync() async* {
    final fetchProgress = StreamController<double>();
    final fetchFuture = _client
        .fetchAllCards(
          onReceiveProgress: (received, total) {
            if (total > 0) fetchProgress.add((received / total) * 0.7);
          },
        )
        .whenComplete(fetchProgress.close);

    await for (final fraction in fetchProgress.stream) {
      yield SyncProgress(fraction, SyncPhase.fetching);
    }
    final fetched = await fetchFuture;

    final cards = fetched.map((f) => f.card).toList();
    final printings = fetched.expand((f) => f.printings).toList();
    final cardChunks = (cards.length / _syncWriteChunkSize).ceil();
    // +1 for the printings write, +1 for the final meta stamp.
    final totalWriteSteps = cardChunks + 2;

    final writeProgress = StreamController<double>();
    final writeFuture = _database
        .transaction((txn) async {
          final txnCardDao = CardDao(txn);
          final txnPrintingDao = PrintingDao(txn);
          var stepsDone = 0;
          for (var i = 0; i < cards.length; i += _syncWriteChunkSize) {
            await txnCardDao.insertAll(
              cards.sublist(i, min(i + _syncWriteChunkSize, cards.length)),
            );
            stepsDone++;
            writeProgress.add(0.7 + (stepsDone / totalWriteSteps) * 0.3);
          }
          await txnPrintingDao.insertAll(printings);
          stepsDone++;
          writeProgress.add(0.7 + (stepsDone / totalWriteSteps) * 0.3);

          await MetaDao(
            txn,
          ).set('last_sync', DateTime.now().millisecondsSinceEpoch.toString());
          stepsDone++;
          writeProgress.add(0.7 + (stepsDone / totalWriteSteps) * 0.3);
        })
        .whenComplete(writeProgress.close);

    await for (final fraction in writeProgress.stream) {
      yield SyncProgress(fraction, SyncPhase.writing);
    }
    await writeFuture;

    yield const SyncProgress(1, SyncPhase.writing);
  }
}

@riverpod
Future<CardRepository> cardRepository(Ref ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return CardRepository(
    cardDao: CardDao(db),
    printingDao: PrintingDao(db),
    metaDao: MetaDao(db),
    database: db,
  );
}
