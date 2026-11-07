import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ygo_scanner/core/constants.dart';
import 'package:ygo_scanner/data/db/dao/card_dao.dart';
import 'package:ygo_scanner/data/db/dao/collection_dao.dart';
import 'package:ygo_scanner/data/db/database.dart';
import 'package:ygo_scanner/features/collection/collection_detail_screen.dart';
import 'package:ygo_scanner/models/card_condition.dart';
import 'package:ygo_scanner/models/card_language.dart';
import 'package:ygo_scanner/models/collection_entry.dart';
import 'package:ygo_scanner/models/ygo_card.dart';
import 'package:ygo_scanner/shared/widgets/language_flag.dart';

import '../../data/db/test_db.dart';
import '../../support/widget_test_harness.dart';

const _blueEyes = YgoCard(
  passcode: '89631139',
  name: 'Blue-Eyes White Dragon',
  type: 'Normal Monster',
);

void main() {
  late Database testDb;

  setUp(() async {
    testDb = await openInMemoryTestDb();
    await CardDao(testDb).insertAll([_blueEyes]);
  });

  tearDown(() async {
    await testDb.close();
  });

  testWidgets('detail shows a per-language breakdown when held in >1 language', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final dao = CollectionDao(testDb);
      // Same card (one passcode), two languages -> two rows.
      await dao.addOrIncrement(
        CollectionEntry(
          passcode: _blueEyes.passcode,
          condition: CardCondition.nearMint,
          language: 'EN',
          quantity: 2,
          createdAt: 1,
          updatedAt: 1,
        ),
      );
      await dao.addOrIncrement(
        CollectionEntry(
          passcode: _blueEyes.passcode,
          condition: CardCondition.nearMint,
          language: 'DE',
          quantity: 1,
          createdAt: 2,
          updatedAt: 2,
        ),
      );

      final entryWithCard = (await dao.getAll()).first;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWith((ref) async => testDb)],
          child: MaterialApp(
            home: CollectionDetailScreen(entryWithCard: entryWithCard),
          ),
        ),
      );
      await pumpUntilSettled(tester);

      // It moved to the Copies tab, so it is not on the one the screen opens on.
      expect(find.text(AppStrings.collectionByLanguageLabel), findsNothing);
      await tester.tap(find.text(AppStrings.cardTabCopies));
      await pumpUntilSettled(tester);

      // Both languages appear in the breakdown and again on their own entry
      // below it, so allow >1.
      expect(find.text(AppStrings.collectionByLanguageLabel), findsOneWidget);
      expect(find.text(languageLabel('EN')), findsWidgets);
      expect(find.text(languageLabel('DE')), findsWidgets);
      // Once in the breakdown, once on the entry's own block.
      expect(find.text('×2'), findsNWidgets(2));
      expect(find.text('×1'), findsNWidgets(2));

      // Both breakdown rows are flagged, plus each entry's Language row. The
      // names above are the point of these two: the flag is a *leading widget*,
      // not a prefix folded into the label, so the exact-text matchers still see
      // the two language names on their own.
      expect(find.byType(LanguageFlag), findsNWidgets(4));
      expect(find.text(kCardLanguageFlags['DE']!), findsNWidgets(2));
    });
  });

  testWidgets('no breakdown section when the card is held in one language', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final dao = CollectionDao(testDb);
      await dao.addOrIncrement(
        CollectionEntry(
          passcode: _blueEyes.passcode,
          condition: CardCondition.nearMint,
          language: 'EN',
          quantity: 1,
          createdAt: 1,
          updatedAt: 1,
        ),
      );
      final entryWithCard = (await dao.getAll()).first;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWith((ref) async => testDb)],
          child: MaterialApp(
            home: CollectionDetailScreen(entryWithCard: entryWithCard),
          ),
        ),
      );
      await pumpUntilSettled(tester);

      await tester.tap(find.text(AppStrings.cardTabCopies));
      await pumpUntilSettled(tester);

      expect(find.text(AppStrings.collectionCopiesTotal(1)), findsOneWidget);
      expect(find.text(AppStrings.collectionByLanguageLabel), findsNothing);
    });
  });
}
