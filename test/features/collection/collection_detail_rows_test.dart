import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ygo_scanner/core/constants.dart';
import 'package:ygo_scanner/data/db/dao/card_dao.dart';
import 'package:ygo_scanner/data/db/dao/collection_dao.dart';
import 'package:ygo_scanner/data/db/dao/printing_dao.dart';
import 'package:ygo_scanner/data/db/database.dart';
import 'package:ygo_scanner/features/collection/collection_detail_screen.dart';
import 'package:ygo_scanner/models/card_condition.dart';
import 'package:ygo_scanner/models/collection_entry.dart';
import 'package:ygo_scanner/models/printing.dart';
import 'package:ygo_scanner/models/ygo_card.dart';

import '../../data/db/test_db.dart';
import '../../support/widget_test_harness.dart';

const _potOfGreed = YgoCard(
  passcode: '55144522',
  name: 'Pot of Greed',
  type: 'Spell Card',
  frameType: 'spell',
  attribute: 'SPELL',
  race: 'Normal',
);
const _mirrorForce = YgoCard(
  passcode: '44095762',
  name: 'Mirror Force',
  type: 'Trap Card',
  frameType: 'trap',
  attribute: 'TRAP',
  race: 'Normal',
);
const _darkMagician = YgoCard(
  passcode: '46986414',
  name: 'Dark Magician',
  type: 'Normal Monster',
  frameType: 'normal',
  attribute: 'DARK',
  race: 'Spellcaster',
);

void main() {
  late Database testDb;
  late CollectionDao collectionDao;

  setUp(() async {
    testDb = await openInMemoryTestDb();
    collectionDao = CollectionDao(testDb);
    await CardDao(testDb).insertAll([_potOfGreed, _mirrorForce, _darkMagician]);
  });

  tearDown(() async {
    await testDb.close();
  });

  Future<void> openDetail(WidgetTester tester, String passcode) async {
    final entryWithCard = (await collectionDao.getAll())
        .firstWhere((e) => e.entry.passcode == passcode);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWith((ref) async => testDb)],
        child: MaterialApp(
          home: CollectionDetailScreen(entryWithCard: entryWithCard),
        ),
      ),
    );
    await pumpUntilSettled(tester);
  }

  Future<void> log(YgoCard card, {int? printingId}) => collectionDao
      .addOrIncrement(CollectionEntry(
        passcode: card.passcode,
        printingId: printingId,
        condition: CardCondition.nearMint,
        quantity: 1,
        createdAt: 1,
        updatedAt: 1,
      ));

  group('the race row names the card\'s own frame', () {
    // YGOPRODeck's `race` holds the monster type for monsters and the card's
    // kind for Spell/Trap — which players name after the frame, not with a
    // generic "Property".
    testWidgets('a Spell is labelled Spell Type', (tester) async {
      await tester.runAsync(() async {
        await log(_potOfGreed);
        await openDetail(tester, _potOfGreed.passcode);

        expect(
          find.text(AppStrings.collectionCardSpellTypeLabel),
          findsOneWidget,
        );
        expect(find.text(AppStrings.collectionCardRaceLabel), findsNothing);
        // "SPELL" duplicates the type row, so the attribute row stays hidden.
        expect(
          find.text(AppStrings.collectionCardAttributeLabel),
          findsNothing,
        );
      });
    });

    testWidgets('a Trap is labelled Trap Type', (tester) async {
      await tester.runAsync(() async {
        await log(_mirrorForce);
        await openDetail(tester, _mirrorForce.passcode);

        expect(
          find.text(AppStrings.collectionCardTrapTypeLabel),
          findsOneWidget,
        );
        expect(find.text(AppStrings.collectionCardRaceLabel), findsNothing);
      });
    });

    testWidgets('a monster keeps Monster Type', (tester) async {
      await tester.runAsync(() async {
        await log(_darkMagician);
        await openDetail(tester, _darkMagician.passcode);

        expect(find.text(AppStrings.collectionCardRaceLabel), findsOneWidget);
        expect(
          find.text(AppStrings.collectionCardSpellTypeLabel),
          findsNothing,
        );
        expect(find.text(AppStrings.collectionCardTrapTypeLabel), findsNothing);
      });
    });
  });

  testWidgets('rarity gets its own row and is not trailed onto the set', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await PrintingDao(testDb).insertAll([
        const Printing(
          passcode: '44095762',
          setCode: 'MRD-EN094',
          setName: 'Metal Raiders',
          rarity: 'Super Rare',
        ),
      ]);
      final printing =
          (await PrintingDao(testDb).getForPasscode(_mirrorForce.passcode))
              .single;
      await log(_mirrorForce, printingId: printing.id);
      await openDetail(tester, _mirrorForce.passcode);

      expect(find.text(AppStrings.collectionSetLabel), findsOneWidget);
      expect(find.text('MRD-EN094 · Metal Raiders'), findsOneWidget);
      expect(find.text(AppStrings.collectionRarityLabel), findsOneWidget);
      expect(find.text('Super Rare'), findsOneWidget);
    });
  });

  testWidgets('no rarity row when the printing records none', (tester) async {
    await tester.runAsync(() async {
      await PrintingDao(testDb).insertAll([
        const Printing(
          passcode: '44095762',
          setCode: 'MRD-EN094',
          setName: 'Metal Raiders',
        ),
      ]);
      final printing =
          (await PrintingDao(testDb).getForPasscode(_mirrorForce.passcode))
              .single;
      await log(_mirrorForce, printingId: printing.id);
      await openDetail(tester, _mirrorForce.passcode);

      expect(find.text(AppStrings.collectionSetLabel), findsOneWidget);
      expect(find.text(AppStrings.collectionRarityLabel), findsNothing);
    });
  });
}
