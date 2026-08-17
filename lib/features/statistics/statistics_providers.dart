import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/repositories/collection_repository.dart';
import '../../data/repositories/price_repository.dart';
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

enum CollectionValueStatus { running, success, failure }

/// What the collection-value section is showing. Null state means "not asked
/// yet" — the button, not a total of zero.
class CollectionValueState {
  const CollectionValueState({
    required this.status,
    this.done = 0,
    this.total = 0,
    this.value,
    this.error,
  });

  final CollectionValueStatus status;

  /// Distinct passcodes priced so far, and how many there are. Real counts
  /// rather than a fraction because this can be a dozen sequential requests,
  /// and "Priced 120 / 340 cards" tells the user whether to wait.
  final int done;
  final int total;

  final CollectionValue? value;
  final Object? error;
}

/// Values the collection on demand, reporting progress inline.
///
/// Shaped like `ResyncController` and for the same reasons: a nullable state so
/// "not run yet" is distinct from "ran and produced nothing", progress on the
/// state rather than a stream, and a **non-blocking** failure — the user can
/// simply walk away from a price fetch, unlike the first-launch sync gate.
///
/// Deliberately not a plain `FutureProvider`: this must never run because a
/// screen was opened. It is a burst of network requests, and it happens when
/// the user asks for it.
@riverpod
class CollectionValueController extends _$CollectionValueController {
  @override
  CollectionValueState? build() => null;

  Future<void> calculate({bool forceRefresh = false}) async {
    state = const CollectionValueState(status: CollectionValueStatus.running);
    try {
      final repository = await ref.read(priceRepositoryProvider.future);
      final value = await repository.collectionValue(
        forceRefresh: forceRefresh,
        onProgress: (done, total) => state = CollectionValueState(
          status: CollectionValueStatus.running,
          done: done,
          total: total,
        ),
      );
      state = CollectionValueState(
        status: CollectionValueStatus.success,
        done: value.pricedCards + value.unpricedCards,
        total: value.pricedCards + value.unpricedCards,
        value: value,
      );
    } catch (e) {
      state = CollectionValueState(
        status: CollectionValueStatus.failure,
        error: e,
      );
    }
  }
}
