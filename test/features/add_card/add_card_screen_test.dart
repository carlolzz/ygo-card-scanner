import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ygo_scanner/core/constants.dart';
import 'package:ygo_scanner/data/assets/localized_names.dart';
import 'package:ygo_scanner/data/db/dao/card_name_dao.dart';
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
import 'package:ygo_scanner/models/fast_log_field.dart';
import 'package:ygo_scanner/shared/widgets/card_art_thumbnail.dart';
import 'package:ygo_scanner/shared/widgets/search_language_picker.dart';

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

  /// Like [openAddCard], but resolves settings before the screen builds — the
  /// wizard reads them synchronously (`ref.read`, once, at controller build),
  /// which `App`'s gate guarantees in production. Any test whose subject is a
  /// setting must seed the `meta` rows *before* calling this: flipping one
  /// afterwards, the way the scan screen's help/diagnostics tests do, cannot
  /// reach a controller that has already read its snapshot.
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

  testWidgets(
    'selecting a card with multiple printings shows the printing step',
    (tester) async {
      await tester.runAsync(() async {
        await openAddCard(tester);
        await search(tester, 'Mirror Force');
        await tapSearchResult(tester, 'Mirror Force');

        expect(find.text('MRD-EN094'), findsOneWidget);
        expect(find.text('DASA-EN059'), findsOneWidget);
      });
    },
  );

  // The wizard was the only logging surface with no picture, so the name in a
  // search list was the only confirmation the right card had been picked.
  testWidgets('both steps after search show the card artwork', (tester) async {
    await tester.runAsync(() async {
      await openAddCard(tester);
      await search(tester, 'Mirror Force');
      await tapSearchResult(tester, 'Mirror Force');

      // The printing step.
      expect(find.byType(CardArtThumbnail), findsOneWidget);

      await tester.tap(find.text(AppStrings.addCardPrintingSkip));
      await pumpUntilSettled(tester);

      // The condition step.
      expect(find.byType(CardArtThumbnail), findsOneWidget);
      expect(find.text('Mirror Force'), findsOneWidget);
    });
  });

  testWidgets(
    'selecting a card with zero printings skips straight to condition',
    (tester) async {
      await tester.runAsync(() async {
        await openAddCard(tester);
        await search(tester, 'Pot of Greed');
        await tapSearchResult(tester, 'Pot of Greed');

        expect(find.text(AppStrings.addCardSaveButton), findsOneWidget);
        expect(find.text(AppStrings.addCardNoPrintingLabel), findsOneWidget);
      });
    },
  );

  testWidgets('selecting a card with one printing skips the step with that '
      'printing already picked', (tester) async {
    await tester.runAsync(() async {
      await openAddCard(tester);
      // Blue-Eyes has exactly one seeded printing, so the step would offer a
      // one-row list and a Skip button — a decision with a single answer.
      await search(tester, 'Blue-Eyes');
      await tapSearchResult(tester, 'Blue-Eyes White Dragon');

      expect(find.text(AppStrings.addCardSaveButton), findsOneWidget);
      // The set is shown, not silently applied.
      expect(find.text('LOB-EN001'), findsOneWidget);
      expect(find.text(AppStrings.addCardNoPrintingLabel), findsNothing);
    });
  });

  testWidgets('that auto-pick is written, and back still reaches the step', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final lobPrinting = (await PrintingDao(
        testDb,
      ).getForPasscode('89631139')).single;

      await openAddCard(tester);
      await search(tester, 'Blue-Eyes');
      await tapSearchResult(tester, 'Blue-Eyes White Dragon');

      // The escape hatch: the printing step is one tap away, Skip included.
      await tester.tap(find.byTooltip(AppStrings.addCardBackTooltip));
      await pumpUntilSettled(tester);
      expect(find.text(AppStrings.addCardPrintingSkip), findsOneWidget);

      await tester.tap(find.text('LOB-EN001'));
      await pumpUntilSettled(tester);
      await tester.tap(find.text(AppStrings.addCardSaveButton));
      await pumpUntilSettled(tester);

      // Seeded Blue-Eyes is 1st Edition; the wizard defaults to Unlimited.
      final entries = await CollectionDao(
        testDb,
      ).getEntriesForPasscode('89631139');
      final saved = entries.where((e) => e.edition == CardEdition.unlimited);
      expect(saved, hasLength(1));
      expect(saved.first.printingId, lobPrinting.id);
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

      final dasaPrinting = (await PrintingDao(testDb).getForPasscode(
        '44095762',
      )).firstWhere((p) => p.setCode == 'DASA-EN059');
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

  testWidgets(
    'the explicit skip button saves with printing_id null even when printings exist',
    (tester) async {
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
    },
  );

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

  group('search language', () {
    /// Italian names for the two fixture cards, standing in for the bundled
    /// `assets/card_names_it.json` — the asset itself is covered by
    /// `localized_names_asset_test.dart`, and loading 11.6k rows here would be
    /// pure test latency.
    Future<void> seedItalianNames() => CardNameDao(testDb).insertAll(const [
      CardName(passcode: '46986414', language: 'IT', name: 'Mago Nero'),
      CardName(passcode: '44095762', language: 'IT', name: 'Forza Speculare'),
    ]);

    /// Marks the names as already imported, so `ensureLocalizedNames` skips the
    /// `rootBundle` read a widget test has no bundle for.
    Future<void> markImported() =>
        MetaDao(testDb).set('localized_names_it', '$kLocalizedNamesVersion');

    Future<void> chooseLanguage(WidgetTester tester, String code) async {
      await tester.tap(find.byType(SearchLanguagePicker));
      await pumpUntilSettled(tester);
      // Only the open menu spells the language out — the closed control shows
      // the code — so this matches the menu item and nothing else.
      await tester.tap(find.text(languageLabel(code)).last);
      await pumpUntilSettled(tester);
    }

    testWidgets('English is the default and searches English names', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await seedItalianNames();
        await markImported();
        await openAddCard(tester);

        expect(
          // The code, not `languageLabel('EN')`: the closed control carries the
          // flag and the two letters, and the full name only appears in the
          // menu it opens.
          find.widgetWithText(SearchLanguagePicker, 'EN'),
          findsOneWidget,
        );
        await search(tester, 'Mago');
        expect(find.byType(ListTile), findsNothing);
      });
    });

    testWidgets('Italian matches the Italian name and shows it under the '
        'English one', (tester) async {
      await tester.runAsync(() async {
        await seedItalianNames();
        await markImported();
        await openAddCard(tester);

        await chooseLanguage(tester, 'IT');
        await search(tester, 'Mago');

        // The card is still named, logged and pictured in English; the Italian
        // name is there so the row visibly contains what was typed.
        final tile = find.widgetWithText(ListTile, 'Dark Magician');
        expect(tile, findsOneWidget);
        expect(
          find.descendant(of: tile, matching: find.text('Mago Nero')),
          findsOneWidget,
        );
      });
    });

    testWidgets('the choice is persisted', (tester) async {
      await tester.runAsync(() async {
        await seedItalianNames();
        await markImported();
        await openAddCard(tester);
        await chooseLanguage(tester, 'IT');

        expect(
          (await SettingsRepository(MetaDao(testDb)).load()).searchLanguage,
          'IT',
        );
      });
    });
  });

  group('fast log', () {
    // Condition stays asked; edition and language do not. Their defaults are
    // set to non-default values so a silently written row is distinguishable
    // from one that merely happened to land on the built-in defaults.
    setUp(() async {
      await SettingsRepository(MetaDao(testDb)).save(
        const AppSettings(
          defaultEdition: CardEdition.first,
          language: 'DE',
          fastLogEnabled: true,
          fastLogFields: {FastLogField.condition},
        ),
      );
    });

    Future<List<Map<String, Object?>>> entriesFor(String passcode) async {
      final entries = await CollectionDao(
        testDb,
      ).getEntriesForPasscode(passcode);
      return [
        for (final entry in entries)
          {
            'printingId': entry.printingId,
            'edition': entry.edition,
            'language': entry.language,
            'condition': entry.condition,
          },
      ];
    }

    testWidgets('the printing step is skipped even with several printings', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await openWithSettings(tester);
        await search(tester, 'Mirror Force');
        await tapSearchResult(tester, 'Mirror Force');

        expect(find.text(AppStrings.addCardSaveButton), findsOneWidget);
        expect(find.text(AppStrings.addCardPrintingSkip), findsNothing);
      });
    });

    testWidgets('only the ticked detail keeps a control', (tester) async {
      await tester.runAsync(() async {
        await openWithSettings(tester);
        await search(tester, 'Mirror Force');
        await tapSearchResult(tester, 'Mirror Force');

        expect(
          find.widgetWithText(ChoiceChip, CardCondition.nearMint.shortCode),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(ChoiceChip, CardEdition.first.label),
          findsNothing,
        );
        expect(
          find.widgetWithText(ChoiceChip, languageLabel('DE')),
          findsNothing,
        );
        // Quantity is never suppressed: it defaults to 1 and costs no
        // interaction to leave alone.
        expect(find.text(AppStrings.collectionQuantityLabel), findsOneWidget);
      });
    });

    testWidgets('the panel says what it is about to write silently', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await openWithSettings(tester);
        await search(tester, 'Mirror Force');
        await tapSearchResult(tester, 'Mirror Force');

        expect(
          find.textContaining(AppStrings.fastLogSilentPrefix),
          findsOneWidget,
        );
        expect(find.textContaining(CardEdition.first.label), findsOneWidget);
      });
    });

    testWidgets('saving writes the defaults for the details it never asked', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await openWithSettings(tester);
        await search(tester, 'Mirror Force');
        await tapSearchResult(tester, 'Mirror Force');
        await tester.tap(find.text(AppStrings.addCardSaveButton));
        await pumpUntilSettled(tester);

        // `contains` compares maps by identity, so match deeply instead. The
        // seed's two Mirror Force entries both carry a printing, so the row
        // written here is the only one without.
        final saved = await entriesFor('44095762');
        expect(
          saved,
          anyElement(
            equals({
              // Several printings, so `preferredPrinting` declines and Fast
              // log offers no picker: logged without a set, by design.
              'printingId': null,
              'edition': CardEdition.first,
              'language': 'DE',
              'condition': CardCondition.nearMint,
            }),
          ),
        );
      });
    });

    // Fast log suppresses the picker, not `preferredPrinting`.
    testWidgets('a card with one known printing still gets it', (tester) async {
      await tester.runAsync(() async {
        final lob = (await PrintingDao(
          testDb,
        ).getForPasscode('89631139')).single;

        await openWithSettings(tester);
        await search(tester, 'Blue-Eyes');
        await tapSearchResult(tester, 'Blue-Eyes White Dragon');
        await tester.tap(find.text(AppStrings.addCardSaveButton));
        await pumpUntilSettled(tester);

        final saved = await entriesFor('89631139');
        expect(saved.map((entry) => entry['printingId']), contains(lob.id));
      });
    });

    testWidgets('back from the condition step returns to search', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await openWithSettings(tester);
        await search(tester, 'Mirror Force');
        await tapSearchResult(tester, 'Mirror Force');

        await tester.tap(find.byTooltip(AppStrings.addCardBackTooltip));
        await pumpUntilSettled(tester);

        // The printing step is unreachable under Fast log, so the back button
        // must not route into it: its Skip button would null out the set.
        expect(find.text(AppStrings.addCardPrintingSkip), findsNothing);
        expect(find.byType(SearchLanguagePicker), findsOneWidget);
      });
    });
  });
}
