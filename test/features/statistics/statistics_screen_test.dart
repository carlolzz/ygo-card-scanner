import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ygo_scanner/core/constants.dart';
import 'package:ygo_scanner/data/db/database.dart';
import 'package:ygo_scanner/data/seed/fake_collection_seed.dart';
import 'package:ygo_scanner/features/statistics/statistics_screen.dart';

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

  Future<void> openStatistics(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWith((ref) async => testDb)],
        child: const MaterialApp(home: StatisticsScreen()),
      ),
    );
    await pumpUntilSettled(tester);
  }

  testWidgets('renders totals, breakdown sections and the export button', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.runAsync(() async {
      await openStatistics(tester);

      // Exact counts are covered by the DAO aggregate tests; here we assert the
      // screen structure. (Seed: 9 copies across 5 distinct passcodes.)
      expect(find.text(AppStrings.statisticsTotalCopiesLabel), findsOneWidget);
      expect(find.text(AppStrings.statisticsDistinctCardsLabel), findsOneWidget);

      expect(find.text(AppStrings.statisticsByConditionSection), findsOneWidget);
      expect(find.text(AppStrings.statisticsByLanguageSection), findsOneWidget);
      expect(find.text(AppStrings.statisticsByTypeSection), findsOneWidget);
      // The seed is all-English, so the language breakdown has one row.
      expect(find.text('English'), findsOneWidget);

      expect(find.text(AppStrings.statisticsExportButton), findsOneWidget);
    });
  });
}
