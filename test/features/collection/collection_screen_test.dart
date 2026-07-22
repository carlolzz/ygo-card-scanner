import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ygo_scanner/core/constants.dart';
import 'package:ygo_scanner/data/seed/fake_collection_seed.dart';
import 'package:ygo_scanner/features/collection/collection_list_tile.dart';
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

      await tester.tap(find.widgetWithText(ChoiceChip, 'LP'));
      await pumpUntilSettled(tester);

      expect(find.text('Red-Eyes B. Dragon'), findsOneWidget);
      expect(find.text('Dark Magician'), findsNothing);
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

  testWidgets('decrementing quantity to zero removes the row', (
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
}
