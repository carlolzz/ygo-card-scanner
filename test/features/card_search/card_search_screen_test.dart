import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ygo_scanner/core/constants.dart';
import 'package:ygo_scanner/data/db/dao/card_dao.dart';
import 'package:ygo_scanner/data/db/database.dart';
import 'package:ygo_scanner/features/card_search/card_search_screen.dart';
import 'package:ygo_scanner/models/ygo_card.dart';
import 'package:ygo_scanner/shared/widgets/card_art_thumbnail.dart';

import '../../data/db/test_db.dart';
import '../../support/widget_test_harness.dart';

/// Searching the whole card database, owned or not.
///
/// Pumped directly rather than routed to from Home: navigating *through*
/// go_router into a screen that kicks off the sqflite isolate mid
/// route-transition does not settle under a widget test — the same trap
/// `statistics_screen_test` documents.
void main() {
  late Database db;

  setUp(() async {
    // Opened in setUp, not in the testWidgets body: opening a
    // sqflite_common_ffi database inside the fake-async zone hangs at teardown.
    db = await openInMemoryTestDb();
    await CardDao(db).insertAll(const [
      YgoCard(
        passcode: '89631139',
        name: 'Blue-Eyes White Dragon',
        type: 'Normal Monster',
        localImagePath: 'no-such-file.jpg',
      ),
      YgoCard(
        passcode: '44095762',
        name: 'Mirror Force',
        type: 'Trap Card',
        localImagePath: 'no-such-file.jpg',
      ),
    ]);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpSearch(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWith((ref) async => db)],
        child: const MaterialApp(home: CardSearchScreen()),
      ),
    );
    await pumpUntilSettled(tester);
  }

  // An empty field is not an empty result. Saying "no cards match" before the
  // user has typed anything reads as a broken database.
  testWidgets('an untouched field explains the screen instead of reporting '
      'nothing found', (tester) async {
    await tester.runAsync(() async {
      await pumpSearch(tester);

      expect(find.text(AppStrings.cardSearchPrompt), findsOneWidget);
      expect(find.text(AppStrings.cardSearchEmptyMessage), findsNothing);
    });
  });

  testWidgets('typing a name lists matching cards', (tester) async {
    await tester.runAsync(() async {
      await pumpSearch(tester);

      await tester.enterText(find.byType(TextField), 'blue-eyes');
      await pumpUntilSettled(tester);

      expect(find.text('Blue-Eyes White Dragon'), findsOneWidget);
      expect(find.text('Mirror Force'), findsNothing);
    });
  });

  testWidgets('a name nothing matches says so', (tester) async {
    await tester.runAsync(() async {
      await pumpSearch(tester);

      await tester.enterText(find.byType(TextField), 'zzzz');
      await pumpUntilSettled(tester);

      expect(find.text(AppStrings.cardSearchEmptyMessage), findsOneWidget);
    });
  });

  // Cards the user does not own have never been through `addOrIncrement`, so
  // their art has never been downloaded — the *art* thumbnail is what fetches
  // it. Rows without a picture would defeat the point of a browse screen.
  testWidgets('results carry artwork', (tester) async {
    await tester.runAsync(() async {
      await pumpSearch(tester);

      await tester.enterText(find.byType(TextField), 'mirror');
      await pumpUntilSettled(tester);

      // The fixture's image file is absent, so the thumbnail renders its
      // placeholder — the assertion is that the row has one at all.
      final tile = find.widgetWithText(ListTile, 'Mirror Force');
      expect(tile, findsOneWidget);
      expect(tester.widget<ListTile>(tile).leading, isA<CardArtThumbnail>());
    });
  });
}
