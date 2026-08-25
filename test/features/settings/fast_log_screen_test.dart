import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ygo_scanner/core/constants.dart';
import 'package:ygo_scanner/core/theme/app_theme.dart';
import 'package:ygo_scanner/data/db/dao/meta_dao.dart';
import 'package:ygo_scanner/data/db/database.dart';
import 'package:ygo_scanner/data/repositories/settings_repository.dart';
import 'package:ygo_scanner/features/settings/fast_log_screen.dart';
import 'package:ygo_scanner/models/app_settings.dart';
import 'package:ygo_scanner/models/fast_log_field.dart';

import '../../data/db/test_db.dart';
import '../../support/widget_test_harness.dart';

void main() {
  late Database testDb;

  // Opened here, in a real-async zone: opening it inside a testWidgets body
  // hangs at teardown. See .claude/skills/flutter-test-troubleshooting.md.
  setUp(() async {
    testDb = await openInMemoryTestDb();
  });

  tearDown(() async {
    await testDb.close();
  });

  /// Pumps the screen directly rather than routing to it through go_router:
  /// navigating to a db-backed screen mid route-transition kicks off the
  /// sqflite isolate and does not settle (CLAUDE.md step 10).
  Future<void> openFastLog(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWith((ref) async => testDb)],
        child: MaterialApp(
          theme: buildAppTheme(brightness: Brightness.dark),
          home: const FastLogScreen(),
        ),
      ),
    );
    await pumpUntilSettled(tester);
  }

  Future<void> seed(AppSettings settings) =>
      SettingsRepository(MetaDao(testDb)).save(settings);

  SwitchListTile switchFor(WidgetTester tester, FastLogField field) => tester
      .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, field.label));

  testWidgets('renders one switch per field, off by default', (tester) async {
    await tester.runAsync(() async {
      await openFastLog(tester);

      expect(
        find.byType(SwitchListTile),
        findsNWidgets(FastLogField.values.length),
      );
      for (final field in FastLogField.values) {
        expect(switchFor(tester, field).value, isFalse);
      }
    });
  });

  testWidgets('renders the stored ticks', (tester) async {
    await tester.runAsync(() async {
      await seed(
        const AppSettings(
          fastLogEnabled: true,
          fastLogFields: {FastLogField.language},
        ),
      );
      await openFastLog(tester);

      expect(switchFor(tester, FastLogField.language).value, isTrue);
      expect(switchFor(tester, FastLogField.condition).value, isFalse);
      expect(switchFor(tester, FastLogField.edition).value, isFalse);
    });
  });

  testWidgets('ticking a field persists it', (tester) async {
    await tester.runAsync(() async {
      await openFastLog(tester);

      await tester.tap(
        find.widgetWithText(SwitchListTile, FastLogField.condition.label),
      );
      await pumpUntilSettled(tester);

      expect(
        await MetaDao(testDb).get('settings.fast_log_fields'),
        'CONDITION',
      );
    });
  });

  testWidgets('unticking a field persists the removal', (tester) async {
    await tester.runAsync(() async {
      await seed(
        const AppSettings(
          fastLogFields: {FastLogField.condition, FastLogField.edition},
        ),
      );
      await openFastLog(tester);

      await tester.tap(
        find.widgetWithText(SwitchListTile, FastLogField.condition.label),
      );
      await pumpUntilSettled(tester);

      expect(await MetaDao(testDb).get('settings.fast_log_fields'), 'EDITION');
    });
  });

  // The reason `setFastLogField` takes one field rather than a whole set.
  // A whole-set setter would be handed a set computed from the snapshot the
  // widget rendered, so the second write would revert the first.
  testWidgets('two ticks in immediate succession both survive', (tester) async {
    await tester.runAsync(() async {
      await openFastLog(tester);

      await tester.tap(
        find.widgetWithText(SwitchListTile, FastLogField.condition.label),
      );
      await tester.tap(
        find.widgetWithText(SwitchListTile, FastLogField.language.label),
      );
      await pumpUntilSettled(tester);

      expect(
        await MetaDao(testDb).get('settings.fast_log_fields'),
        'CONDITION,LANGUAGE',
      );
    });
  });

  testWidgets('says the choices are inert while the switch is off', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await openFastLog(tester);

      expect(find.text(AppStrings.fastLogDisabledNote), findsOneWidget);
      expect(find.text(AppStrings.fastLogAllTickedNote), findsNothing);
    });
  });

  testWidgets('says Fast log is doing nothing when everything is ticked', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await seed(
        AppSettings(
          fastLogEnabled: true,
          fastLogFields: FastLogField.values.toSet(),
        ),
      );
      await openFastLog(tester);

      expect(find.text(AppStrings.fastLogAllTickedNote), findsOneWidget);
      expect(find.text(AppStrings.fastLogDisabledNote), findsNothing);
    });
  });

  testWidgets('shows neither note when Fast log is actually suppressing', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await seed(
        const AppSettings(
          fastLogEnabled: true,
          fastLogFields: {FastLogField.condition},
        ),
      );
      await openFastLog(tester);

      expect(find.text(AppStrings.fastLogAllTickedNote), findsNothing);
      expect(find.text(AppStrings.fastLogDisabledNote), findsNothing);
    });
  });
}
