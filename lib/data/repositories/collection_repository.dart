import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../models/card_condition.dart';
import '../../models/card_edition.dart';
import '../../models/collection_entry.dart';
import '../../models/collection_entry_with_card.dart';
import '../db/dao/collection_dao.dart';
import '../db/database.dart';
import 'card_repository.dart';

part 'collection_repository.g.dart';

class CollectionRepository {
  CollectionRepository(this._dao, this._cardRepository);

  final CollectionDao _dao;
  final CardRepository _cardRepository;

  Future<CollectionEntry> addOrIncrement(CollectionEntry entry) async {
    final result = await _dao.addOrIncrement(entry);
    unawaited(_cardRepository.ensureImageDownloaded(entry.passcode));
    return result;
  }

  Future<void> setQuantity(int id, int quantity) =>
      _dao.setQuantity(id, quantity);

  Future<void> decrement(int id) => _dao.decrement(id);

  Future<void> delete(int id) => _dao.delete(id);

  /// Edits an entry's printing/condition/edition/language, merging into a
  /// matching entry when the change makes it a duplicate. See
  /// [CollectionDao.updateEntryDetails]. Returns the surviving entry's id.
  Future<int> updateEntryDetails(
    int id, {
    required int? printingId,
    required CardCondition condition,
    required CardEdition edition,
    required String language,
  }) => _dao.updateEntryDetails(
    id,
    printingId: printingId,
    condition: condition,
    edition: edition,
    language: language,
  );

  Future<List<CollectionEntryWithCard>> getAll({
    CollectionFilter filter = const CollectionFilter(),
  }) => _dao.getAll(filter: filter);

  /// The rarity values present in the collection (a null element = "no
  /// rarity"), for the collection filter row's chips.
  Future<List<String?>> rarityFilterOptions() => _dao.rarityFilterOptions();

  /// Every value the collection filter sheet can offer, for its controls.
  Future<CollectionFilterOptions> filterOptions() => _dao.filterOptions();

  Future<int> totalCardCount() => _dao.totalCardCount();

  Future<int> distinctCardCount() => _dao.distinctCardCount();

  Future<Map<String, int>> sumByCondition() => _dao.sumByCondition();

  Future<Map<String, int>> sumByLanguage() => _dao.sumByLanguage();

  Future<Map<String, int>> sumByCardType() => _dao.sumByCardType();

  Future<List<CollectionEntry>> getEntriesForPasscode(String passcode) =>
      _dao.getEntriesForPasscode(passcode);
}

@riverpod
Future<CollectionRepository> collectionRepository(Ref ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final cardRepository = await ref.watch(cardRepositoryProvider.future);
  return CollectionRepository(CollectionDao(db), cardRepository);
}
