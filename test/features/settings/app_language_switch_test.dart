import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ygo_scanner/app.dart';
import 'package:ygo_scanner/core/constants.dart';
import 'package:ygo_scanner/core/routes.dart';
import 'package:ygo_scanner/data/db/dao/card_dao.dart';
import 'package:ygo_scanner/data/db/dao/meta_dao.dart';
import 'package:ygo_scanner/data/db/database.dart';
import 'package:ygo_scanner/features/home/home_screen.dart';
import 'package:ygo_scanner/features/settings/fast_log_screen.dart';
import 'package:ygo_scanner/features/settings/settings_providers.dart';
import 'package:ygo_scanner/features/sync/initial_sync_providers.dart';
import 'package:ygo_scanner/models/app_language.dart';
import 'package:ygo_scanner/models/ygo_card.dart';

import '../../data/db/test_db.dart';
import '../../support/widget_test_harness.dart';

/// The interface-language switch, through the real [App].
///
/// It has to be the real one: the strings are plain getters, and what makes a
/// change visible is `App` rebuilding everything below it. The usual `pumpApp`
/// harness pumps `MaterialApp.router` directly and would never see it.
///
/// Home is the screen to assert on, because it is the hard case: `const`, and
/// watching nothing, so only that rebuild can reach it. A screen that watches
/// settings (Fast log, Settings) would update on its own and pass regardless.
void main() {
  // Opened in setUp, a real-async zone — see app_gate_test for why.
  late Database db;

  setUp(() async {
    db = await openInMemoryTestDb();
  });

  tearDown(() async {
    await db.close();
    // Process-wide; the rest of this isolate's tests expect English.
    AppStrings.select(AppLanguage.english);
  });

  /// An already-synced db, so the gate goes straight to Home.
  Future<void> openApp(WidgetTester tester) async {
    await CardDao(db).insertAll(const [
      YgoCard(passcode: '89631139', name: 'Blue-Eyes White Dragon'),
    ]);
    await MetaDao(db).set('last_sync', '123456');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((ref) async => db),
          debugSyncBypassProvider.overrideWith((ref) => false),
        ],
        child: const App(),
      ),
    );
    await pumpUntilSettled(tester);
  }

  SettingsController settingsOf(WidgetTester tester) => ProviderScope
      .containerOf(tester.element(find.byType(App)))
      .read(settingsControllerProvider.notifier);

  testWidgets('switching to Italian re-renders the screen on display', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await openApp(tester);
      expect(find.text('Log Cards'), findsOneWidget);

      await settingsOf(tester).setAppLanguage(AppLanguage.italian);
      await pumpUntilSettled(tester);

      expect(find.text('Registra carte'), findsOneWidget);
      expect(find.text('Log Cards'), findsNothing);
    });
  });

  // The switch happens on Settings with Home underneath, so both halves matter:
  // the user keeps their place, and the screen they go back to has changed too.
  testWidgets('the route survives, and the screen below it is translated', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await openApp(tester);
      final router = GoRouter.of(tester.element(find.byType(HomeScreen)));
      // `App._router` is static, so whatever this leaves on the stack would be
      // where the next test in this isolate starts.
      addTearDown(() => router.go(AppRoutes.home));

      router.push(AppRoutes.fastLog);
      await pumpUntilSettled(tester);
      expect(find.text('Fast log'), findsWidgets);

      await settingsOf(tester).setAppLanguage(AppLanguage.italian);
      await pumpUntilSettled(tester);

      expect(find.byType(FastLogScreen), findsOneWidget);
      expect(find.text('Registrazione rapida'), findsWidgets);

      router.pop();
      await pumpUntilSettled(tester);

      expect(find.text('Registra carte'), findsOneWidget);
    });
  });

  // Material's own text comes from `flutter_localizations`, not `AppStrings`,
  // so it only follows if `App` passes the locale and the delegates through.
  testWidgets("Material's own strings follow the language", (tester) async {
    await tester.runAsync(() async {
      await openApp(tester);
      final context = tester.element(find.byType(HomeScreen));
      expect(MaterialLocalizations.of(context).backButtonTooltip, 'Back');

      await settingsOf(tester).setAppLanguage(AppLanguage.italian);
      await pumpUntilSettled(tester);

      expect(
        MaterialLocalizations.of(
          tester.element(find.byType(HomeScreen)),
        ).backButtonTooltip,
        'Indietro',
      );
    });
  });

  testWidgets('the choice is persisted and applied on the next start', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await MetaDao(db).set('settings.app_language', 'ITALIAN');
      await openApp(tester);

      expect(AppStrings.language, AppLanguage.italian);
      expect(find.text('Registra carte'), findsOneWidget);
    });
  });
}
