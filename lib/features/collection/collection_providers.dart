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
    state = state.copyWith(
      nameQuery: query.isEmpty ? null : query,
      clearNameQuery: query.isEmpty,
    );
  }

  /// Replaces every filter at once — the filter sheet edits a local draft and
  /// applies it in one go, so the list is queried once per Apply rather than on
  /// every chip tap behind a sheet that covers it.
  void apply(CollectionFilter filter) => state = filter;

  void setCondition(CardCondition? condition) => state = state.copyWith(
    condition: condition,
    clearCondition: condition == null,
  );

  /// Null clears the rarity filter ("All").
  void setRarity(RarityFilter? rarity) =>
      state = state.copyWith(rarity: rarity, clearRarity: rarity == null);

  void setSortBy(CollectionSortBy sortBy) =>
      state = state.copyWith(sortBy: sortBy);

  void toggleSortDirection() =>
      state = state.copyWith(sortDescending: !state.sortDescending);
}

/// Which collection entries are selected, and whether the screen is in
/// selection mode at all.
///
/// A hand-written immutable class rather than freezed, matching
/// `AddCardSelection` and `ScanState`: it is UI state, not a DB row.
class CollectionSelection {
  const CollectionSelection({this.active = false, this.ids = const <int>{}});

  /// Whether the list is in selection mode. True with an empty [ids] is a real
  /// state — the user deselected everything without leaving the mode.
  final bool active;

  /// `collection_entries.id`, the only stable key here: one passcode backs
  /// several rows (conditions, languages, printings) and selecting a card means
  /// selecting exactly one of them.
  final Set<int> ids;

  int get count => ids.length;
  bool contains(int? id) => id != null && ids.contains(id);
}

/// Owns [CollectionSelection] for the collection screen.
///
/// autoDispose, and unlike the scan pause this genuinely dies with its screen:
/// `CollectionScreen` **watches** it, so there is a real subscription holding it
/// up rather than a pair of `ref.read`s that close immediately.
@riverpod
class CollectionSelectionController extends _$CollectionSelectionController {
  @override
  CollectionSelection build() {
    // Watching the filter *is* the clearing rule. Any change to the filter or
    // the search box rebuilds this notifier back to empty and inactive — which
    // matters because a row filtered out of the list would otherwise stay
    // selected invisibly and be swept up by a delete button whose count never
    // showed it. That is the one way this feature could destroy data the user
    // did not choose.
    ref.watch(collectionFilterControllerProvider);
    return const CollectionSelection();
  }

  /// Enters selection mode with one card picked — the long-press.
  void enter(int id) => state = CollectionSelection(active: true, ids: {id});

  void toggle(int id) {
    final next = Set<int>.of(state.ids);
    if (!next.remove(id)) next.add(id);
    // Deselecting the last card keeps the mode on: leaving it would fight the
    // user, who is one tap away from picking a different card.
    state = CollectionSelection(active: true, ids: next);
  }

  void selectAll(Iterable<int> ids) =>
      state = CollectionSelection(active: true, ids: ids.toSet());

  void clearSelection() => state = const CollectionSelection(active: true);

  void exit() => state = const CollectionSelection();
}

@riverpod
Future<List<CollectionEntryWithCard>> collectionEntries(Ref ref) async {
  await ref.watch(debugSeedCollectionProvider.future);
  final filter = ref.watch(collectionFilterControllerProvider);
  final repository = await ref.watch(collectionRepositoryProvider.future);
  return repository.getAll(filter: filter);
}

/// Every value the filter sheet's controls can offer — rarities, sets,
/// languages, card types, frame types, races, attributes, archetypes, levels.
///
/// Deliberately **not** derived from [collectionEntries], even though it is a
/// projection of the same rows. Chaining one async provider onto another that is
/// invalidated mid route-transition makes Riverpod schedule a scope refresh from
/// inside a build ("setState() called during build"), which is a real defect and
/// not merely a test artifact. Instead the mutation sites invalidate this
/// alongside `collectionEntriesProvider` — but only those that can change *which
/// values are held* (add, edit, delete, re-sync); a plain quantity change cannot.
///
/// The query is also deliberately unfiltered: the sheet must offer every value
/// in the collection, not just those surviving the filter currently applied, or
/// narrowing once would strand the user with no way back.
///
/// Waits on the debug seed for the same reason [collectionEntries] does — it can
/// otherwise run before the fixtures have been written.
///
/// This replaced a rarity-only provider when the two chip rows below the search
/// box became one sheet: nine separate options providers would have meant nine
/// invalidation sites for the same event, and the invalidation is the subtle
/// part.
@riverpod
Future<CollectionFilterOptions> collectionFilterOptions(Ref ref) async {
  await ref.watch(debugSeedCollectionProvider.future);
  final repository = await ref.watch(collectionRepositoryProvider.future);
  return repository.filterOptions();
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
