import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ygo_scanner/data/db/dao/card_dao.dart';
import 'package:ygo_scanner/data/db/dao/collection_dao.dart';
import 'package:ygo_scanner/data/db/dao/printing_dao.dart';
import 'package:ygo_scanner/models/card_condition.dart';
import 'package:ygo_scanner/models/card_edition.dart';
import 'package:ygo_scanner/models/collection_entry.dart';
import 'package:ygo_scanner/models/printing.dart';
import 'package:ygo_scanner/models/ygo_card.dart';

import 'test_db.dart';

const _blueEyes = YgoCard(
  passcode: '89631139',
  name: 'Blue-Eyes White Dragon',
  type: 'Normal Monster',
);
const _redEyes = YgoCard(
  passcode: '74677422',
  name: 'Red-Eyes Black Dragon',
  type: 'Effect Monster',
);

CollectionEntry _entry({
  required String passcode,
  int? printingId,
  required CardCondition condition,
  CardEdition edition = CardEdition.unlimited,
  String language = 'EN',
  int quantity = 1,
  int createdAt = 1000,
  int updatedAt = 1000,
}) {
  return CollectionEntry(
    passcode: passcode,
    printingId: printingId,
    condition: condition,
    edition: edition,
    language: language,
    quantity: quantity,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

void main() {
  late Database db;
  late CardDao cardDao;
  late PrintingDao printingDao;
  late CollectionDao collectionDao;

  setUp(() async {
    db = await openInMemoryTestDb();
    cardDao = CardDao(db);
    printingDao = PrintingDao(db);
    collectionDao = CollectionDao(db);
    await cardDao.insertAll([_blueEyes, _redEyes]);
  });

  tearDown(() async {
    await db.close();
  });

  test('addOrIncrement inserts a new row, then increments in place', () async {
    await printingDao.insertAll([
      const Printing(passcode: '89631139', setCode: 'LOB-EN001', rarity: 'Ultra Rare'),
    ]);
    final printing = (await printingDao.getForPasscode('89631139')).single;

    final first = await collectionDao.addOrIncrement(
      _entry(
        passcode: _blueEyes.passcode,
        printingId: printing.id,
        condition: CardCondition.nearMint,
        quantity: 2,
        createdAt: 1000,
        updatedAt: 1000,
      ),
    );
    expect(first.quantity, 2);
    expect(first.id, isNotNull);

    final second = await collectionDao.addOrIncrement(
      _entry(
        passcode: _blueEyes.passcode,
        printingId: printing.id,
        condition: CardCondition.nearMint,
        quantity: 3,
        createdAt: 1000,
        updatedAt: 2000,
      ),
    );

    expect(second.id, first.id);
    expect(second.quantity, 5);
    expect(second.createdAt, 1000);
    expect(second.updatedAt, 2000);

    final all = await collectionDao.getEntriesForPasscode(_blueEyes.passcode);
    expect(all, hasLength(1));
  });

  test('different condition on the same card creates a separate row', () async {
    await printingDao.insertAll([
      const Printing(passcode: '89631139', setCode: 'LOB-EN001', rarity: 'Ultra Rare'),
    ]);
    final printing = (await printingDao.getForPasscode('89631139')).single;

    await collectionDao.addOrIncrement(
      _entry(
        passcode: _blueEyes.passcode,
        printingId: printing.id,
        condition: CardCondition.nearMint,
      ),
    );
    await collectionDao.addOrIncrement(
      _entry(
        passcode: _blueEyes.passcode,
        printingId: printing.id,
        condition: CardCondition.lightPlayed,
      ),
    );

    final all = await collectionDao.getEntriesForPasscode(_blueEyes.passcode);
    expect(all, hasLength(2));
    expect(all.map((e) => e.condition).toSet(), {
      CardCondition.nearMint,
      CardCondition.lightPlayed,
    });
  });

  test(
    'addOrIncrement with a null printingId still increments instead of duplicating '
    '(NULL is distinct under UNIQUE, so this cannot rely on ON CONFLICT alone)',
    () async {
      await collectionDao.addOrIncrement(
        _entry(passcode: _blueEyes.passcode, condition: CardCondition.mint, quantity: 1),
      );
      await collectionDao.addOrIncrement(
        _entry(passcode: _blueEyes.passcode, condition: CardCondition.mint, quantity: 4),
      );

      final all = await collectionDao.getEntriesForPasscode(_blueEyes.passcode);
      expect(all, hasLength(1));
      expect(all.single.quantity, 5);
    },
  );

  test('setQuantity(0) removes the row', () async {
    final added = await collectionDao.addOrIncrement(
      _entry(passcode: _blueEyes.passcode, condition: CardCondition.good, quantity: 2),
    );

    await collectionDao.setQuantity(added.id!, 0);

    final all = await collectionDao.getEntriesForPasscode(_blueEyes.passcode);
    expect(all, isEmpty);
  });

  test('decrement reduces quantity by one and setQuantity above 0 updates in place', () async {
    final added = await collectionDao.addOrIncrement(
      _entry(passcode: _blueEyes.passcode, condition: CardCondition.poor, quantity: 3),
    );

    await collectionDao.decrement(added.id!);

    final all = await collectionDao.getEntriesForPasscode(_blueEyes.passcode);
    expect(all.single.quantity, 2);
  });

  test('foreign key violation is rejected when the passcode does not exist', () async {
    final fkStatus = await db.rawQuery('PRAGMA foreign_keys');
    expect(fkStatus.first['foreign_keys'], 1);

    expect(
      () => collectionDao.addOrIncrement(
        _entry(passcode: '00000000', condition: CardCondition.mint),
      ),
      throwsA(isA<DatabaseException>()),
    );
  });

  group('getAll filter and sort combinations', () {
    setUp(() async {
      await collectionDao.addOrIncrement(
        _entry(
          passcode: _blueEyes.passcode,
          condition: CardCondition.nearMint,
          quantity: 3,
          createdAt: 1000,
          updatedAt: 1000,
        ),
      );
      await collectionDao.addOrIncrement(
        _entry(
          passcode: _blueEyes.passcode,
          condition: CardCondition.mint,
          quantity: 1,
          createdAt: 2000,
          updatedAt: 2000,
        ),
      );
      await collectionDao.addOrIncrement(
        _entry(
          passcode: _redEyes.passcode,
          condition: CardCondition.lightPlayed,
          edition: CardEdition.first,
          quantity: 5,
          createdAt: 3000,
          updatedAt: 3000,
        ),
      );
    });

    test('default sort (name ascending) orders Blue-Eyes before Red-Eyes', () async {
      final results = await collectionDao.getAll();
      expect(results, hasLength(3));
      expect(results.first.card.name, 'Blue-Eyes White Dragon');
      expect(results.last.card.name, 'Red-Eyes Black Dragon');
    });

    test('sort by dateAdded ascending/descending follows created_at', () async {
      final asc = await collectionDao.getAll(
        filter: const CollectionFilter(sortBy: CollectionSortBy.dateAdded),
      );
      expect(asc.map((r) => r.entry.quantity), [3, 1, 5]);

      final desc = await collectionDao.getAll(
        filter: const CollectionFilter(
          sortBy: CollectionSortBy.dateAdded,
          sortDescending: true,
        ),
      );
      expect(desc.map((r) => r.entry.quantity), [5, 1, 3]);
    });

    test('sort by quantity ascending', () async {
      final results = await collectionDao.getAll(
        filter: const CollectionFilter(sortBy: CollectionSortBy.quantity),
      );
      expect(results.map((r) => r.entry.quantity), [1, 3, 5]);
    });

    test('filter by cardType isolates matching rows', () async {
      final results = await collectionDao.getAll(
        filter: const CollectionFilter(cardType: 'Effect Monster'),
      );
      expect(results, hasLength(1));
      expect(results.single.card.name, 'Red-Eyes Black Dragon');
    });

    test('filter by condition isolates matching rows', () async {
      final results = await collectionDao.getAll(
        filter: const CollectionFilter(condition: CardCondition.nearMint),
      );
      expect(results, hasLength(1));
      expect(results.single.entry.quantity, 3);
    });

    test('filter by "no rarity" keeps rows with no printing', () async {
      final results = await collectionDao.getAll(
        filter: const CollectionFilter(rarity: RarityFilter.noRarity()),
      );
      // None of these three entries has a printing, so none carries a rarity —
      // and they must still be reachable by a filter, not only under "All".
      expect(results, hasLength(3));
    });

    test('filter by name substring isolates matching rows', () async {
      final results = await collectionDao.getAll(
        filter: const CollectionFilter(nameQuery: 'Red'),
      );
      expect(results, hasLength(1));
      expect(results.single.card.name, 'Red-Eyes Black Dragon');
    });

    test('combined filter + sort narrows and orders correctly', () async {
      final results = await collectionDao.getAll(
        filter: const CollectionFilter(
          cardType: 'Normal Monster',
          sortBy: CollectionSortBy.quantity,
          sortDescending: true,
        ),
      );
      expect(results.map((r) => r.entry.quantity), [3, 1]);
    });

    test('totalCardCount sums quantity and distinctCardCount counts unique passcodes', () async {
      expect(await collectionDao.totalCardCount(), 9);
      expect(await collectionDao.distinctCardCount(), 2);
    });
  });

  group('rarity filter', () {
    setUp(() async {
      await printingDao.insertAll([
        const Printing(
          passcode: '89631139',
          setCode: 'LOB-EN001',
          setName: 'Legend of Blue Eyes White Dragon',
          rarity: 'Ultra Rare',
        ),
        const Printing(
          passcode: '74677422',
          setCode: 'MRD-EN094',
          setName: 'Metal Raiders',
          rarity: 'Super Rare',
        ),
      ]);
      final blueEyesPrinting =
          (await printingDao.getForPasscode('89631139')).single;
      final redEyesPrinting =
          (await printingDao.getForPasscode('74677422')).single;

      await collectionDao.addOrIncrement(
        _entry(
          passcode: _blueEyes.passcode,
          printingId: blueEyesPrinting.id,
          condition: CardCondition.nearMint,
        ),
      );
      await collectionDao.addOrIncrement(
        _entry(
          passcode: _redEyes.passcode,
          printingId: redEyesPrinting.id,
          condition: CardCondition.good,
        ),
      );
      // A third entry with no printing at all — the scanned-quick-log shape,
      // which carries no rarity.
      await collectionDao.addOrIncrement(
        _entry(passcode: _redEyes.passcode, condition: CardCondition.poor),
      );
    });

    test('filter by a rarity value isolates matching rows', () async {
      final results = await collectionDao.getAll(
        filter: const CollectionFilter(
          rarity: RarityFilter.value('Super Rare'),
        ),
      );
      expect(results, hasLength(1));
      expect(results.single.printing!.setCode, 'MRD-EN094');
    });

    test('filter by "no rarity" isolates the entry with no printing', () async {
      final results = await collectionDao.getAll(
        filter: const CollectionFilter(rarity: RarityFilter.noRarity()),
      );
      expect(results, hasLength(1));
      expect(results.single.entry.condition, CardCondition.poor);
      expect(results.single.printing, isNull);
    });

    test('rarityFilterOptions reports held rarities, null first', () async {
      // SQLite orders NULL first, so the "no rarity" option leads — and it is
      // present only because an entry without a printing exists, which is what
      // keeps the filter row from ever offering a dead chip.
      expect(await collectionDao.rarityFilterOptions(), [
        null,
        'Super Rare',
        'Ultra Rare',
      ]);
    });

    test('rarityFilterOptions omits null when every entry has a rarity',
        () async {
      final noRarity = await collectionDao.getAll(
        filter: const CollectionFilter(rarity: RarityFilter.noRarity()),
      );
      await collectionDao.delete(noRarity.single.entry.id!);

      expect(await collectionDao.rarityFilterOptions(), [
        'Super Rare',
        'Ultra Rare',
      ]);
    });
  });

  group('statistics aggregates', () {
    setUp(() async {
      // Same card in two languages -> two rows under one passcode (passcodes
      // are language-independent). Plus a second card in a different type.
      await collectionDao.addOrIncrement(
        _entry(
          passcode: _blueEyes.passcode,
          condition: CardCondition.nearMint,
          language: 'EN',
          quantity: 3,
        ),
      );
      await collectionDao.addOrIncrement(
        _entry(
          passcode: _blueEyes.passcode,
          condition: CardCondition.nearMint,
          language: 'DE',
          quantity: 2,
        ),
      );
      await collectionDao.addOrIncrement(
        _entry(
          passcode: _redEyes.passcode,
          condition: CardCondition.lightPlayed,
          language: 'EN',
          quantity: 5,
        ),
      );
    });

    test('sumByCondition sums quantity per condition db value', () async {
      expect(await collectionDao.sumByCondition(), {
        'NEAR_MINT': 5,
        'LIGHT_PLAYED': 5,
      });
    });

    test('sumByLanguage sums quantity per language code', () async {
      expect(await collectionDao.sumByLanguage(), {'EN': 8, 'DE': 2});
    });

    test('sumByCardType sums quantity per joined cards.type', () async {
      expect(await collectionDao.sumByCardType(), {
        'Normal Monster': 5,
        'Effect Monster': 5,
      });
    });
  });

  group('getAll printing join', () {
    test('entry with a printing_id returns a populated Printing', () async {
      await printingDao.insertAll([
        const Printing(passcode: '89631139', setCode: 'LOB-EN001', setName: 'Legend of Blue Eyes White Dragon', rarity: 'Ultra Rare'),
      ]);
      final printing = (await printingDao.getForPasscode('89631139')).single;

      await collectionDao.addOrIncrement(
        _entry(
          passcode: _blueEyes.passcode,
          printingId: printing.id,
          condition: CardCondition.nearMint,
        ),
      );

      final results = await collectionDao.getAll();
      expect(results.single.printing, isNotNull);
      expect(results.single.printing!.setCode, 'LOB-EN001');
      expect(results.single.printing!.setName, 'Legend of Blue Eyes White Dragon');
      expect(results.single.printing!.rarity, 'Ultra Rare');
    });

    test('entry with a null printing_id returns a null Printing', () async {
      await collectionDao.addOrIncrement(
        _entry(passcode: _blueEyes.passcode, condition: CardCondition.mint),
      );

      final results = await collectionDao.getAll();
      expect(results.single.printing, isNull);
    });

    test(
      'two entries sharing a passcode but different printing_id stay '
      'distinct rows with distinct printing data',
      () async {
        await printingDao.insertAll([
          const Printing(passcode: '89631139', setCode: 'MRD-EN094', setName: 'Metal Raiders', rarity: 'Super Rare'),
          const Printing(passcode: '89631139', setCode: 'DASA-EN059', setName: 'Dark Saviors', rarity: 'Ultra Rare'),
        ]);
        final printings = await printingDao.getForPasscode('89631139');
        final mrd = printings.firstWhere((p) => p.setCode == 'MRD-EN094');
        final dasa = printings.firstWhere((p) => p.setCode == 'DASA-EN059');

        await collectionDao.addOrIncrement(
          _entry(passcode: _blueEyes.passcode, printingId: mrd.id, condition: CardCondition.nearMint),
        );
        await collectionDao.addOrIncrement(
          _entry(passcode: _blueEyes.passcode, printingId: dasa.id, condition: CardCondition.nearMint),
        );

        final results = await collectionDao.getAll();
        expect(results, hasLength(2));
        expect(
          results.map((r) => r.printing!.setCode).toSet(),
          {'MRD-EN094', 'DASA-EN059'},
        );
      },
    );
  });

  test('getAll surfaces a card\'s local_image_path through the join', () async {
    await cardDao.updateLocalImagePath(_blueEyes.passcode, '/tmp/89631139.jpg');
    await collectionDao.addOrIncrement(
      _entry(passcode: _blueEyes.passcode, condition: CardCondition.mint),
    );

    final results = await collectionDao.getAll();

    expect(results.single.card.localImagePath, '/tmp/89631139.jpg');
  });

  group('updateEntryDetails', () {
    test('no collision updates in place and returns the same id', () async {
      final added = await collectionDao.addOrIncrement(
        _entry(
          passcode: _blueEyes.passcode,
          condition: CardCondition.nearMint,
          language: 'EN',
          quantity: 2,
        ),
      );

      final survivorId = await collectionDao.updateEntryDetails(
        added.id!,
        printingId: null,
        condition: CardCondition.lightPlayed,
        edition: CardEdition.first,
        language: 'DE',
      );

      expect(survivorId, added.id);
      final all = await collectionDao.getEntriesForPasscode(_blueEyes.passcode);
      expect(all, hasLength(1));
      final row = all.single;
      expect(row.id, added.id);
      expect(row.condition, CardCondition.lightPlayed);
      expect(row.edition, CardEdition.first);
      expect(row.language, 'DE');
      expect(row.quantity, 2, reason: 'a plain edit must not change quantity');
    });

    test(
      'editing an entry into another entry\'s exact key merges quantities '
      'and deletes the edited row, returning the survivor id',
      () async {
        // Target: NM / EN, qty 3. Source: NM / DE, qty 2. Editing the source to
        // EN collides with the target -> merge into one NM/EN row of qty 5.
        final target = await collectionDao.addOrIncrement(
          _entry(
            passcode: _blueEyes.passcode,
            condition: CardCondition.nearMint,
            language: 'EN',
            quantity: 3,
          ),
        );
        final source = await collectionDao.addOrIncrement(
          _entry(
            passcode: _blueEyes.passcode,
            condition: CardCondition.nearMint,
            language: 'DE',
            quantity: 2,
          ),
        );

        final survivorId = await collectionDao.updateEntryDetails(
          source.id!,
          printingId: null,
          condition: CardCondition.nearMint,
          edition: CardEdition.unlimited,
          language: 'EN',
        );

        expect(survivorId, target.id);
        final all = await collectionDao.getEntriesForPasscode(
          _blueEyes.passcode,
        );
        expect(all, hasLength(1), reason: 'the two rows collapse into one');
        expect(all.single.id, target.id);
        expect(all.single.quantity, 5);
        expect(all.single.language, 'EN');
      },
    );

    test(
      'merge works across printing_id when the target has a real printing '
      '(NULL vs non-NULL keys are handled)',
      () async {
        await printingDao.insertAll([
          const Printing(
            passcode: '89631139',
            setCode: 'LOB-EN001',
            rarity: 'Ultra Rare',
          ),
        ]);
        final printing = (await printingDao.getForPasscode('89631139')).single;

        final target = await collectionDao.addOrIncrement(
          _entry(
            passcode: _blueEyes.passcode,
            printingId: printing.id,
            condition: CardCondition.nearMint,
            quantity: 1,
          ),
        );
        final source = await collectionDao.addOrIncrement(
          _entry(
            passcode: _blueEyes.passcode,
            condition: CardCondition.nearMint,
            quantity: 4,
          ),
        );

        final survivorId = await collectionDao.updateEntryDetails(
          source.id!,
          printingId: printing.id,
          condition: CardCondition.nearMint,
          edition: CardEdition.unlimited,
          language: 'EN',
        );

        expect(survivorId, target.id);
        final all = await collectionDao.getEntriesForPasscode(
          _blueEyes.passcode,
        );
        expect(all, hasLength(1));
        expect(all.single.quantity, 5);
        expect(all.single.printingId, printing.id);
      },
    );
  });
}
