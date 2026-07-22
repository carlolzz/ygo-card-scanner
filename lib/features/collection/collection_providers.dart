import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/db/dao/collection_dao.dart';
import '../../data/repositories/collection_repository.dart';
import '../../data/seed/fake_collection_seed.dart';
import '../../models/card_condition.dart';
import '../../models/card_edition.dart';
import '../../models/collection_entry_with_card.dart';

part 'collection_providers.g.dart';

@riverpod
class CollectionFilterController extends _$CollectionFilterController {
  @override
  CollectionFilter build() => const CollectionFilter();

  void setNameQuery(String query) {
    state = CollectionFilter(
      nameQuery: query.isEmpty ? null : query,
      condition: state.condition,
      edition: state.edition,
      sortBy: state.sortBy,
      sortDescending: state.sortDescending,
    );
  }

  void setCondition(CardCondition? condition) {
    state = CollectionFilter(
      nameQuery: state.nameQuery,
      condition: condition,
      edition: state.edition,
      sortBy: state.sortBy,
      sortDescending: state.sortDescending,
    );
  }

  void setEdition(CardEdition? edition) {
    state = CollectionFilter(
      nameQuery: state.nameQuery,
      condition: state.condition,
      edition: edition,
      sortBy: state.sortBy,
      sortDescending: state.sortDescending,
    );
  }

  void setSortBy(CollectionSortBy sortBy) {
    state = CollectionFilter(
      nameQuery: state.nameQuery,
      condition: state.condition,
      edition: state.edition,
      sortBy: sortBy,
      sortDescending: state.sortDescending,
    );
  }

  void toggleSortDirection() {
    state = CollectionFilter(
      nameQuery: state.nameQuery,
      condition: state.condition,
      edition: state.edition,
      sortBy: state.sortBy,
      sortDescending: !state.sortDescending,
    );
  }
}

@riverpod
Future<List<CollectionEntryWithCard>> collectionEntries(Ref ref) async {
  await ref.watch(debugSeedCollectionProvider.future);
  final filter = ref.watch(collectionFilterControllerProvider);
  final repository = await ref.watch(collectionRepositoryProvider.future);
  return repository.getAll(filter: filter);
}
