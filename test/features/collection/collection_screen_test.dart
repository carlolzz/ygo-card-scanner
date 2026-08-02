import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ygo_scanner/core/constants.dart';
import 'package:ygo_scanner/data/seed/fake_collection_seed.dart';
import 'package:ygo_scanner/features/collection/collection_grid_tile.dart';
import 'package:ygo_scanner/features/collection/collection_list_tile.dart';
import 'package:ygo_scanner/models/collection_view_mode.dart';
import 'package:ygo_scanner/shared/widgets/card_thumbnail.dart';

import '../../data/db/test_db.dart';
import '../../support/widget_test_harness.dart';

void main() {
  late Database testDb;

  setUp(() async {
    testDb = await openInMemoryTestDb();
    await seedFakeCollectionIfEmpty(testDb);
  });

  tearDown(() async {
    await testDb.close();
  });

  Future<void> openCollection(WidgetTester tester) async {
    await pumpApp(tester, testDb);
    await tester.tap(find.text(AppStrings.homeTileMyCollection));
    await pumpUntilSettled(tester);
  }

  /// Opens the filter sheet, taps one chip by label, and applies.
  ///
  /// The filters used to be two chip rows on the screen itself; they are now
  /// behind a button, and the sheet edits a **local draft** that only reaches
  /// the list on Apply — so a test that merely taps a chip would assert against
  /// an unchanged list and pass or fail for the wrong reason.
  Future<void> applyFilterChip(WidgetTester tester, String label) async {
    await tester.tap(find.text(AppStrings.collectionFiltersButton));
    await pumpUntilSettled(tester);

    final chip = find.widgetWithText(ChoiceChip, label);
    await tester.ensureVisible(chip.first);
    await pumpUntilSettled(tester);
    await tester.tap(chip.first);
    await pumpUntilSettled(tester);

    await tester.tap(find.text(AppStrings.collectionFiltersApply));
    await pumpUntilSettled(tester);
  }

  testWidgets('shows all seeded cards', (tester) async {
    // Tall enough that all six seeded rows (Mirror Force now seeds two)
    // render without needing to scroll a lazy ListView into view.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.runAsync(() async {
      await openCollection(tester);

      expect(find.text('Blue-Eyes White Dragon'), findsOneWidget);
      expect(find.text('Dark Magician'), findsOneWidget);
      expect(find.text('Red-Eyes B. Dragon'), findsOneWidget);
      // Two rows: Mirror Force is seeded with two distinct printings.
      expect(find.text('Mirror Force'), findsNWidgets(2));
      expect(find.text('Pot of Greed'), findsOneWidget);
    });
  });

  testWidgets('search narrows the list by name', (tester) async {
    await tester.runAsync(() async {
      await openCollection(tester);

      await tester.enterText(find.byType(TextField), 'Dark');
      await pumpUntilSettled(tester);

      expect(find.text('Dark Magician'), findsOneWidget);
      expect(find.text('Blue-Eyes White Dragon'), findsNothing);
    });
  });

  testWidgets('condition chip narrows the list', (tester) async {
    await tester.runAsync(() async {
      await openCollection(tester);

      await applyFilterChip(tester, 'LP');

      expect(find.text('Red-Eyes B. Dragon'), findsOneWidget);
      expect(find.text('Dark Magician'), findsNothing);
    });
  });

  testWidgets('rarity chip narrows the list', (tester) async {
    await tester.runAsync(() async {
      await openCollection(tester);

      // Only the Metal Raiders printing of Mirror Force is Super Rare; the
      // Dark Saviors one is Ultra Rare, so one of the two rows survives.
      await applyFilterChip(tester, 'Super Rare');

      expect(find.text('Mirror Force'), findsOneWidget);
      expect(find.text('Blue-Eyes White Dragon'), findsNothing);
    });
  });

  testWidgets('the "No rarity" chip finds cards logged without a printing', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await openCollection(tester);

      await applyFilterChip(tester, AppStrings.collectionFilterNoRarity);

      // The seeded Dark Magician and Pot of Greed carry no printing.
      expect(find.text('Dark Magician'), findsOneWidget);
      expect(find.text('Pot of Greed'), findsOneWidget);
      expect(find.text('Blue-Eyes White Dragon'), findsNothing);
    });
  });

  testWidgets('a tile shows the set and the rarity, not the edition', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.runAsync(() async {
      await openCollection(tester);

      final tile = find.ancestor(
        of: find.text('Blue-Eyes White Dragon'),
        matching: find.byType(CollectionListTile),
      );
      expect(
        find.descendant(of: tile, matching: find.text('LOB-EN001')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: tile, matching: find.text('Ultra Rare')),
        findsOneWidget,
      );
      // The edition moved to the detail screen.
      expect(
        find.descendant(of: tile, matching: find.text('1st Edition')),
        findsNothing,
      );
    });
  });

  testWidgets('incrementing quantity updates the displayed count', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await openCollection(tester);

      final tile = find.ancestor(
        of: find.text('Dark Magician'),
        matching: find.byType(CollectionListTile),
      );
      expect(
        find.descendant(of: tile, matching: find.text('1')),
        findsOneWidget,
      );

      await tester.tap(
        find.descendant(
          of: tile,
          matching: find.byIcon(Icons.add_circle_outline),
        ),
      );
      await pumpUntilSettled(tester);

      expect(
        find.descendant(of: tile, matching: find.text('2')),
        findsOneWidget,
      );
    });
  });

  testWidgets('decrementing quantity to zero removes the row after confirming', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await openCollection(tester);

      final tile = find.ancestor(
        of: find.text('Dark Magician'),
        matching: find.byType(CollectionListTile),
      );
      await tester.tap(
        find.descendant(
          of: tile,
          matching: find.byIcon(Icons.remove_circle_outline),
        ),
      );
      await pumpUntilSettled(tester);

      // Removing the last copy is a deletion — the confirmation dialog is on by
      // default. The row is still there until the user confirms.
      expect(find.text(AppStrings.collectionDeleteDialogTitle), findsOneWidget);
      expect(find.text('Dark Magician'), findsWidgets);

      await tester.tap(find.text(AppStrings.collectionDeleteDialogConfirm));
      await pumpUntilSettled(tester);

      expect(find.text('Dark Magician'), findsNothing);
    });
  });

  testWidgets('tapping a tile opens the detail screen', (tester) async {
    await tester.runAsync(() async {
      await openCollection(tester);

      await tester.tap(find.text('Dark Magician'));
      await pumpUntilSettled(tester);

      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Dark Magician'),
        ),
        findsOneWidget,
      );
      expect(find.byType(CardThumbnail), findsOneWidget);
    });
  });

  testWidgets('a card thumbnail renders in every list tile', (tester) async {
    // Tall enough that all six seeded rows render without needing to
    // scroll a lazy ListView into view (see the identical setup above).
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.runAsync(() async {
      await openCollection(tester);

      expect(
        find.byType(CardThumbnail),
        findsNWidgets(6), // one per seeded row
      );
    });
  });

  testWidgets(
    'incrementing on the detail screen is reflected back on the list',
    (tester) async {
      await tester.runAsync(() async {
        await openCollection(tester);

        await tester.tap(find.text('Dark Magician'));
        await pumpUntilSettled(tester);

        // The card thumbnail at the top of the detail screen can push the
        // quantity controls below the fold — scroll them into view first,
        // exactly as a real user would.
        await tester.ensureVisible(find.byIcon(Icons.add_circle_outline));
        await pumpUntilSettled(tester);
        await tester.tap(find.byIcon(Icons.add_circle_outline));
        await pumpUntilSettled(tester);

        await tester.pageBack();
        await pumpUntilSettled(tester);

        final tile = find.ancestor(
          of: find.text('Dark Magician'),
          matching: find.byType(CollectionListTile),
        );
        expect(
          find.descendant(of: tile, matching: find.text('2')),
          findsOneWidget,
        );
      });
    },
  );

  group('minify view modes', () {
    /// Picks a density from the view menu next to the filter button.
    Future<void> selectViewMode(
      WidgetTester tester,
      CollectionViewMode mode,
    ) async {
      await tester.tap(find.text(AppStrings.collectionMinifyButton));
      await pumpUntilSettled(tester);
      await tester.tap(find.text(mode.label).last);
      await pumpUntilSettled(tester);
    }

    testWidgets('standard is the default and renders full rows', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await openCollection(tester);

        expect(find.byType(CollectionListTile), findsWidgets);
        expect(find.byType(CollectionGridTile), findsNothing);
      });
    });

    testWidgets('artwork + name swaps the list for a captioned grid', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await openCollection(tester);
        await selectViewMode(tester, CollectionViewMode.minifyStandard);

        expect(find.byType(CollectionListTile), findsNothing);
        expect(find.byType(CollectionGridTile), findsWidgets);
        // Names are still captioned in this mode.
        expect(find.text('Dark Magician'), findsOneWidget);
      });
    });

    testWidgets('artwork only drops the names', (tester) async {
      await tester.runAsync(() async {
        await openCollection(tester);
        await selectViewMode(tester, CollectionViewMode.minifyFull);

        expect(find.byType(CollectionGridTile), findsWidgets);
        expect(find.text('Dark Magician'), findsNothing);
      });
    });

    testWidgets('a minified cell keeps the quantity, which has no control '
        'to show it otherwise', (tester) async {
      await tester.runAsync(() async {
        await openCollection(tester);
        await selectViewMode(tester, CollectionViewMode.minifyFull);

        // Blue-Eyes is seeded with two copies; Dark Magician with one, so only
        // the former gets a badge.
        expect(find.text('x2'), findsOneWidget);
        expect(find.text('x1'), findsNothing);
      });
    });

    testWidgets('the chosen mode is persisted', (tester) async {
      await tester.runAsync(() async {
        await openCollection(tester);
        await selectViewMode(tester, CollectionViewMode.minifyFull);

        // Leave the screen and come back: the setting lives in `meta`, not in
        // widget state, so the grid must survive a rebuild of the screen.
        await tester.pageBack();
        await pumpUntilSettled(tester);
        await tester.tap(find.text(AppStrings.homeTileMyCollection));
        await pumpUntilSettled(tester);

        expect(find.byType(CollectionGridTile), findsWidgets);
        expect(find.byType(CollectionListTile), findsNothing);
      });
    });
  });

  testWidgets('an advanced filter narrows the list', (tester) async {
    await tester.runAsync(() async {
      await openCollection(tester);

      await tester.tap(find.text(AppStrings.collectionFiltersButton));
      await pumpUntilSettled(tester);

      // The advanced group is behind a tick box, below the basic groups and so
      // below the fold in the default test viewport.
      final advanced = find.text(AppStrings.collectionFiltersAdvanced);
      await tester.ensureVisible(advanced);
      await pumpUntilSettled(tester);
      await tester.tap(advanced);
      await pumpUntilSettled(tester);

      final chip = find.widgetWithText(ChoiceChip, 'LIGHT');
      await tester.ensureVisible(chip);
      await pumpUntilSettled(tester);
      await tester.tap(chip);
      await pumpUntilSettled(tester);

      await tester.tap(find.text(AppStrings.collectionFiltersApply));
      await pumpUntilSettled(tester);

      // Only Blue-Eyes is LIGHT in the seed.
      expect(find.text('Blue-Eyes White Dragon'), findsOneWidget);
      expect(find.text('Dark Magician'), findsNothing);
    });
  });

  testWidgets('the filter button counts what is active', (tester) async {
    await tester.runAsync(() async {
      await openCollection(tester);

      // With the controls hidden behind a button, the count is the only thing
      // that says the list is narrowed at all.
      expect(find.text(AppStrings.collectionFiltersButton), findsOneWidget);

      await applyFilterChip(tester, 'LP');

      expect(find.text('${AppStrings.collectionFiltersButton} (1)'),
          findsOneWidget);
    });
  });
}
