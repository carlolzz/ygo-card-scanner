import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sqflite/sqflite.dart';

import '../../models/card_language.dart';
import '../../models/card_search_hit.dart';
import '../../models/printing.dart';
import '../../models/ygo_card.dart';
import '../api/card_image_downloader.dart';
import '../api/ygoprodeck_client.dart';
import '../assets/localized_names.dart';
import '../db/dao/card_dao.dart';
import '../db/dao/card_name_dao.dart';
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

/// Rows per batch when importing the bundled localized names. One transaction
/// either way; this only bounds how large a single batch grows.
const _nameWriteChunkSize = 2000;

class CardRepository {
  CardRepository({
    required this._cardDao,
    required this._printingDao,
    required this._metaDao,
    required this._database,
    YgoProdeckClient? client,
    CardImageDownloader? imageDownloader,
    Future<LocalizedNames> Function(String language)? localizedNamesLoader,
  }) : _client = client ?? YgoProdeckClient(),
       _imageDownloader = imageDownloader ?? CardImageDownloader(),
       _loadLocalizedNames = localizedNamesLoader ?? loadLocalizedNamesAsset;

  final CardDao _cardDao;
  final PrintingDao _printingDao;
  final MetaDao _metaDao;
  final Database _database;
  final YgoProdeckClient _client;
  final CardImageDownloader _imageDownloader;

  /// Injectable so DAO-level tests can exercise [ensureLocalizedNames] without
  /// a `rootBundle` — the same seam shape as [CardImageDownloader] above.
  final Future<LocalizedNames> Function(String language) _loadLocalizedNames;

  Future<YgoCard?> getByPasscode(String passcode) =>
      _cardDao.getByPasscode(passcode);

  Future<List<YgoCard>> getByPasscodes(List<String> passcodes) =>
      _cardDao.getByPasscodes(passcodes);

  Future<List<YgoCard>> searchByName(String query, {int limit = 20}) =>
      _cardDao.searchByName(query, limit: limit);

  /// The single entry point both search screens use.
  ///
  /// English searches `cards.name` as it always has; anything else searches the
  /// bundled `card_names` rows, having first made sure they are loaded. The
  /// language decides which, so neither screen has to know that one of the two
  /// needs an asset behind it.
  Future<List<CardSearchHit>> search(
    String query, {
    String language = kDefaultSearchLanguage,
    int limit = 20,
  }) async {
    if (language == kDefaultSearchLanguage) {
      final cards = await _cardDao.searchByName(query, limit: limit);
      return [for (final card in cards) CardSearchHit(card)];
    }
    await ensureLocalizedNames(language);
    return _cardDao.searchByLocalizedName(
      query,
      language: language,
      limit: limit,
    );
  }

  /// Imports `assets/card_names_<lang>.json` into `card_names`, once.
  ///
  /// Guarded by a `meta` stamp holding the asset's own version, so this costs
  /// one key read on every later call and re-imports only when the asset is
  /// rebuilt. **Not** guarded by a row count: a corrected translation changes
  /// no row count at all.
  ///
  /// Deliberately not called from [sync]. These names come from the APK, not
  /// the network, and `card_names` has no cascade from `cards` precisely so a
  /// re-sync leaves them alone (see migration v5).
  Future<void> ensureLocalizedNames(String language) async {
    final key = _localizedNamesKey(language);
    // The version check comes first, against the *build* constant, so the
    // steady state is one `meta` read — not an asset load and a JSON decode on
    // every keystroke. `parseLocalizedNames` is what keeps the constant and the
    // file honest with each other.
    if (await _metaDao.get(key) == '$kLocalizedNamesVersion') return;
    final loaded = await _loadLocalizedNames(language);
    await _database.transaction((txn) async {
      final dao = CardNameDao(txn);
      for (var i = 0; i < loaded.names.length; i += _nameWriteChunkSize) {
        await dao.insertAll(
          loaded.names.sublist(
            i,
            min(i + _nameWriteChunkSize, loaded.names.length),
          ),
        );
      }
      await MetaDao(txn).set(key, loaded.version.toString());
    });
  }

  String _localizedNamesKey(String language) =>
      'localized_names_${language.toLowerCase()}';

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

  /// When the last successful [sync] finished, or null if none ever has.
  /// Reads the same `last_sync` stamp [needsSync] checks.
  Future<DateTime?> lastSyncedAt() async {
    final stored = await _metaDao.get('last_sync');
    if (stored == null) return null;
    final millis = int.tryParse(stored);
    if (millis == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis);
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
