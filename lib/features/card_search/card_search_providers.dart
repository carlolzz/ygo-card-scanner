import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/repositories/card_repository.dart';
import '../../data/seed/fake_collection_seed.dart';
import '../../models/card_search_hit.dart';
import '../settings/settings_providers.dart';

part 'card_search_providers.g.dart';

/// How many results the browse screen shows.
///
/// Larger than the add-card wizard's default of 20: that list exists to pick
/// one card and get on with logging it, while this one is for reading, where
/// scrolling past the exact match to see what else shares a name is the point.
const int kCardSearchLimit = 50;

/// The query typed into the card-search field.
///
/// Its own controller rather than widget state, matching
/// `AddCardQueryController` — the results provider watches it, so it has to
/// live where a provider can see it. No debounce, also matching that one:
/// `CardDao.searchByName` is a single indexed query on a local database.
@riverpod
class CardSearchQueryController extends _$CardSearchQueryController {
  @override
  String build() => '';

  void setQuery(String query) => state = query;
}

/// Cards matching the current query, across the whole synced database.
///
/// The `debugSeedCollectionProvider` await is not optional: any provider that
/// reads from the database has to wait for the debug seed, or it can run before
/// the fixtures are in place when this screen is the first one opened. See
/// `addCardSearchResults`, which carries the same guard for the same reason.
@riverpod
Future<List<CardSearchHit>> cardSearchResults(Ref ref) async {
  await ref.watch(debugSeedCollectionProvider.future);
  final query = ref.watch(cardSearchQueryControllerProvider);
  if (query.isEmpty) return const [];
  // `watch`, not `read`: the language is a search input, so changing it must
  // re-run the query — unlike the *default* condition/edition/language, which
  // are read once so a mid-flight change can't disturb a card being logged.
  final language = ref.watch(searchLanguageProvider);
  final repository = await ref.watch(cardRepositoryProvider.future);
  return repository.search(query, language: language, limit: kCardSearchLimit);
}
