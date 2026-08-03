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

      // Both languages appear in the breakdown; whichever entry was opened also
      // shows its own language in the per-entry detail row, so allow >1.
      expect(find.text(AppStrings.collectionByLanguageLabel), findsOneWidget);
      expect(find.text('English'), findsWidgets);
      expect(find.text('German'), findsWidgets);
      expect(find.text('×2'), findsOneWidget);
      expect(find.text('×1'), findsOneWidget);

      // Both breakdown rows are flagged, plus the per-entry Language row above
      // them. The names above are the point of these two: the flag is a
      // *leading widget*, not a prefix folded into the label, so the exact-text
      // matchers still see 'English' and 'German' on their own.
      expect(find.byType(LanguageFlag), findsNWidgets(3));
      expect(find.text(kCardLanguageFlags['DE']!), findsOneWidget);
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

      expect(find.text(AppStrings.collectionByLanguageLabel), findsNothing);
    });
  });
}
