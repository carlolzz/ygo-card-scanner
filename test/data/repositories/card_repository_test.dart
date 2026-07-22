import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ygo_scanner/data/api/card_image_downloader.dart';
import 'package:ygo_scanner/data/api/ygoprodeck_client.dart';
import 'package:ygo_scanner/data/db/dao/card_dao.dart';
import 'package:ygo_scanner/data/db/dao/meta_dao.dart';
import 'package:ygo_scanner/data/db/dao/printing_dao.dart';
import 'package:ygo_scanner/data/repositories/card_repository.dart';
import 'package:ygo_scanner/models/ygo_card.dart';

import '../db/test_db.dart';

/// Hand-rolled fake transport — no mocking package needed. Returns a small
/// canned `cardinfo.php`-shaped payload regardless of the request, with a
/// `content-length` header so `onReceiveProgress`'s `total` is meaningful.
class _FakeCardinfoAdapter implements HttpClientAdapter {
  _FakeCardinfoAdapter(this.responseJson);

  final Map<String, Object?> responseJson;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final bytes = utf8.encode(jsonEncode(responseJson));
    return ResponseBody.fromBytes(
      bytes,
      200,
      headers: {
        Headers.contentLengthHeader: ['${bytes.length}'],
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _FakeDownloader implements CardImageDownloader {
  _FakeDownloader({this.result, this.error});

  String? result;
  Object? error;
  int callCount = 0;

  @override
  Future<String> download(String passcode, String imageUrl) async {
    callCount++;
    if (error != null) throw error!;
    return result!;
  }
}

void main() {
  late Database db;
  late CardDao cardDao;

  const cardWithImage = YgoCard(
    passcode: '89631139',
    name: 'Blue-Eyes White Dragon',
    imageUrl: 'https://images.ygoprodeck.com/images/cards/89631139.jpg',
  );
  const cardWithoutImage = YgoCard(
    passcode: '74677422',
    name: 'Red-Eyes Black Dragon',
  );

  setUp(() async {
    db = await openInMemoryTestDb();
    cardDao = CardDao(db);
    await cardDao.insertAll([cardWithImage, cardWithoutImage]);
  });

  tearDown(() async {
    await db.close();
  });

  CardRepository repositoryWith(_FakeDownloader downloader) => CardRepository(
    cardDao: cardDao,
    printingDao: PrintingDao(db),
    metaDao: MetaDao(db),
    database: db,
    imageDownloader: downloader,
  );

  test('ensureImageDownloaded no-ops when the card has no imageUrl', () async {
    final downloader = _FakeDownloader(result: '/tmp/should-not-be-used.jpg');
    final repository = repositoryWith(downloader);

    await repository.ensureImageDownloaded(cardWithoutImage.passcode);

    expect(downloader.callCount, 0);
    expect(
      (await cardDao.getByPasscode(cardWithoutImage.passcode))?.localImagePath,
      isNull,
    );
  });

  test('ensureImageDownloaded downloads and persists the path on success', () async {
    final downloader = _FakeDownloader(result: '/tmp/89631139.jpg');
    final repository = repositoryWith(downloader);

    await repository.ensureImageDownloaded(cardWithImage.passcode);

    expect(downloader.callCount, 1);
    expect(
      (await cardDao.getByPasscode(cardWithImage.passcode))?.localImagePath,
      '/tmp/89631139.jpg',
    );
  });

  test(
    'ensureImageDownloaded no-ops when a local path is already set and the '
    'file still exists',
    () async {
      final dir = await Directory.systemTemp.createTemp('card_repo_test');
      final file = File('${dir.path}/89631139.jpg');
      await file.writeAsBytes([0xFF, 0xD8, 0xFF, 0xD9]);
      addTearDown(() => dir.delete(recursive: true));

      await cardDao.updateLocalImagePath(cardWithImage.passcode, file.path);
      final downloader = _FakeDownloader(result: '/tmp/should-not-be-used.jpg');
      final repository = repositoryWith(downloader);

      await repository.ensureImageDownloaded(cardWithImage.passcode);

      expect(downloader.callCount, 0);
      expect(
        (await cardDao.getByPasscode(cardWithImage.passcode))?.localImagePath,
        file.path,
      );
    },
  );

  test('ensureImageDownloaded swallows exceptions from a failing downloader', () async {
    final downloader = _FakeDownloader(error: StateError('network down'));
    final repository = repositoryWith(downloader);

    await expectLater(
      repository.ensureImageDownloaded(cardWithImage.passcode),
      completes,
    );
    expect(
      (await cardDao.getByPasscode(cardWithImage.passcode))?.localImagePath,
      isNull,
    );
  });

  group('needsSync', () {
    test('true when no sync has ever run (fresh db, even with seed cards)', () async {
      final repository = repositoryWith(_FakeDownloader());
      expect(await repository.needsSync(), isTrue);
    });

    test('false once last_sync is stamped and cards exist', () async {
      await MetaDao(db).set('last_sync', '123456');
      final repository = repositoryWith(_FakeDownloader());
      expect(await repository.needsSync(), isFalse);
    });

    test('true if last_sync is stamped but cards table is empty', () async {
      final emptyDb = await openInMemoryTestDb();
      await MetaDao(emptyDb).set('last_sync', '123456');
      final repository = CardRepository(
        cardDao: CardDao(emptyDb),
        printingDao: PrintingDao(emptyDb),
        metaDao: MetaDao(emptyDb),
        database: emptyDb,
      );

      expect(await repository.needsSync(), isTrue);
      await emptyDb.close();
    });
  });

  group('sync', () {
    test('fetches, writes cards/printings, and stamps last_sync', () async {
      final client = YgoProdeckClient(
        dio: Dio(BaseOptions(baseUrl: 'https://db.ygoprodeck.com/api/v7'))
          ..httpClientAdapter = _FakeCardinfoAdapter({
            'data': [
              {
                'id': 10000000,
                'name': 'Fake Card One',
                'type': 'Normal Monster',
                'frameType': 'normal',
                'attribute': 'LIGHT',
                'race': 'Dragon',
                'atk': 1000,
                'def': 1000,
                'level': 4,
                'desc': 'A fake card.',
                'card_images': [
                  {'image_url': 'https://images.ygoprodeck.com/1.jpg'},
                ],
                'archetype': null,
                'card_sets': [
                  {
                    'set_code': 'FAKE-EN001',
                    'set_name': 'Fake Set',
                    'set_rarity': 'Common',
                  },
                ],
              },
              {
                'id': 10000001,
                'name': 'Fake Card Two',
                'card_images': <Object?>[],
                'card_sets': <Object?>[],
              },
            ],
          }),
      );
      final freshDb = await openInMemoryTestDb();
      final repository = CardRepository(
        cardDao: CardDao(freshDb),
        printingDao: PrintingDao(freshDb),
        metaDao: MetaDao(freshDb),
        database: freshDb,
        client: client,
      );

      final events = await repository.sync().toList();

      expect(events, isNotEmpty);
      expect(events.any((e) => e.phase == SyncPhase.fetching), isTrue);
      expect(events.any((e) => e.phase == SyncPhase.writing), isTrue);
      expect(events.last.fraction, 1);

      expect(await CardDao(freshDb).count(), 2);
      final printings = await PrintingDao(freshDb).getForPasscode('10000000');
      expect(printings, hasLength(1));
      expect(printings.single.setCode, 'FAKE-EN001');
      expect(await MetaDao(freshDb).get('last_sync'), isNotNull);

      await freshDb.close();
    });
  });
}
