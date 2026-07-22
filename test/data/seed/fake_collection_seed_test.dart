import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ygo_scanner/data/db/dao/card_dao.dart';
import 'package:ygo_scanner/data/db/dao/collection_dao.dart';
import 'package:ygo_scanner/data/db/dao/meta_dao.dart';
import 'package:ygo_scanner/data/db/database.dart';
import 'package:ygo_scanner/data/seed/fake_collection_seed.dart';
import 'package:ygo_scanner/models/ygo_card.dart';

import '../db/test_db.dart';

void main() {
  late Database db;

  setUp(() async {
    db = await openInMemoryTestDb();
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'seeds fixture cards and collection entries into an empty database',
    () async {
      await seedFakeCollectionIfEmpty(db);

      expect(await CardDao(db).count(), greaterThan(0));
      expect(await CollectionDao(db).totalCardCount(), greaterThan(0));
    },
  );

  test('is idempotent — running again does not duplicate data', () async {
    await seedFakeCollectionIfEmpty(db);
    final cardCountAfterFirst = await CardDao(db).count();
    final totalAfterFirst = await CollectionDao(db).totalCardCount();

    await seedFakeCollectionIfEmpty(db);

    expect(await CardDao(db).count(), cardCountAfterFirst);
    expect(await CollectionDao(db).totalCardCount(), totalAfterFirst);
  });

  group('debugSeedCollectionProvider', () {
    test('runs the seed on a fresh database (no sync has happened)', () async {
      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWith((ref) async => db)],
      );
      addTearDown(container.dispose);

      await container.read(debugSeedCollectionProvider.future);

      expect(await CollectionDao(db).totalCardCount(), greaterThan(0));
    });

    test(
      'is skipped once a real sync has happened, so it never overwrites '
      'real synced cards',
      () async {
        const realBlueEyes = YgoCard(
          passcode: '89631139',
          name: 'A Real Synced Name',
        );
        await CardDao(db).insertAll([realBlueEyes]);
        await MetaDao(db).set('last_sync', '123456');

        final container = ProviderContainer(
          overrides: [appDatabaseProvider.overrideWith((ref) async => db)],
        );
        addTearDown(container.dispose);

        await container.read(debugSeedCollectionProvider.future);

        expect(await CollectionDao(db).totalCardCount(), 0);
        expect(
          (await CardDao(db).getByPasscode('89631139'))?.name,
          'A Real Synced Name',
        );
      },
    );
  });
}
