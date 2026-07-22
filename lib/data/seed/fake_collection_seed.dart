import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sqflite/sqflite.dart';

import '../../models/card_condition.dart';
import '../../models/card_edition.dart';
import '../../models/collection_entry.dart';
import '../../models/printing.dart';
import '../../models/ygo_card.dart';
import '../db/dao/card_dao.dart';
import '../db/dao/collection_dao.dart';
import '../db/dao/printing_dao.dart';
import '../db/database.dart';
import '../repositories/card_repository.dart';

part 'fake_collection_seed.g.dart';

const _blueEyesWhiteDragon = YgoCard(
  passcode: '89631139',
  name: 'Blue-Eyes White Dragon',
  type: 'Normal Monster',
  frameType: 'normal',
  attribute: 'LIGHT',
  race: 'Dragon',
  atk: 3000,
  def: 2500,
  level: 8,
  description: 'This legendary dragon is a powerful engine of destruction.',
  archetype: 'Blue-Eyes',
);

const _darkMagician = YgoCard(
  passcode: '46986414',
  name: 'Dark Magician',
  type: 'Normal Monster',
  frameType: 'normal',
  attribute: 'DARK',
  race: 'Spellcaster',
  atk: 2500,
  def: 2100,
  level: 7,
  description: 'The ultimate wizard in terms of attack and defense.',
  archetype: 'Dark Magician',
);

const _redEyesBDragon = YgoCard(
  passcode: '74677422',
  name: 'Red-Eyes B. Dragon',
  type: 'Normal Monster',
  frameType: 'normal',
  attribute: 'DARK',
  race: 'Dragon',
  atk: 2400,
  def: 2000,
  level: 7,
  description: 'A ferocious dragon with a deadly attack.',
  archetype: 'Red-Eyes',
);

const _mirrorForce = YgoCard(
  passcode: '44095762',
  name: 'Mirror Force',
  type: 'Trap Card',
  frameType: 'trap',
  race: 'Normal',
  description: "Destroy all your opponent's Attack Position monsters.",
);

const _potOfGreed = YgoCard(
  passcode: '55144522',
  name: 'Pot of Greed',
  type: 'Spell Card',
  frameType: 'spell',
  race: 'Normal',
  description: 'Draw 2 cards.',
);

final List<YgoCard> _seedCards = [
  _blueEyesWhiteDragon,
  _darkMagician,
  _redEyesBDragon,
  _mirrorForce,
  _potOfGreed,
];

const _blueEyesPrinting = Printing(
  passcode: '89631139',
  setCode: 'LOB-EN001',
  setName: 'Legend of Blue Eyes White Dragon',
  rarity: 'Ultra Rare',
);

const _redEyesPrinting = Printing(
  passcode: '74677422',
  setCode: 'LOB-EN002',
  setName: 'Legend of Blue Eyes White Dragon',
  rarity: 'Ultra Rare',
);

/// Mirror Force has the same passcode across every reprint — these two
/// rows demonstrate that different expansions of the same card are kept as
/// distinct `printings` rows (and, below, distinct `collection_entries`).
const _mirrorForcePrintingLob = Printing(
  passcode: '44095762',
  setCode: 'MRD-EN094',
  setName: 'Metal Raiders',
  rarity: 'Super Rare',
);

const _mirrorForcePrintingDasa = Printing(
  passcode: '44095762',
  setCode: 'DASA-EN059',
  setName: 'Dark Saviors',
  rarity: 'Ultra Rare',
);

final List<Printing> _seedPrintings = [
  _blueEyesPrinting,
  _redEyesPrinting,
  _mirrorForcePrintingLob,
  _mirrorForcePrintingDasa,
];

/// Populates the database with a handful of fixture cards and collection
/// entries, for exercising the Collection screen ahead of the manual
/// add-card flow and YGOPRODeck sync steps that will eventually provide
/// real data.
///
/// Gated on [CollectionDao.totalCardCount] rather than [CardDao.count] —
/// that's the count that must never be duplicated, and it stays a correct
/// gate once a real user collection exists (seeding becomes permanently
/// inert once `totalCardCount() > 0`).
Future<void> seedFakeCollectionIfEmpty(Database db) async {
  final collectionDao = CollectionDao(db);
  if (await collectionDao.totalCardCount() > 0) return;

  await db.transaction((txn) async {
    await CardDao(txn).insertAll(_seedCards);
    await PrintingDao(txn).insertAll(_seedPrintings);
  });

  final printingDao = PrintingDao(db);
  final blueEyesPrinting = (await printingDao.getForPasscode(
    _blueEyesWhiteDragon.passcode,
  )).first;
  final redEyesPrinting = (await printingDao.getForPasscode(
    _redEyesBDragon.passcode,
  )).first;
  final mirrorForcePrintings = await printingDao.getForPasscode(
    _mirrorForce.passcode,
  );
  final mirrorForcePrintingLob = mirrorForcePrintings.firstWhere(
    (p) => p.setCode == _mirrorForcePrintingLob.setCode,
  );
  final mirrorForcePrintingDasa = mirrorForcePrintings.firstWhere(
    (p) => p.setCode == _mirrorForcePrintingDasa.setCode,
  );

  final now = DateTime.now().millisecondsSinceEpoch;
  const day = Duration.millisecondsPerDay;

  final seedEntries = [
    CollectionEntry(
      passcode: _blueEyesWhiteDragon.passcode,
      printingId: blueEyesPrinting.id,
      condition: CardCondition.nearMint,
      edition: CardEdition.first,
      quantity: 2,
      createdAt: now - 4 * day,
      updatedAt: now - 4 * day,
    ),
    CollectionEntry(
      passcode: _darkMagician.passcode,
      condition: CardCondition.mint,
      quantity: 1,
      createdAt: now - 3 * day,
      updatedAt: now - 3 * day,
    ),
    CollectionEntry(
      passcode: _redEyesBDragon.passcode,
      printingId: redEyesPrinting.id,
      condition: CardCondition.lightPlayed,
      quantity: 3,
      createdAt: now - 2 * day,
      updatedAt: now - 2 * day,
    ),
    CollectionEntry(
      passcode: _mirrorForce.passcode,
      printingId: mirrorForcePrintingLob.id,
      condition: CardCondition.excellent,
      quantity: 1,
      createdAt: now - day,
      updatedAt: now - day,
    ),
    CollectionEntry(
      passcode: _mirrorForce.passcode,
      printingId: mirrorForcePrintingDasa.id,
      condition: CardCondition.nearMint,
      quantity: 1,
      createdAt: now - day,
      updatedAt: now - day,
    ),
    CollectionEntry(
      passcode: _potOfGreed.passcode,
      condition: CardCondition.poor,
      edition: CardEdition.limited,
      quantity: 1,
      createdAt: now,
      updatedAt: now,
    ),
  ];

  for (final entry in seedEntries) {
    await collectionDao.addOrIncrement(entry);
  }
}

/// Debug-only, runs once per app session. Kept in the provider layer rather
/// than `main.dart`/`app.dart` so only the Collection feature waits on it.
///
/// Also skipped once a real YGOPRODeck sync has happened
/// (`!cardRepository.needsSync()`) — a real sync only ever populates
/// `cards`/`printings`, never `collection_entries`, so without this check
/// this seed would still fire after a real sync and silently overwrite the
/// real synced rows for the fixture passcodes (`CardDao.insertAll` uses
/// `ConflictAlgorithm.replace`).
@Riverpod(keepAlive: true)
Future<void> debugSeedCollection(Ref ref) async {
  if (!kDebugMode) return;
  final cardRepository = await ref.watch(cardRepositoryProvider.future);
  if (!await cardRepository.needsSync()) return;
  final db = await ref.watch(appDatabaseProvider.future);
  await seedFakeCollectionIfEmpty(db);
}
