import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/repositories/collection_repository.dart';
import '../../data/seed/fake_collection_seed.dart';

part 'statistics_providers.g.dart';

/// A snapshot of collection-wide totals for the statistics screen. Counts are
/// summed quantities (copies), not distinct rows. Breakdown maps are keyed by
/// the stored value — condition/edition db value, language code, `cards.type` —
/// and the screen is responsible for turning those into display labels.
class CollectionStats {
  const CollectionStats({
    required this.totalCopies,
    required this.distinctCards,
    required this.byCondition,
    required this.byLanguage,
    required this.byCardType,
  });

  final int totalCopies;
  final int distinctCards;
  final Map<String, int> byCondition;
  final Map<String, int> byLanguage;
  final Map<String, int> byCardType;
}

@riverpod
Future<CollectionStats> collectionStats(Ref ref) async {
  // Same debug-seed gate the collection list uses, so the screen has data on a
  // fresh debug install before any real sync.
  await ref.watch(debugSeedCollectionProvider.future);
  final repository = await ref.watch(collectionRepositoryProvider.future);

  final results = await Future.wait([
    repository.totalCardCount(),
    repository.distinctCardCount(),
    repository.sumByCondition(),
    repository.sumByLanguage(),
    repository.sumByCardType(),
  ]);

  return CollectionStats(
    totalCopies: results[0] as int,
    distinctCards: results[1] as int,
    byCondition: results[2] as Map<String, int>,
    byLanguage: results[3] as Map<String, int>,
    byCardType: results[4] as Map<String, int>,
  );
}
