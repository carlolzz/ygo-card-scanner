import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/db/dao/collection_dao.dart';
import '../../data/repositories/card_repository.dart';
import '../../data/repositories/collection_repository.dart';
import '../../data/seed/fake_collection_seed.dart';
import '../../models/app_settings.dart';
import '../../models/card_condition.dart';
import '../../models/card_language.dart';
import '../../models/collection_entry.dart';
import '../../models/collection_entry_with_card.dart';
import '../../models/printing.dart';
import '../settings/settings_providers.dart';

part 'collection_providers.g.dart';

@riverpod
class CollectionFilterController extends _$CollectionFilterController {
  /// The filters themselves start empty on every visit — a filter *hides* cards,
  /// and a collection still narrowed from last week reads as lost data. The sort
  /// is the exception: it only reorders what is already all there, so it is
  /// restored from settings, which is what stops a trip to the home menu (this
  /// notifier is autoDispose) putting the list back in name order.
  ///
  /// `ref.read`, not `watch`, deliberately — matching `ScanController` and
  /// `AddCardSelectionController`. Watching would rebuild this notifier on the
  /// write-through in [setSortBy] and so wipe every other filter the user had
  /// applied. `App` gates routing on settings resolving, so `.value` is
  /// non-null here in practice; the fallback is what the screen rendered before
  /// this was persisted.
  @override
  CollectionFilter build() {
    final settings =
        ref.read(settingsControllerProvider).value ?? const AppSettings();
    return CollectionFilter(
      sortBy: settings.collectionSortBy,
      sortDescending: settings.collectionSortDescending,
    );
  }

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

  /// Both sort controls publish immediately and persist in the background: the
  /// list must reorder on the tap, and a failed write is not worth blocking or
  /// reverting a reorder the user can simply repeat. [SettingsController] itself
  /// still writes before it publishes, so its own state never claims a
  /// preference the database doesn't hold.
  void setSortBy(CollectionSortBy sortBy) {
    state = state.copyWith(sortBy: sortBy);
    unawaited(
      ref.read(settingsControllerProvider.notifier).setCollectionSortBy(sortBy),
    );
  }

  void toggleSortDirection() {
    final descending = !state.sortDescending;
    state = state.copyWith(sortDescending: descending);
    unawaited(
      ref
          .read(settingsControllerProvider.notifier)
          .setCollectionSortDescending(descending),
    );
  }
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

/// The collection list, narrowed by the filter and matched in the language the
/// app-bar picker selects.
///
/// The language is `searchLanguageProvider`, the same persisted preference the
/// two card-search screens read, rather than a field on [CollectionFilter]:
/// one value, one source of truth. It is **watched** here (unlike the sort,
/// which [CollectionFilterController] reads once at build) because the language
/// is a search input, not a starting position.
@riverpod
Future<List<CollectionEntryWithCard>> collectionEntries(Ref ref) async {
  await ref.watch(debugSeedCollectionProvider.future);
  final filter = ref.watch(collectionFilterControllerProvider);
  final language = ref.watch(searchLanguageProvider);
  final repository = await ref.watch(collectionRepositoryProvider.future);

  var nameLanguage = language;
  final query = filter.nameQuery;
  // Gated on there being a query at all: the first run of
  // `ensureLocalizedNames` decodes a 435 KB asset and inserts ~11.6k rows, and
  // merely picking a language must not pay for it.
  if (language != kDefaultSearchLanguage && query != null && query.isNotEmpty) {
    try {
      final cards = await ref.watch(cardRepositoryProvider.future);
      await cards.ensureLocalizedNames(language);
    } catch (_) {
      // Degrade to English rather than blanking the collection. The OR in
      // `CollectionDao.getAll` means every owned card is still findable by its
      // English name, so a missing or malformed asset costs reach, not the
      // list. A card *search* can surface that failure; the collection is the
      // wrong screen to report it on.
      nameLanguage = kDefaultSearchLanguage;
    }
  }
  return repository.getAll(filter: filter, nameLanguage: nameLanguage);
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

/// One `collection_entries` row with the printing it points at, for the detail
/// screen's Copies tab.
class OwnedCopy {
  const OwnedCopy({required this.entry, this.printing});

  final CollectionEntry entry;

  /// Null when the copy was logged without a set.
  final Printing? printing;
}

/// [copies] best grade first, then by set code with no set last, then by
/// language: the order a person reads a stack of duplicates in. A copy, so the
/// caller's list is left alone.
List<OwnedCopy> sortOwnedCopies(List<OwnedCopy> copies) => [...copies]
  ..sort((a, b) {
    final byCondition = a.entry.condition.sortOrder.compareTo(
      b.entry.condition.sortOrder,
    );
    if (byCondition != 0) return byCondition;
    final aSet = a.printing?.setCode;
    final bSet = b.printing?.setCode;
    if (aSet != bSet) {
      if (aSet == null) return 1;
      if (bSet == null) return -1;
      return aSet.compareTo(bSet);
    }
    return a.entry.language.compareTo(b.entry.language);
  });

/// Every copy held of one card (passcode), across languages, conditions and
/// printings, for the detail screen's Copies tab.
///
/// Composes two existing repository reads by id, so there is no new SQL. It reads
/// the repositories directly rather than watching [cardPrintings], because
/// chaining one async provider onto another that is invalidated mid
/// route-transition schedules a scope refresh from inside a build (see
/// [collectionFilterOptions]). A quantity change must invalidate this, or the tab
/// goes on showing the old count.
@riverpod
Future<List<OwnedCopy>> ownedCopies(Ref ref, String passcode) async {
  final collection = await ref.watch(collectionRepositoryProvider.future);
  final cards = await ref.watch(cardRepositoryProvider.future);
  final entries = await collection.getEntriesForPasscode(passcode);
  final printings = await cards.getPrintingsForPasscode(passcode);
  final printingsById = {for (final p in printings) p.id: p};
  return sortOwnedCopies([
    for (final entry in entries)
      OwnedCopy(entry: entry, printing: printingsById[entry.printingId]),
  ]);
}

/// The known printings (set + rarity) for a card, for the detail screen's
/// edit sheet. Reuses [CardRepository.getPrintingsForPasscode] so the widget
/// stays off the DAO.
@riverpod
Future<List<Printing>> cardPrintings(Ref ref, String passcode) async {
  final repository = await ref.watch(cardRepositoryProvider.future);
  return repository.getPrintingsForPasscode(passcode);
}
