import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ygo_scanner/core/constants.dart';
import 'package:ygo_scanner/data/db/dao/collection_dao.dart';
import 'package:ygo_scanner/data/db/dao/meta_dao.dart';
import 'package:ygo_scanner/data/db/dao/printing_dao.dart';
import 'package:ygo_scanner/data/db/database.dart';
import 'package:ygo_scanner/data/repositories/settings_repository.dart';
import 'package:ygo_scanner/data/seed/fake_collection_seed.dart';
import 'package:ygo_scanner/features/add_card/add_card_screen.dart';
import 'package:ygo_scanner/features/settings/settings_providers.dart';
import 'package:ygo_scanner/models/app_settings.dart';
import 'package:ygo_scanner/models/card_condition.dart';
import 'package:ygo_scanner/models/card_edition.dart';
import 'package:ygo_scanner/models/card_language.dart';

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

  // The manual wizard now lives at its own route (the "Log Cards" tile opens
  // the camera scanner), so pump it directly rather than tapping through Home.
  Future<void> openAddCard(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWith((ref) async => testDb)],
        child: const MaterialApp(home: AddCardScreen()),
      ),
    );
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

  testWidgets('picking a language writes it on the saved entry', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await openAddCard(tester);
      await search(tester, 'Pot of Greed');
      await tapSearchResult(tester, 'Pot of Greed');

      // Override the EN default with a per-card pick.
      await tester.tap(find.widgetWithText(ChoiceChip, languageLabel('IT')));
      await pumpUntilSettled(tester);
      await tester.tap(find.text(AppStrings.addCardSaveButton));
      await pumpUntilSettled(tester);

      final entries = await CollectionDao(
        testDb,
      ).getEntriesForPasscode('55144522');
      expect(entries.where((e) => e.language == 'IT'), hasLength(1));
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

  group('settings defaults', () {
    setUp(() async {
      await SettingsRepository(MetaDao(testDb)).save(
        const AppSettings(
          defaultCondition: CardCondition.lightPlayed,
          defaultEdition: CardEdition.first,
          language: 'DE',
        ),
      );
    });

    /// Like [openAddCard], but resolves settings before the screen builds —
    /// the wizard reads them synchronously, which `App`'s gate guarantees in
    /// production.
    Future<void> openWithSettings(WidgetTester tester) async {
      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWith((ref) async => testDb)],
      );
      addTearDown(container.dispose);
      await container.read(settingsControllerProvider.future);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: AddCardScreen()),
        ),
      );
      await pumpUntilSettled(tester);
    }

    testWidgets('the wizard opens on the configured defaults', (tester) async {
      await tester.runAsync(() async {
        await openWithSettings(tester);
        await search(tester, 'Pot of Greed');
        await tapSearchResult(tester, 'Pot of Greed');

        expect(
          tester
              .widget<ChoiceChip>(
                find.widgetWithText(
                  ChoiceChip,
                  CardCondition.lightPlayed.shortCode,
                ),
              )
              .selected,
          isTrue,
        );
        expect(
          tester
              .widget<ChoiceChip>(
                find.widgetWithText(ChoiceChip, CardEdition.first.label),
              )
              .selected,
          isTrue,
        );
      });
    });

    testWidgets('saving writes the configured defaults, including language', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await openWithSettings(tester);
        await search(tester, 'Pot of Greed');
        await tapSearchResult(tester, 'Pot of Greed');

        await tester.tap(find.text(AppStrings.addCardSaveButton));
        await pumpUntilSettled(tester);

        final entries = await CollectionDao(
          testDb,
        ).getEntriesForPasscode('55144522');
        final saved = entries.singleWhere(
          (e) => e.condition == CardCondition.lightPlayed,
        );
        expect(saved.edition, CardEdition.first);
        expect(saved.language, 'DE');
      });
    });

    testWidgets('the defaults are restored for the next card after a save', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await openWithSettings(tester);
        await search(tester, 'Pot of Greed');
        await tapSearchResult(tester, 'Pot of Greed');

        // Grade this one differently, then save — the reset must go back to
        // the configured default, not to the one-off pick or to Near Mint.
        await tester.tap(
          find.widgetWithText(ChoiceChip, CardCondition.poor.shortCode),
        );
        await pumpUntilSettled(tester);
        await tester.tap(find.text(AppStrings.addCardSaveButton));
        await pumpUntilSettled(tester);

        // Dark Magician has no printings in the seed, so this lands straight
        // on the condition step — and avoids tapping a button underneath the
        // "Added to your collection" SnackBar still on screen from the save.
        await search(tester, 'Dark Magician');
        await tapSearchResult(tester, 'Dark Magician');

        expect(
          tester
              .widget<ChoiceChip>(
                find.widgetWithText(
                  ChoiceChip,
                  CardCondition.lightPlayed.shortCode,
                ),
              )
              .selected,
          isTrue,
        );
      });
    });
  });
}
