import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/db/dao/collection_dao.dart';
import '../../data/repositories/card_repository.dart';
import '../../data/repositories/collection_repository.dart';
import '../../data/seed/fake_collection_seed.dart';
import '../../models/card_condition.dart';
import '../../models/collection_entry.dart';
import '../../models/collection_entry_with_card.dart';
import '../../models/printing.dart';

part 'collection_providers.g.dart';

@riverpod
class CollectionFilterController extends _$CollectionFilterController {
  @override
  CollectionFilter build() => const CollectionFilter();

  void setNameQuery(String query) {
    state = CollectionFilter(
      nameQuery: query.isEmpty ? null : query,
      condition: state.condition,
      rarity: state.rarity,
      sortBy: state.sortBy,
      sortDescending: state.sortDescending,
    );
  }

  void setCondition(CardCondition? condition) {
    state = CollectionFilter(
      nameQuery: state.nameQuery,
      condition: condition,
      rarity: state.rarity,
      sortBy: state.sortBy,
      sortDescending: state.sortDescending,
    );
  }

  /// Null clears the rarity filter ("All").
  void setRarity(RarityFilter? rarity) {
    state = CollectionFilter(
      nameQuery: state.nameQuery,
      condition: state.condition,
      rarity: rarity,
      sortBy: state.sortBy,
      sortDescending: state.sortDescending,
    );
  }

  void setSortBy(CollectionSortBy sortBy) {
    state = CollectionFilter(
      nameQuery: state.nameQuery,
      condition: state.condition,
      rarity: state.rarity,
      sortBy: sortBy,
      sortDescending: state.sortDescending,
    );
  }

  void toggleSortDirection() {
    state = CollectionFilter(
      nameQuery: state.nameQuery,
      condition: state.condition,
      rarity: state.rarity,
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

/// The rarity values held in the collection, for the filter row's chips — a
/// null element means "no rarity" (see [CollectionDao.rarityFilterOptions]).
///
/// Deliberately **not** derived from [collectionEntries], even though it is a
/// projection of the same rows. Chaining one async provider onto another that is
/// invalidated mid route-transition makes Riverpod schedule a scope refresh from
/// inside a build ("setState() called during build"), which is a real defect and
/// not merely a test artifact. Instead the mutation sites invalidate this
/// alongside `collectionEntriesProvider` — but only those that can change *which
/// printings are held* (add, edit, delete); a plain quantity change cannot.
///
/// The query is also deliberately unfiltered: the chips must offer every rarity
/// in the collection, not just those surviving the current filter.
///
/// Waits on the debug seed for the same reason [collectionEntries] does — it can
/// otherwise run before the fixtures have been written.
@riverpod
Future<List<String?>> collectionRarityOptions(Ref ref) async {
  await ref.watch(debugSeedCollectionProvider.future);
  final repository = await ref.watch(collectionRepositoryProvider.future);
  return repository.rarityFilterOptions();
}

/// Every collection entry for one card (passcode), across languages, conditions
/// and printings — the source for the detail screen's per-language breakdown.
/// Reuses the existing `getEntriesForPasscode` passthrough; no new SQL.
@riverpod
Future<List<CollectionEntry>> entriesForPasscode(
  Ref ref,
  String passcode,
) async {
  final repository = await ref.watch(collectionRepositoryProvider.future);
  return repository.getEntriesForPasscode(passcode);
}

/// The known printings (set + rarity) for a card, for the detail screen's
/// edit sheet. Reuses [CardRepository.getPrintingsForPasscode] so the widget
/// stays off the DAO.
@riverpod
Future<List<Printing>> cardPrintings(Ref ref, String passcode) async {
  final repository = await ref.watch(cardRepositoryProvider.future);
  return repository.getPrintingsForPasscode(passcode);
}
