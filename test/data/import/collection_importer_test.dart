import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ygo_scanner/data/db/dao/collection_dao.dart';
import 'package:ygo_scanner/data/export/collection_csv.dart';
import 'package:ygo_scanner/data/export/collection_csv_parser.dart';
import 'package:ygo_scanner/data/import/collection_import_plan.dart';
import 'package:ygo_scanner/data/import/collection_importer.dart';
import 'package:ygo_scanner/data/seed/fake_collection_seed.dart';
import 'package:ygo_scanner/models/card_condition.dart';

import '../db/test_db.dart';

/// End-to-end against a real database: the resolution of a CSV's set columns
/// back to `printings.id`, and the write itself.
///
/// The seeded fixture (see `fake_collection_seed.dart`) already holds:
///   Blue-Eyes  89631139  LOB-EN001 Ultra Rare   NM 1st  x2
///   Dark Magician 46986414  (no printing)       MINT    x1
///   Mirror Force 44095762  MRD-EN094 Super Rare EX      x1
///   Mirror Force 44095762  DASA-EN059 Ultra Rare NM     x1
void main() {
  late Database db;
  late CollectionImporter importer;
  late CollectionDao dao;

  const header =
      'passcode,name,set_code,set_name,rarity,condition,edition,language,'
      'quantity,notes,created_at,updated_at';

  String csv(List<String> rows) => '${[header, ...rows].join('\r\n')}\r\n';

  setUp(() async {
    db = await openInMemoryTestDb();
    await seedFakeCollectionIfEmpty(db);
    importer = CollectionImporter(db);
    dao = CollectionDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> quantityOf(String passcode, CardCondition condition) async {
    final entries = await dao.getEntriesForPasscode(passcode);
    return entries
        .where((e) => e.condition == condition)
        .fold<int>(0, (sum, e) => sum + e.quantity);
  }

  group('resolving a row against the local database', () {
    test('a set code and rarity resolve to that exact printing', () async {
      final preview = await importer.preview(
        csv([
          '44095762,Mirror Force,MRD-EN094,Metal Raiders,Super Rare,'
              'POOR,UNLIMITED,EN,1,,,',
        ]),
      );

      final printings = await dao.getEntriesForPasscode('44095762');
      final metalRaiders = printings
          .firstWhere((e) => e.condition == CardCondition.excellent)
          .printingId;
      expect(preview.rows.single.printingId, metalRaiders);
      expect(preview.rows.single.setUnresolved, isFalse);
    });

    test('matching is case- and space-insensitive', () async {
      final preview = await importer.preview(
        csv([
          '44095762,Mirror Force,  mrd-en094 ,,  SUPER RARE ,'
              'POOR,UNLIMITED,EN,1,,,',
        ]),
      );
      expect(preview.rows.single.printingId, isNotNull);
      expect(preview.rows.single.setUnresolved, isFalse);
    });

    test('a set name alone still resolves', () async {
      final preview = await importer.preview(
        csv(['44095762,Mirror Force,,Dark Saviors,,POOR,UNLIMITED,EN,1,,,']),
      );
      expect(preview.rows.single.printingId, isNotNull);
    });

    test('no set columns at all means no printing, and is not an error',
        () async {
      final preview = await importer.preview(
        csv(['46986414,Dark Magician,,,,POOR,UNLIMITED,EN,1,,,']),
      );
      expect(preview.rows.single.printingId, isNull);
      expect(preview.rows.single.setUnresolved, isFalse);
      expect(preview.plan.setsUnresolved, 0);
    });

    // Losing the set is bad; losing the card is worse. The count is reported so
    // the user is told rather than quietly given a setless entry.
    test('an unknown set is imported without one, and counted', () async {
      final preview = await importer.preview(
        csv([
          '46986414,Dark Magician,ZZZ-EN999,Nonexistent Set,Secret Rare,'
              'POOR,UNLIMITED,EN,1,,,',
        ]),
      );

      expect(preview.rows.single.printingId, isNull);
      expect(preview.rows.single.setUnresolved, isTrue);
      expect(preview.plan.setsUnresolved, 1);
      expect(preview.plan.newEntries, 1);
    });

    // `collection_entries.passcode` is a foreign key, so this row could not be
    // inserted even if we wanted to — and it would have no name or art to show.
    test('a passcode the card database does not have is skipped', () async {
      final preview = await importer.preview(
        csv([
          '00000000,Some Card,,,,MINT,UNLIMITED,EN,1,,,',
          '46986414,Dark Magician,,,,POOR,UNLIMITED,EN,1,,,',
        ]),
      );

      expect(preview.unknownCards, 1);
      expect(preview.rows, hasLength(1));
      expect(preview.skipped, 1);
      expect(preview.totalRows, 2);
    });
  });

  group('applying an import', () {
    test('a new entry is added to the collection', () async {
      // The fixture holds Pot of Greed only as POOR/LIMITED, so GOOD is new.
      final preview = await importer.preview(
        csv(['55144522,Pot of Greed,,,,GOOD,UNLIMITED,EN,4,,,']),
      );
      final result = await importer.apply(
        preview,
        ImportMergeStrategy.keepExisting,
      );

      expect(result.entriesAdded, 1);
      expect(result.entriesMerged, 0);
      expect(result.copiesAdded, 4);
      expect(await quantityOf('55144522', CardCondition.good), 4);
      expect(await dao.getEntriesForPasscode('55144522'), hasLength(2));
    });

    // Edition alone is enough to make it a separate entry — the fixture's
    // Pot of Greed is LIMITED, this row is UNLIMITED.
    test('a differing edition does not merge', () async {
      final preview = await importer.preview(
        csv(['55144522,Pot of Greed,,,,POOR,UNLIMITED,EN,1,,,']),
      );
      final result = await importer.apply(
        preview,
        ImportMergeStrategy.sumQuantities,
      );

      expect(result.entriesAdded, 1);
      expect(result.entriesMerged, 0);
      expect(await dao.getEntriesForPasscode('55144522'), hasLength(2));
    });

    // The user's example, end to end: two Dark Magicians at quantity 1 become
    // one Dark Magician at quantity 1.
    test('keepExisting leaves a matching entry exactly as it was', () async {
      expect(await quantityOf('46986414', CardCondition.mint), 1);

      final preview = await importer.preview(
        csv(['46986414,Dark Magician,,,,MINT,UNLIMITED,EN,1,,,']),
      );
      final result = await importer.apply(
        preview,
        ImportMergeStrategy.keepExisting,
      );

      expect(result.entriesMerged, 1);
      expect(result.entriesAdded, 0);
      expect(result.copiesAdded, 0);
      expect(await quantityOf('46986414', CardCondition.mint), 1);
      expect((await dao.getEntriesForPasscode('46986414')), hasLength(1));
    });

    test('sumQuantities adds the copies together', () async {
      final preview = await importer.preview(
        csv(['46986414,Dark Magician,,,,MINT,UNLIMITED,EN,2,,,']),
      );
      final result = await importer.apply(
        preview,
        ImportMergeStrategy.sumQuantities,
      );

      expect(result.entriesMerged, 1);
      expect(result.copiesAdded, 2);
      expect(await quantityOf('46986414', CardCondition.mint), 3);
      expect((await dao.getEntriesForPasscode('46986414')), hasLength(1));
    });

    test('a matching entry is found through its resolved printing', () async {
      final preview = await importer.preview(
        csv([
          '44095762,Mirror Force,MRD-EN094,Metal Raiders,Super Rare,'
              'EXCELLENT,UNLIMITED,EN,5,,,',
        ]),
      );
      await importer.apply(preview, ImportMergeStrategy.sumQuantities);

      expect(await quantityOf('44095762', CardCondition.excellent), 6);
      // Still two Mirror Force rows: the Dark Saviors printing is untouched.
      expect(await dao.getEntriesForPasscode('44095762'), hasLength(2));
    });

    test('a different printing of a held card becomes its own entry', () async {
      final preview = await importer.preview(
        csv([
          '44095762,Mirror Force,DASA-EN059,Dark Saviors,Ultra Rare,'
              'POOR,UNLIMITED,EN,1,,,',
        ]),
      );
      await importer.apply(preview, ImportMergeStrategy.sumQuantities);

      expect(await dao.getEntriesForPasscode('44095762'), hasLength(3));
    });

    test('nothing is written by preview alone', () async {
      await importer.preview(
        csv([
          '55144522,Pot of Greed,,,,GOOD,UNLIMITED,EN,4,,,',
          '46986414,Dark Magician,,,,MINT,UNLIMITED,EN,9,,,',
        ]),
      );

      // The fixture's single Pot of Greed row, and its Dark Magician still at 1.
      expect(await dao.getEntriesForPasscode('55144522'), hasLength(1));
      expect(await quantityOf('46986414', CardCondition.mint), 1);
    });

    test('mixed new and matching rows in one file', () async {
      final preview = await importer.preview(
        csv([
          '46986414,Dark Magician,,,,MINT,UNLIMITED,EN,1,,,',
          '55144522,Pot of Greed,,,,POOR,UNLIMITED,EN,2,,,',
          '00000000,Ghost,,,,MINT,UNLIMITED,EN,1,,,',
        ]),
      );

      expect(preview.plan.newEntries, 1);
      expect(preview.plan.matchedEntries, 1);
      expect(preview.unknownCards, 1);

      final result = await importer.apply(
        preview,
        ImportMergeStrategy.sumQuantities,
      );
      expect(result.entriesAdded, 1);
      expect(result.entriesMerged, 1);
      expect(result.skipped, 1);
    });
  });

  // The property that makes the default strategy safe: exporting the collection
  // and importing it straight back must change nothing at all.
  group('round trip with the exporter', () {
    test('re-importing our own export under keepExisting is a no-op', () async {
      final before = await dao.getAll(filter: const CollectionFilter());
      final source = collectionToCsv(before);

      final preview = await importer.preview(source);
      expect(preview.errors, isEmpty);
      expect(preview.unknownCards, 0);
      expect(preview.plan.setsUnresolved, 0, reason: 'every set must resolve');
      expect(preview.plan.newEntries, 0, reason: 'every row already exists');
      expect(preview.plan.matchedEntries, before.length);

      final result = await importer.apply(
        preview,
        ImportMergeStrategy.keepExisting,
      );
      expect(result.copiesAdded, 0);

      final after = await dao.getAll(filter: const CollectionFilter());
      expect(after.length, before.length);
      for (var i = 0; i < after.length; i++) {
        expect(after[i].entry.quantity, before[i].entry.quantity);
        expect(after[i].entry.printingId, before[i].entry.printingId);
      }
    });

    test('the same round trip under sumQuantities doubles every count',
        () async {
      final before = await dao.getAll(filter: const CollectionFilter());
      final preview = await importer.preview(collectionToCsv(before));
      await importer.apply(preview, ImportMergeStrategy.sumQuantities);

      final after = await dao.getAll(filter: const CollectionFilter());
      expect(after.length, before.length, reason: 'no new rows, only bigger');
      for (var i = 0; i < after.length; i++) {
        expect(after[i].entry.quantity, before[i].entry.quantity * 2);
      }
    });
  });

  test('a file that is not a collection CSV is rejected outright', () async {
    expect(
      () => importer.preview('some,other,file\r\n1,2,3\r\n'),
      throwsA(isA<CsvFormatException>()),
    );
  });
}
