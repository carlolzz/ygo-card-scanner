import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ygo_scanner/data/db/database.dart';
import 'package:ygo_scanner/features/collection/collection_providers.dart';
import 'package:ygo_scanner/features/settings/settings_providers.dart';
import 'package:ygo_scanner/models/collection_sort_by.dart';

import '../../data/db/test_db.dart';

/// The collection's sort order is a persisted preference, unlike the rest of the
/// filter. `CollectionFilterController` is autoDispose, so leaving the screen for
/// the home menu tears it down — which used to put the list back in name order.
void main() {
  late Database db;

  setUp(() async {
    db = await openInMemoryTestDb();
  });

  tearDown(() async {
    await db.close();
  });

  /// A container wired to [db], with settings already resolved — `App` gates
  /// routing on exactly that, so it is the state the collection screen is
  /// always built in.
  Future<ProviderContainer> openContainer() async {
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWith((ref) async => db)],
    );
    addTearDown(container.dispose);
    await container.read(settingsControllerProvider.future);
    return container;
  }

  /// The sort setters publish immediately and persist in the background, so the
  /// write needs real wall-clock time (sqflite_common_ffi answers on a
  /// background isolate).
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 50));

  test(
    'the chosen sort survives the filter controller being disposed',
    () async {
      final container = await openContainer();

      // A live subscription, so the autoDispose notifier is actually held up and
      // closing it is a genuine teardown rather than a no-op.
      var sub = container.listen(collectionFilterControllerProvider, (_, _) {});
      container
          .read(collectionFilterControllerProvider.notifier)
          .setSortBy(CollectionSortBy.quantity);
      container
          .read(collectionFilterControllerProvider.notifier)
          .toggleSortDirection();
      await settle();

      // Leaving the collection screen.
      sub.close();
      await settle();

      // Coming back to it.
      sub = container.listen(collectionFilterControllerProvider, (_, _) {});
      final filter = container.read(collectionFilterControllerProvider);
      expect(filter.sortBy, CollectionSortBy.quantity);
      expect(filter.sortDescending, isTrue);
    },
  );

  test('the chosen sort survives an app restart', () async {
    final first = await openContainer();
    final sub = first.listen(collectionFilterControllerProvider, (_, _) {});
    first
        .read(collectionFilterControllerProvider.notifier)
        .setSortBy(CollectionSortBy.dateAdded);
    await settle();
    sub.close();
    first.dispose();

    // A second container over the same database: nothing is carried in memory,
    // so this reads the preference back out of `meta`.
    final second = await openContainer();
    final filter = second.read(collectionFilterControllerProvider);
    expect(filter.sortBy, CollectionSortBy.dateAdded);
  });

  test('changing the sort does not clear the other filters', () async {
    // The write-through goes through `SettingsController`. If this notifier
    // *watched* settings rather than reading them, that write would rebuild it
    // and silently drop every filter the user had applied.
    final container = await openContainer();
    final sub = container.listen(collectionFilterControllerProvider, (_, _) {});
    addTearDown(sub.close);

    final notifier = container.read(
      collectionFilterControllerProvider.notifier,
    );
    notifier.setNameQuery('Dark');
    notifier.setSortBy(CollectionSortBy.cardType);
    await settle();

    final filter = container.read(collectionFilterControllerProvider);
    expect(filter.sortBy, CollectionSortBy.cardType);
    expect(filter.nameQuery, 'Dark');
  });

  test('the filters themselves are not persisted', () async {
    // Only the sort is. A filter hides cards, and a collection still narrowed
    // on the next visit reads as lost data.
    final container = await openContainer();
    var sub = container.listen(collectionFilterControllerProvider, (_, _) {});
    container
        .read(collectionFilterControllerProvider.notifier)
        .setNameQuery('Dark');
    await settle();
    sub.close();
    await settle();

    sub = container.listen(collectionFilterControllerProvider, (_, _) {});
    addTearDown(sub.close);
    expect(
      container.read(collectionFilterControllerProvider).nameQuery,
      isNull,
    );
  });
}
