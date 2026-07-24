import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/db/dao/collection_dao.dart';
import '../../data/repositories/card_repository.dart';
import '../../data/repositories/collection_repository.dart';
import '../../data/seed/fake_collection_seed.dart';
import '../../models/card_condition.dart';
import '../../models/card_edition.dart';
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
