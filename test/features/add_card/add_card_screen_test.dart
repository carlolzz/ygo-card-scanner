import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ygo_scanner/core/constants.dart';
import 'package:ygo_scanner/data/db/dao/collection_dao.dart';
import 'package:ygo_scanner/data/db/dao/printing_dao.dart';
import 'package:ygo_scanner/data/seed/fake_collection_seed.dart';

import '../../data/db/test_db.dart';
import '../../support/widget_test_harness.dart';

void main() {
  late Database testDb;

  setUp(() async {
    testDb = await openInMemoryTestDb();
    // Provides Mirror Force (two printings, passcode 44095762) and Pot of
    // Greed (zero printings) — exactly the two shapes this flow needs to
    // exercise, without duplicating fixture setup.
    await seedFakeCollectionIfEmpty(testDb);
  });

  tearDown(() async {
    await testDb.close();
  });

  Future<void> openAddCard(WidgetTester tester) async {
    await pumpApp(tester, testDb);
    await tester.tap(find.text(AppStrings.homeTileLogCards));
    await pumpUntilSettled(tester);
  }

  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField), query);
    await pumpUntilSettled(tester);
  }

  // The search TextField echoes the typed query as its own text, which
  // ambiguates a plain find.text(name) once a result with the same name is
  // in the list — target the ListTile specifically instead.
  Future<void> tapSearchResult(WidgetTester tester, String cardName) async {
    await tester.tap(find.widgetWithText(ListTile, cardName));
    await pumpUntilSettled(tester);
  }

  testWidgets('selecting a card with multiple printings shows the printing step', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await openAddCard(tester);
      await search(tester, 'Mirror Force');
      await tapSearchResult(tester, 'Mirror Force');

      expect(find.text('MRD-EN094'), findsOneWidget);
      expect(find.text('DASA-EN059'), findsOneWidget);
    });
  });

  testWidgets('selecting a card with zero printings skips straight to condition', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await openAddCard(tester);
      await search(tester, 'Pot of Greed');
      await tapSearchResult(tester, 'Pot of Greed');

      expect(find.text(AppStrings.addCardSaveButton), findsOneWidget);
      expect(find.text(AppStrings.addCardNoPrintingLabel), findsOneWidget);
    });
  });

  testWidgets('saving with a chosen printing writes the right printing_id', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await openAddCard(tester);
      await search(tester, 'Mirror Force');
      await tapSearchResult(tester, 'Mirror Force');

      await tester.tap(find.text('DASA-EN059'));
      await pumpUntilSettled(tester);

      await tester.tap(find.text(AppStrings.addCardSaveButton));
      await pumpUntilSettled(tester);

      expect(find.text(AppStrings.addCardSavedMessage), findsOneWidget);

      final dasaPrinting = (await PrintingDao(
        testDb,
      ).getForPasscode('44095762')).firstWhere((p) => p.setCode == 'DASA-EN059');
      final entries = await CollectionDao(
        testDb,
      ).getEntriesForPasscode('44095762');
      // The seed already logs Mirror Force under both printings once each;
      // saving a third time under DASA-EN059 increments that row to 2
      // rather than adding a new one.
      expect(entries, hasLength(2));
      final dasaEntry = entries.firstWhere(
        (e) => e.printingId == dasaPrinting.id,
      );
      expect(dasaEntry.quantity, 2);
    });
  });

  testWidgets('the explicit skip button saves with printing_id null even when printings exist', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await openAddCard(tester);
      await search(tester, 'Mirror Force');
      await tapSearchResult(tester, 'Mirror Force');

      await tester.tap(find.text(AppStrings.addCardPrintingSkip));
      await pumpUntilSettled(tester);

      expect(find.text(AppStrings.addCardNoPrintingLabel), findsOneWidget);

      await tester.tap(find.text(AppStrings.addCardSaveButton));
      await pumpUntilSettled(tester);

      final entries = await CollectionDao(
        testDb,
      ).getEntriesForPasscode('44095762');
      expect(entries.where((e) => e.printingId == null), hasLength(1));
    });
  });

  testWidgets('after saving, the wizard resets to the search step', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await openAddCard(tester);
      await search(tester, 'Pot of Greed');
      await tapSearchResult(tester, 'Pot of Greed');

      await tester.tap(find.text(AppStrings.addCardSaveButton));
      await pumpUntilSettled(tester);

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text(AppStrings.addCardSaveButton), findsNothing);
    });
  });
}
