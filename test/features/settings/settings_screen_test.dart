import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ygo_scanner/core/constants.dart';
import 'package:ygo_scanner/core/theme/app_theme.dart';
import 'package:ygo_scanner/core/theme/tokens.dart';
import 'package:ygo_scanner/data/db/dao/card_dao.dart';
import 'package:ygo_scanner/data/db/dao/meta_dao.dart';
import 'package:ygo_scanner/data/db/dao/printing_dao.dart';
import 'package:ygo_scanner/data/db/database.dart';
import 'package:ygo_scanner/data/repositories/card_repository.dart';
import 'package:ygo_scanner/features/settings/settings_providers.dart';
import 'package:ygo_scanner/features/settings/settings_screen.dart';
import 'package:ygo_scanner/models/app_settings.dart';
import 'package:ygo_scanner/models/app_theme_mode.dart';
import 'package:ygo_scanner/models/card_condition.dart';
import 'package:ygo_scanner/models/card_edition.dart';
import 'package:ygo_scanner/models/printing.dart';
import 'package:ygo_scanner/models/ygo_card.dart';
import 'package:ygo_scanner/shared/widgets/searchable_text_picker.dart';

import '../../data/db/test_db.dart';
import '../../support/widget_test_harness.dart';

/// Counts sync attempts so the confirm dialog's cancel path can be asserted
/// without any network. Subclassing `CardRepository` mirrors the fake in
/// test/features/sync/initial_sync_screen_test.dart.
class _FakeCardRepository extends CardRepository {
  _FakeCardRepository(Database db)
    : super(
        cardDao: CardDao(db),
        printingDao: PrintingDao(db),
        metaDao: MetaDao(db),
        database: db,
      );

  int syncCount = 0;

  @override
  Stream<SyncProgress> sync() async* {
    syncCount++;
    yield const SyncProgress(0.5, SyncPhase.fetching);
    yield const SyncProgress(1, SyncPhase.writing);
  }
}

void main() {
  late Database testDb;

  // The db must be opened here, in a real-async zone — opening it inside a
  // testWidgets body hangs at teardown. See
  // .claude/skills/flutter-test-troubleshooting.md.
  setUp(() async {
    testDb = await openInMemoryTestDb();
  });

  tearDown(() async {
    await testDb.close();
  });

  Future<void> openSettings(
    WidgetTester tester, {
    CardRepository? cardRepository,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((ref) async => testDb),
          if (cardRepository != null)
            cardRepositoryProvider.overrideWith((ref) async => cardRepository),
        ],
        child: MaterialApp(
          theme: buildAppTheme(brightness: Brightness.dark),
          home: const SettingsScreen(),
        ),
      ),
    );
    await pumpUntilSettled(tester);
  }

  /// Scrolls [target] into view and all the way onto the screen.
  ///
  /// Both steps are needed. The `ListView` is lazy, so a widget below the fold
  /// has no element at all and finders simply miss it — hence `dragUntilVisible`
  /// first. But that stops as soon as the target is *built*, which can still
  /// leave it under the bottom edge where a tap misses, so `ensureVisible`
  /// finishes the job.
  Future<void> scrollTo(WidgetTester tester, Finder target) async {
    await tester.dragUntilVisible(
      target,
      find.byType(ListView),
      const Offset(0, -100),
    );
    await pumpUntilSettled(tester);
    await tester.ensureVisible(target);
    await pumpUntilSettled(tester);
  }

  /// The card-database section is the last thing in the list and sits below
  /// the fold in the default test viewport.
  Future<void> scrollToDatabaseSection(WidgetTester tester) =>
      scrollTo(tester, find.text(AppStrings.settingsResyncButton));

  testWidgets('renders the stored defaults as the selected options', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await MetaDao(testDb).set('settings.default_condition', 'LIGHT_PLAYED');
      await openSettings(tester);

      final chip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, CardCondition.lightPlayed.shortCode),
      );
      expect(chip.selected, isTrue);
    });
  });

  testWidgets('choosing a default condition persists it', (tester) async {
    await tester.runAsync(() async {
      await openSettings(tester);

      await tester.tap(
        find.widgetWithText(ChoiceChip, CardCondition.played.shortCode),
      );
      await pumpUntilSettled(tester);

      expect(
        await MetaDao(testDb).get('settings.default_condition'),
        CardCondition.played.toDb(),
      );
    });
  });

  testWidgets('choosing a default edition persists it', (tester) async {
    await tester.runAsync(() async {
      await openSettings(tester);

      await tester.tap(
        find.widgetWithText(ChoiceChip, CardEdition.first.label),
      );
      await pumpUntilSettled(tester);

      expect(
        await MetaDao(testDb).get('settings.default_edition'),
        CardEdition.first.toDb(),
      );
    });
  });

  testWidgets('choosing a language persists it', (tester) async {
    await tester.runAsync(() async {
      await openSettings(tester);

      await tester.tap(find.byType(DropdownButton<String>));
      await pumpUntilSettled(tester);
      await tester.tap(find.text('JP').last);
      await pumpUntilSettled(tester);

      expect(await MetaDao(testDb).get('settings.language'), 'JP');
    });
  });

  testWidgets('choosing a theme mode persists it', (tester) async {
    await tester.runAsync(() async {
      await openSettings(tester);

      // Appearance dropped below the fold in the 600pt test viewport when the
      // defaults section gained a fourth control — the same trap
      // `scrollToDatabaseSection` exists for, one section up.
      final lightChip = find.widgetWithText(
        ChoiceChip,
        AppThemeMode.light.label,
      );
      await scrollTo(tester, lightChip);
      await tester.tap(lightChip);
      await pumpUntilSettled(tester);

      expect(
        await MetaDao(testDb).get('settings.theme_mode'),
        AppThemeMode.light.toDb(),
      );
      // And the controller republishes it, which is what App watches to swap
      // MaterialApp.themeMode.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SettingsScreen)),
      );
      expect(
        container.read(settingsControllerProvider).value?.themeMode,
        AppThemeMode.light,
      );
    });
  });

  testWidgets('switching off the scan how-to box persists it', (tester) async {
    await tester.runAsync(() async {
      await openSettings(tester);

      // The scanning switches sit just above the card-database section, so the
      // same scroll brings them on-screen (dragUntilVisible alone stops as soon
      // as the tile is *built*, which can still be below the fold).
      await scrollToDatabaseSection(tester);
      await tester.tap(find.text(AppStrings.settingsScanHelpLabel));
      await pumpUntilSettled(tester);

      expect(await MetaDao(testDb).get('settings.show_scan_help'), 'false');
    });
  });

  testWidgets('re-sync asks for confirmation and does nothing when cancelled', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final repository = _FakeCardRepository(testDb);
      await openSettings(tester, cardRepository: repository);
      await scrollToDatabaseSection(tester);

      await tester.tap(find.text(AppStrings.settingsResyncButton));
      await pumpUntilSettled(tester);
      expect(find.text(AppStrings.settingsResyncDialogTitle), findsOneWidget);

      await tester.tap(find.text(AppStrings.settingsResyncDialogCancel));
      await pumpUntilSettled(tester);

      expect(repository.syncCount, 0);
    });
  });

  testWidgets('confirming re-sync runs a sync and reports it', (tester) async {
    await tester.runAsync(() async {
      final repository = _FakeCardRepository(testDb);
      await openSettings(tester, cardRepository: repository);
      await scrollToDatabaseSection(tester);

      await tester.tap(find.text(AppStrings.settingsResyncButton));
      await pumpUntilSettled(tester);
      await tester.tap(find.text(AppStrings.settingsResyncDialogConfirm));
      await pumpUntilSettled(tester);

      expect(repository.syncCount, 1);
      expect(find.text(AppStrings.settingsResyncDoneMessage), findsOneWidget);
    });
  });

  testWidgets('shows Never until a sync has been stamped', (tester) async {
    await tester.runAsync(() async {
      await openSettings(tester);
      await scrollToDatabaseSection(tester);

      expect(
        find.textContaining(AppStrings.settingsNeverSynced),
        findsOneWidget,
      );
    });
  });

  testWidgets('renders light surfaces under the light theme', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWith((ref) async => testDb),
          ],
          child: MaterialApp(
            theme: buildAppTheme(brightness: Brightness.light),
            home: const SettingsScreen(),
          ),
        ),
      );
      await pumpUntilSettled(tester);

      final palette = AppPalette.of(
        tester.element(find.byType(SettingsScreen)),
      );
      expect(palette, same(AppPalette.light));
    });
  });

  testWidgets('AppPalette falls back to dark without a registered theme', (
    tester,
  ) async {
    // Several existing widget tests pump a bare MaterialApp; the fallback is
    // what keeps them rendering the app's real (dark) look.
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
    );

    expect(
      AppPalette.of(tester.element(find.byType(Scaffold))),
      same(AppPalette.dark),
    );
  });

  testWidgets('the defaults survive a reopen of the screen', (tester) async {
    await tester.runAsync(() async {
      await openSettings(tester);
      await tester.tap(
        find.widgetWithText(ChoiceChip, CardCondition.mint.shortCode),
      );
      await pumpUntilSettled(tester);

      // A fresh ProviderScope: nothing cached, everything re-read from the db.
      await openSettings(tester);

      final chip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, CardCondition.mint.shortCode),
      );
      expect(chip.selected, isTrue);
      expect(const AppSettings().defaultCondition, isNot(CardCondition.mint));
    });
  });

  group('default rarity', () {
    /// Rarities come from the synced `printings` table, not a const list —
    /// there are roughly ninety of them and they are free-form text from
    /// YGOPRODeck, so a hand-written constant subtly off by a word would make
    /// the preference silently never match anything.
    Future<void> seedRarities(List<String> rarities) async {
      await CardDao(testDb).insertAll([
        const YgoCard(passcode: '89631139', name: 'Blue-Eyes White Dragon'),
      ]);
      await PrintingDao(testDb).insertAll([
        for (final (index, rarity) in rarities.indexed)
          Printing(
            passcode: '89631139',
            setCode: 'SET-$index',
            rarity: rarity,
          ),
      ]);
    }

    testWidgets('offers the synced rarities and persists a pick', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await seedRarities(['Common', 'Secret Rare', 'Ultra Rare']);
        await openSettings(tester);

        final picker = find.byType(SearchableTextPicker);
        expect(picker, findsOneWidget);
        await tester.ensureVisible(picker);
        await pumpUntilSettled(tester);

        // Focusing clears the field into a search box, exactly like the set
        // pickers in the logging flows.
        await tester.tap(picker);
        await pumpUntilSettled(tester);
        await tester.enterText(find.byType(TextField), 'secret');
        await pumpUntilSettled(tester);

        await tester.tap(
          find.descendant(of: picker, matching: find.text('Secret Rare')),
        );
        await pumpUntilSettled(tester);

        expect(
          await MetaDao(testDb).get('settings.default_rarity'),
          'Secret Rare',
        );
      });
    });

    testWidgets('an unsynced database still renders, offering nothing', (
      tester,
    ) async {
      await tester.runAsync(() async {
        // A fresh install before the first sync. The picker must degrade to its
        // "no preference" row rather than erroring or blanking the screen.
        await openSettings(tester);

        expect(find.byType(SearchableTextPicker), findsOneWidget);
        expect(find.text(AppStrings.settingsRarityLabel), findsOneWidget);
      });
    });
  });
}
