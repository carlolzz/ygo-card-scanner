import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../models/collection_entry.dart';
import '../../models/collection_entry_with_card.dart';
import '../db/dao/collection_dao.dart';
import '../db/database.dart';

part 'collection_repository.g.dart';

class CollectionRepository {
  CollectionRepository(this._dao);

  final CollectionDao _dao;

  Future<CollectionEntry> addOrIncrement(CollectionEntry entry) =>
      _dao.addOrIncrement(entry);

  Future<void> setQuantity(int id, int quantity) =>
      _dao.setQuantity(id, quantity);

  Future<void> decrement(int id) => _dao.decrement(id);

  Future<void> delete(int id) => _dao.delete(id);

  Future<List<CollectionEntryWithCard>> getAll({
    CollectionFilter filter = const CollectionFilter(),
  }) => _dao.getAll(filter: filter);

  Future<int> totalCardCount() => _dao.totalCardCount();

  Future<int> distinctCardCount() => _dao.distinctCardCount();

  Future<List<CollectionEntry>> getEntriesForPasscode(String passcode) =>
      _dao.getEntriesForPasscode(passcode);
}

@riverpod
Future<CollectionRepository> collectionRepository(Ref ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return CollectionRepository(CollectionDao(db));
}
