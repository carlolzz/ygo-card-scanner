import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Rect;
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ygo_scanner/core/theme/tokens.dart';
import 'package:ygo_scanner/data/db/dao/card_dao.dart';
import 'package:ygo_scanner/data/db/dao/meta_dao.dart';
import 'package:ygo_scanner/data/db/dao/printing_dao.dart';
import 'package:ygo_scanner/data/repositories/card_repository.dart';
import 'package:ygo_scanner/data/seed/fake_collection_seed.dart';
import 'package:ygo_scanner/features/scan/art_frame.dart';
import 'package:ygo_scanner/features/scan/art_matcher.dart';
import 'package:ygo_scanner/features/scan/camera_service.dart';
import 'package:ygo_scanner/features/scan/card_detector.dart';
import 'package:ygo_scanner/features/scan/hamming.dart';
import 'package:ygo_scanner/features/scan/hash_index.dart';
import 'package:ygo_scanner/features/scan/phash.dart';

import '../../data/db/test_db.dart';

const darkMagician = '46986414';

/// Minimal [CameraService] that only surfaces a fixed [ArtFrame] — no hardware.
class _FakeCamera implements CameraService {
  _FakeCamera(this._frame);
  final ArtFrame? _frame;
  final ValueNotifier<CameraController?> _preview =
      ValueNotifier<CameraController?>(null);

  @override
  ArtFrame? get latestArtFrame => _frame;

  @override
  Stream<InputImage> get frames => const Stream<InputImage>.empty();

  @override
  ValueListenable<CameraController?> get preview => _preview;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

/// Reproduces the pre-OpenCV behaviour (orient only, no card detection) so the
/// existing hash assertions still hold without loading the OpenCV native
/// library, which doesn't load on the host.
class _IdentityCardDetector implements CardDetector {
  const _IdentityCardDetector();
  @override
  ArtFrame? detectCard(ArtFrame frame) => frame.oriented();
}

/// Builds a synthetic upright luma frame with enough structure that its pHash is
/// non-degenerate.
ArtFrame syntheticFrame({int width = 120, int height = 168}) {
  final luma = Uint8List(width * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      luma[y * width + x] = (x * 2 + y) % 256;
    }
  }
  return ArtFrame(luma: luma, width: width, height: height);
}

/// Replicates [PHashArtMatcher]'s internal crop so the test can predict the hash
/// the matcher will produce for a given frame.
PerceptualHash expectedHash(ArtFrame frame, Rect roi) {
  final f = frame.oriented();
  final left = (roi.left * f.width).round();
  final top = (roi.top * f.height).round();
  final right = (roi.right * f.width).round();
  final bottom = (roi.bottom * f.height).round();
  return phashFromLuma(
    f.luma,
    f.width,
    f.height,
    crop: PixelRect(left, top, right - left, bottom - top),
  );
}

void main() {
  late Database db;
  late CardRepository repository;

  setUp(() async {
    db = await openInMemoryTestDb();
    await seedFakeCollectionIfEmpty(db);
    repository = CardRepository(
      cardDao: CardDao(db),
      printingDao: PrintingDao(db),
      metaDao: MetaDao(db),
      database: db,
    );
  });

  tearDown(() async => db.close());

  test('ranks the nearest card and resolves it via the repository', () async {
    final frame = syntheticFrame();
    final hash = expectedHash(frame, ArtMatchTuning.artBoxRoi);
    final index = HashIndex(
      version: 1,
      algorithm: 'phash',
      hashSize: 8,
      hashes: {
        darkMagician: hash, // distance 0 to the frame, and it is in the db
        'not_in_db': hash, // equally close but has no cards row -> skipped
        'far': PerceptualHash(~hash.hi & 0xffffffff, ~hash.lo & 0xffffffff),
      },
    );

    final matcher = PHashArtMatcher(
      camera: _FakeCamera(frame),
      index: index,
      repository: repository,
      detector: const _IdentityCardDetector(),
    );
    final candidates = await matcher.match();

    // 'far' is beyond the threshold; 'not_in_db' resolves to null and is
    // dropped; only the real card survives.
    expect(candidates, hasLength(1));
    expect(candidates.first.card.passcode, darkMagician);
    expect(candidates.first.distance, 0);
  });

  test('rankFrame ranks near hits (DB or not) with no repository read',
      () {
    final frame = syntheticFrame();
    final hash = expectedHash(frame, ArtMatchTuning.artBoxRoi);
    final index = HashIndex(
      version: 1,
      algorithm: 'phash',
      hashSize: 8,
      hashes: {
        darkMagician: hash, // in the db
        'not_in_db': hash, // equally close, but no cards row
        'far': PerceptualHash(~hash.hi & 0xffffffff, ~hash.lo & 0xffffffff),
      },
    );
    final matcher = PHashArtMatcher(
      camera: _FakeCamera(frame),
      index: index,
      repository: repository,
      detector: const _IdentityCardDetector(),
    );

    final result = matcher.rankFrame();
    final ranked = result.matches;

    expect(result.status, ArtFrameStatus.detected);
    // Pure ranking keeps every near hit — the DB filter lives in match(), not
    // here — but the far complement is still beyond the gate.
    expect(
      ranked.map((m) => m.passcode),
      containsAll(<String>['not_in_db', darkMagician]),
    );
    expect(ranked.any((m) => m.passcode == 'far'), isFalse);
    expect(ranked.first.distance, 0);
  });

  test('returns empty when there is no frame yet', () async {
    final matcher = PHashArtMatcher(
      camera: _FakeCamera(null),
      index: HashIndex(
        version: 1,
        algorithm: 'phash',
        hashSize: 8,
        hashes: {darkMagician: PerceptualHash.parseHex('0000000000000000')},
      ),
      repository: repository,
      detector: const _IdentityCardDetector(),
    );
    expect(await matcher.match(), isEmpty);
  });

  test('returns empty when nothing ranks within the threshold', () async {
    final frame = syntheticFrame();
    final hash = expectedHash(frame, ArtMatchTuning.artBoxRoi);
    // Every entry is the bitwise complement of the frame's hash (distance 64).
    final index = HashIndex(
      version: 1,
      algorithm: 'phash',
      hashSize: 8,
      hashes: {
        darkMagician:
            PerceptualHash(~hash.hi & 0xffffffff, ~hash.lo & 0xffffffff),
      },
    );
    final matcher = PHashArtMatcher(
      camera: _FakeCamera(frame),
      index: index,
      repository: repository,
      detector: const _IdentityCardDetector(),
    );
    expect(await matcher.match(), isEmpty);
  });

  test('rankFrame reports noFrame when the camera has no frame', () {
    final matcher = PHashArtMatcher(
      camera: _FakeCamera(null),
      index: HashIndex(
        version: 1,
        algorithm: 'phash',
        hashSize: 8,
        hashes: {darkMagician: PerceptualHash.parseHex('0000000000000000')},
      ),
      repository: repository,
      detector: const _IdentityCardDetector(),
    );
    final result = matcher.rankFrame(includeNearest: true);
    expect(result.status, ArtFrameStatus.noFrame);
    expect(result.matches, isEmpty);
    expect(result.nearest, isEmpty);
  });

  test('rankFrame(includeNearest) surfaces the nearest hit past the gate', () {
    final frame = syntheticFrame();
    final hash = expectedHash(frame, ArtMatchTuning.artBoxRoi);
    // The only entry is the frame's complement (distance 64): beyond the match
    // gate, so it is not a match — but the overlay still needs to see it.
    final far = PerceptualHash(~hash.hi & 0xffffffff, ~hash.lo & 0xffffffff);
    final matcher = PHashArtMatcher(
      camera: _FakeCamera(frame),
      index: HashIndex(
        version: 1,
        algorithm: 'phash',
        hashSize: 8,
        hashes: {'far': far},
      ),
      repository: repository,
      detector: const _IdentityCardDetector(),
    );
    final result = matcher.rankFrame(includeNearest: true);
    expect(result.status, ArtFrameStatus.detected);
    expect(result.matches, isEmpty); // nothing within the gate
    expect(result.nearest.map((m) => m.passcode), ['far']);
  });
}
