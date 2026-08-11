import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ygo_scanner/data/db/dao/card_dao.dart';
import 'package:ygo_scanner/data/db/dao/printing_dao.dart';
import 'package:ygo_scanner/models/printing.dart';
import 'package:ygo_scanner/models/ygo_card.dart';

import 'test_db.dart';

void main() {
  late Database db;
  late CardDao cardDao;
  late PrintingDao dao;

  const blueEyes = YgoCard(passcode: '89631139', name: 'Blue-Eyes White Dragon');

  setUp(() async {
    db = await openInMemoryTestDb();
    cardDao = CardDao(db);
    dao = PrintingDao(db);
    await cardDao.insertAll([blueEyes]);
  });

  tearDown(() async {
    await db.close();
  });

  test('insertAll then getForPasscode returns all printings for a card', () async {
    await dao.insertAll([
      const Printing(passcode: '89631139', setCode: 'LOB-EN001', rarity: 'Ultra Rare'),
      const Printing(passcode: '89631139', setCode: 'SDK-001', rarity: 'Ultra Rare'),
    ]);

    final printings = await dao.getForPasscode('89631139');

    expect(printings, hasLength(2));
    expect(printings.map((p) => p.setCode), containsAll(['LOB-EN001', 'SDK-001']));
    expect(printings.every((p) => p.id != null), isTrue);
  });

  test('getForPasscode returns an empty list for a card with no printings', () async {
    final printings = await dao.getForPasscode('89631139');
    expect(printings, isEmpty);
  });

  group('getForPasscodes', () {
    const darkMagician = YgoCard(passcode: '46986414', name: 'Dark Magician');

    setUp(() async {
      await cardDao.insertAll([darkMagician]);
      await dao.insertAll([
        const Printing(
          passcode: '89631139',
          setCode: 'LOB-EN001',
          rarity: 'Ultra Rare',
        ),
        const Printing(
          passcode: '89631139',
          setCode: 'SDK-001',
          rarity: 'Ultra Rare',
        ),
        const Printing(
          passcode: '46986414',
          setCode: 'LOB-005',
          rarity: 'Ultra Rare',
        ),
      ]);
    });

    test('returns the printings of every listed card', () async {
      final printings = await dao.getForPasscodes(['89631139', '46986414']);

      expect(printings, hasLength(3));
      expect(
        printings.where((p) => p.passcode == '89631139'),
        hasLength(2),
      );
    });

    test('ignores passcodes with no printings', () async {
      final printings = await dao.getForPasscodes(['46986414', '00000000']);
      expect(printings, hasLength(1));
    });

    // `IN ()` is not valid SQL, and an import of a file with no readable rows
    // reaches this with nothing to look up.
    test('an empty list is not a query at all', () async {
      expect(await dao.getForPasscodes(const []), isEmpty);
    });
  });

  // Backs the Settings default-rarity picker.
  group('distinctRarities', () {
    test('deduplicates and sorts alphabetically', () async {
      await dao.insertAll([
        const Printing(
          passcode: '89631139',
          setCode: 'LOB-EN001',
          rarity: 'Ultra Rare',
        ),
        const Printing(
          passcode: '89631139',
          setCode: 'SDK-001',
          rarity: 'Ultra Rare',
        ),
        const Printing(
          passcode: '89631139',
          setCode: 'SKE-001',
          rarity: 'Common',
        ),
        const Printing(
          passcode: '89631139',
          setCode: 'DPBC-EN001',
          rarity: 'Secret Rare',
        ),
      ]);

      expect(await dao.distinctRarities(), [
        'Common',
        'Secret Rare',
        'Ultra Rare',
      ]);
    });

    // Unlike the collection's rarity *filter*, where a null is the meaningful
    // "no rarity" option, a null here is just a printing whose rarity the sync
    // didn't carry — there is nothing to offer as a default.
    test('drops printings with no rarity', () async {
      await dao.insertAll([
        const Printing(passcode: '89631139', setCode: 'LOB-EN001'),
        const Printing(
          passcode: '89631139',
          setCode: 'SDK-001',
          rarity: 'Common',
        ),
        const Printing(passcode: '89631139', setCode: 'MRD-001', rarity: ''),
      ]);

      expect(await dao.distinctRarities(), ['Common']);
    });

    // A fresh install before the first sync. The picker degrades to its "no
    // preference" row rather than erroring.
    test('an unsynced database offers nothing', () async {
      expect(await dao.distinctRarities(), isEmpty);
    });
  });
}
