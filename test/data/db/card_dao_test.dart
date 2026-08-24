import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ygo_scanner/data/db/dao/card_dao.dart';
import 'package:ygo_scanner/data/db/dao/card_name_dao.dart';
import 'package:ygo_scanner/models/ygo_card.dart';

import 'test_db.dart';

void main() {
  late Database db;
  late CardDao dao;

  setUp(() async {
    db = await openInMemoryTestDb();
    dao = CardDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  const blueEyes = YgoCard(
    passcode: '89631139',
    name: 'Blue-Eyes White Dragon',
  );
  const redEyes = YgoCard(passcode: '74677422', name: 'Red-Eyes Black Dragon');
  const toonBlueEyes = YgoCard(
    passcode: '53183600',
    name: 'Toon Blue-Eyes White Dragon',
  );

  test('insertAll then getByPasscode round-trips a card', () async {
    await dao.insertAll([blueEyes]);

    final result = await dao.getByPasscode(blueEyes.passcode);

    expect(result, blueEyes);
  });

  test('getByPasscode returns null for an unknown passcode', () async {
    final result = await dao.getByPasscode('00000000');
    expect(result, isNull);
  });

  group('getByPasscodes', () {
    test('returns every existing row and omits unknown passcodes', () async {
      await dao.insertAll([blueEyes, redEyes, toonBlueEyes]);

      final results = await dao.getByPasscodes([
        blueEyes.passcode,
        '00000000', // not in the table
        redEyes.passcode,
      ]);

      expect(
        results.map((c) => c.passcode),
        unorderedEquals([blueEyes.passcode, redEyes.passcode]),
      );
    });

    test('returns empty for an empty list', () async {
      await dao.insertAll([blueEyes]);

      // Guards the `IN ()` path: an empty candidate list is normal (nothing
      // detected in the frame) and must not reach SQLite as invalid SQL.
      expect(await dao.getByPasscodes(const []), isEmpty);
    });

    test('tolerates arbitrary non-numeric passcode strings', () async {
      await dao.insertAll([blueEyes]);

      // The artwork index keys every alt-art image id, so it can hand us keys
      // that are not in `cards` at all — and a test fake can hand us keys that
      // are not even digits. `passcode` is a TEXT column; neither may throw.
      final results = await dao.getByPasscodes([
        blueEyes.passcode,
        'not_in_db',
        "o'brien",
      ]);

      expect(results.map((c) => c.passcode), [blueEyes.passcode]);
    });

    test('a duplicated passcode yields one row', () async {
      await dao.insertAll([blueEyes]);

      final results = await dao.getByPasscodes([
        blueEyes.passcode,
        blueEyes.passcode,
      ]);

      expect(results, [blueEyes]);
    });
  });

  test('count reflects the number of inserted cards', () async {
    await dao.insertAll([blueEyes, redEyes]);
    expect(await dao.count(), 2);
  });

  test(
    'searchByName ranks prefix matches above substring-only matches',
    () async {
      await dao.insertAll([toonBlueEyes, redEyes, blueEyes]);

      final results = await dao.searchByName('Blue-Eyes');

      expect(results.map((c) => c.name), [
        'Blue-Eyes White Dragon',
        'Toon Blue-Eyes White Dragon',
      ]);
    },
  );

  group('searchByLocalizedName', () {
    Future<void> seedItalian() async {
      await dao.insertAll([toonBlueEyes, redEyes, blueEyes]);
      await CardNameDao(db).insertAll(const [
        CardName(
          passcode: '89631139',
          language: 'IT',
          name: 'Drago Bianco Occhi Blu',
        ),
        CardName(
          passcode: '53183600',
          language: 'IT',
          name: 'Drago Bianco Occhi Blu Cartoon',
        ),
        CardName(
          passcode: '74677422',
          language: 'IT',
          name: 'Drago Nero Occhi Rossi',
        ),
      ]);
    }

    test('ranks prefix matches above substring-only ones, on the '
        'localized name', () async {
      await seedItalian();

      final results = await dao.searchByLocalizedName(
        'Drago Bianco',
        language: 'IT',
      );

      // Both match; only the exact-prefix one may lead. Ordering on `c.name`
      // would put "Toon Blue-Eyes..." after "Blue-Eyes..." by accident of the
      // English alphabet rather than by what was typed.
      expect(results.map((h) => h.card.passcode), ['89631139', '53183600']);
    });

    test('carries the matched name, and the English card beside it', () async {
      await seedItalian();

      final results = await dao.searchByLocalizedName(
        'Occhi Rossi',
        language: 'IT',
      );

      expect(results.single.card.name, 'Red-Eyes Black Dragon');
      expect(results.single.localizedName, 'Drago Nero Occhi Rossi');
    });

    test('a name row with no cards row never surfaces', () async {
      // The asset is built from YGOPRODeck's Italian dump and the `cards` table
      // from its English one; the two do not cover exactly the same passcodes,
      // and a card with no local row has no type, art or price to show.
      await CardNameDao(db).insertAll(const [
        CardName(passcode: '00000000', language: 'IT', name: 'Fantasma'),
      ]);

      expect(
        await dao.searchByLocalizedName('Fantasma', language: 'IT'),
        isEmpty,
      );
    });

    test('a different language does not match', () async {
      await seedItalian();

      expect(await dao.searchByLocalizedName('Drago', language: 'FR'), isEmpty);
    });
  });

  test(
    'updateLocalImagePath sets the column, reflected by getByPasscode',
    () async {
      await dao.insertAll([blueEyes]);

      await dao.updateLocalImagePath(blueEyes.passcode, '/tmp/89631139.jpg');

      final result = await dao.getByPasscode(blueEyes.passcode);
      expect(result?.localImagePath, '/tmp/89631139.jpg');
    },
  );

  test('updateLocalImagePath is a no-op for an unknown passcode', () async {
    await expectLater(
      dao.updateLocalImagePath('00000000', '/tmp/00000000.jpg'),
      completes,
    );
  });
}
