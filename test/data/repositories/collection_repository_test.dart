import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ygo_scanner/data/api/card_image_downloader.dart';
import 'package:ygo_scanner/data/db/dao/card_dao.dart';
import 'package:ygo_scanner/data/db/dao/collection_dao.dart';
import 'package:ygo_scanner/data/db/dao/meta_dao.dart';
import 'package:ygo_scanner/data/db/dao/printing_dao.dart';
import 'package:ygo_scanner/data/repositories/card_repository.dart';
import 'package:ygo_scanner/data/repositories/collection_repository.dart';
import 'package:ygo_scanner/models/card_condition.dart';
import 'package:ygo_scanner/models/collection_entry.dart';
import 'package:ygo_scanner/models/ygo_card.dart';

import '../db/test_db.dart';

class _RecordingDownloader implements CardImageDownloader {
  int callCount = 0;
  Object? error;

  @override
  Future<String> download(String passcode, String imageUrl) async {
    callCount++;
    if (error != null) throw error!;
    return '/tmp/$passcode.jpg';
  }
}

void main() {
  late Database db;

  const blueEyes = YgoCard(
    passcode: '89631139',
    name: 'Blue-Eyes White Dragon',
    imageUrl: 'https://images.ygoprodeck.com/images/cards/89631139.jpg',
  );

  setUp(() async {
    db = await openInMemoryTestDb();
    await CardDao(db).insertAll([blueEyes]);
  });

  tearDown(() async {
    await db.close();
  });

  CollectionRepository repositoryWith(_RecordingDownloader downloader) {
    final cardRepository = CardRepository(
      cardDao: CardDao(db),
      printingDao: PrintingDao(db),
      metaDao: MetaDao(db),
      database: db,
      imageDownloader: downloader,
    );
    return CollectionRepository(CollectionDao(db), cardRepository);
  }

  CollectionEntry entry() => CollectionEntry(
    passcode: blueEyes.passcode,
    condition: CardCondition.nearMint,
    createdAt: 1000,
    updatedAt: 1000,
  );

  test('addOrIncrement still writes the entry correctly', () async {
    final repository = repositoryWith(_RecordingDownloader());

    final result = await repository.addOrIncrement(entry());

    expect(result.passcode, blueEyes.passcode);
    expect(result.quantity, 1);
  });

  test(
    'addOrIncrement triggers exactly one image download attempt for the passcode',
    () async {
      final downloader = _RecordingDownloader();
      final repository = repositoryWith(downloader);

      await repository.addOrIncrement(entry());
      // ensureImageDownloaded is fire-and-forget, and sqflite_common_ffi
      // resolves its query via a background isolate — give it real
      // wall-clock time to complete rather than a single zero-duration turn.
      for (var i = 0; i < 20 && downloader.callCount == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      expect(downloader.callCount, 1);
    },
  );

  test(
    "a throwing downloader never breaks addOrIncrement's own success",
    () async {
      final downloader = _RecordingDownloader()..error = StateError('offline');
      final repository = repositoryWith(downloader);

      final result = await repository.addOrIncrement(entry());

      expect(result.quantity, 1);
    },
  );
}
