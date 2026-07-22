import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ygo_scanner/core/constants.dart';
import 'package:ygo_scanner/core/router.dart';
import 'package:ygo_scanner/data/db/dao/collection_dao.dart';
import 'package:ygo_scanner/data/db/database.dart';
import 'package:ygo_scanner/data/seed/fake_collection_seed.dart';
import 'package:ygo_scanner/features/scan/scan_providers.dart';
import 'package:ygo_scanner/models/card_condition.dart';

import '../../data/db/test_db.dart';
import '../../support/widget_test_harness.dart';

const _darkMagician = '46986414';

void main() {
  late Database testDb;

  setUp(() async {
    testDb = await openInMemoryTestDb();
    await seedFakeCollectionIfEmpty(testDb);
  });

  tearDown(() async {
    await testDb.close();
  });

  testWidgets('a matched scan is reviewable and confirming logs it', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final readings = StreamController<PasscodeReading>.broadcast();
      addTearDown(readings.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWith((ref) async => testDb),
            passcodeReadingsProvider.overrideWith((ref) => readings.stream),
          ],
          child: MaterialApp.router(routerConfig: buildAppRouter()),
        ),
      );

      // Home -> Log Cards opens the camera scan screen.
      await tester.tap(find.text(AppStrings.homeTileLogCards));
      await pumpUntilSettled(tester);

      // Three agreeing frames drive the state machine to a match.
      for (var i = 0; i < 3; i++) {
        readings.add(PasscodeReading(i, _darkMagician));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump(const Duration(milliseconds: 20));
      }
      await pumpUntilSettled(tester);

      // The review panel shows the card and its default (Near Mint) grade.
      expect(find.text('Dark Magician'), findsOneWidget);
      expect(find.text(AppStrings.scanConfirmButton), findsOneWidget);

      // Downgrade to Excellent before confirming, proving the grade is editable.
      await tester.tap(find.text(CardCondition.excellent.shortCode));
      await pumpUntilSettled(tester);

      await tester.tap(find.text(AppStrings.scanConfirmButton));
      await pumpUntilSettled(tester);

      expect(find.text(AppStrings.scanSavedMessage), findsOneWidget);

      final entries = await CollectionDao(
        testDb,
      ).getEntriesForPasscode(_darkMagician);
      final scanned = entries.where(
        (e) => e.condition == CardCondition.excellent && e.printingId == null,
      );
      expect(scanned, hasLength(1));
    });
  });
}
