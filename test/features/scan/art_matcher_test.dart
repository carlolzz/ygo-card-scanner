import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Offset, Rect, Size;
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

// Two more seeded passcodes, chosen for their *lexical* order. `passcode` is the
// primary key, so SQLite satisfies a `passcode IN (...)` predicate from that
// index and returns rows in ascending passcode order — measured, not assumed:
// `getByPasscodes(['89631139', '44095762'])` comes back `[44095762, 89631139]`.
// Making the nearer card the lexically larger one is what gives the ordering
// test below something to catch.
const blueEyes = '89631139';
const mirrorForce = '44095762';

/// Minimal [CameraService] that only surfaces a fixed [ArtFrame] — no hardware.
class _FakeCamera implements CameraService {
  _FakeCamera(this._frame);
  final ArtFrame? _frame;
  final ValueNotifier<CameraController?> _preview =
      ValueNotifier<CameraController?>(null);

  @override
  ArtFrame? get latestArtFrame => _frame;

  @override
  int get frameSequence => _frame == null ? 0 : 1;

  @override
  CameraHealth get health => CameraHealth(
    initialized: _frame != null,
    streaming: _frame != null,
    framesSeen: _frame == null ? 0 : 1,
    sinceLastFrame: Duration.zero,
    restarts: 0,
  );

  @override
  Stream<InputImage> get frames => const Stream<InputImage>.empty();

  @override
  InputImage? get latestInputImage => null;

  @override
  set artCaptureEnabled(bool enabled) {}

  @override
  Future<void> setExposureCompensation(double ev) async {}

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
/// library, which doesn't load on the host. Reports the whole frame as the
/// detected quad and no art box, so the matcher takes its fixed-ROI path.
class _IdentityCardDetector implements CardDetector {
  const _IdentityCardDetector();
  @override
  Future<DetectedCard?> detectCard(ArtFrame frame, {Rect? searchRoi}) async =>
      DetectedCard(
        image: frame.oriented(),
        quad: const [
          Offset(0, 0),
          Offset(1, 0),
          Offset(1, 1),
          Offset(0, 1),
        ],
      );
}

/// Records the search ROIs it was asked about, and finds a card only for the
/// whole-frame one — so a test can prove the matcher retries over the full frame
/// after the reticle region comes up empty.
class _RoiSensitiveDetector implements CardDetector {
  final List<Rect?> searchRois = [];

  @override
  Future<DetectedCard?> detectCard(ArtFrame frame, {Rect? searchRoi}) async {
    searchRois.add(searchRoi);
    if (searchRoi != ArtMatchTuning.cardSearchRoi) return null;
    return DetectedCard(
      image: frame.oriented(),
      quad: const [
        Offset(0, 0),
        Offset(1, 0),
        Offset(1, 1),
        Offset(0, 1),
      ],
    );
  }
}

/// Never finds anything, whatever it is asked.
class _BlindCardDetector implements CardDetector {
  const _BlindCardDetector();
  @override
  Future<DetectedCard?> detectCard(ArtFrame frame, {Rect? searchRoi}) async =>
      null;
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

/// [hash] with [bits] of its lowest lane flipped: a near neighbour, comfortably
/// inside [ArtMatchTuning.maxHammingDistance] but not an exact hit.
PerceptualHash nudged(PerceptualHash hash, {int bits = 4}) {
  final lanes = Uint32List.fromList(hash.lanes);
  lanes[PerceptualHash.laneCount - 1] ^= (1 << bits) - 1;
  return PerceptualHash(lanes);
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
      hashSize: HashIndex.kExpectedHashSize,
      hashes: {
        darkMagician: hash, // distance 0 to the frame, and it is in the db
        'not_in_db': hash, // equally close but has no cards row -> skipped
        'far': hash.complement(),
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

  test('resolves candidates in ranked order, not database order', () async {
    final frame = syntheticFrame();
    final hash = expectedHash(frame, ArtMatchTuning.artBoxRoi);
    final index = HashIndex(
      version: 1,
      algorithm: 'phash',
      hashSize: HashIndex.kExpectedHashSize,
      hashes: {
        // The nearer card is the lexically *larger* passcode, so the batched
        // `WHERE passcode IN (...)` hands back Mirror Force first. If `match`
        // ever returned rows in the order the database produced them instead of
        // walking the ranked matches, this would come out reversed and the
        // review panel would present the second-best guess.
        blueEyes: hash, // distance 0
        mirrorForce: nudged(hash), // near, but farther
      },
    );

    final matcher = PHashArtMatcher(
      camera: _FakeCamera(frame),
      index: index,
      repository: repository,
      detector: const _IdentityCardDetector(),
    );
    final candidates = await matcher.match();

    expect(candidates.map((c) => c.card.passcode), [blueEyes, mirrorForce]);
    expect(candidates.first.distance, 0);
    expect(candidates.last.distance, greaterThan(0));
  });

  test('rankFrame ranks near hits (DB or not) with no repository read',
      () async {
    final frame = syntheticFrame();
    final hash = expectedHash(frame, ArtMatchTuning.artBoxRoi);
    final index = HashIndex(
      version: 1,
      algorithm: 'phash',
      hashSize: HashIndex.kExpectedHashSize,
      hashes: {
        darkMagician: hash, // in the db
        'not_in_db': hash, // equally close, but no cards row
        'far': hash.complement(),
      },
    );
    final matcher = PHashArtMatcher(
      camera: _FakeCamera(frame),
      index: index,
      repository: repository,
      detector: const _IdentityCardDetector(),
    );

    final result = await matcher.rankFrame();
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
        hashSize: HashIndex.kExpectedHashSize,
        hashes: {darkMagician: PerceptualHash.parseHex('0' * PerceptualHash.hexChars)},
      ),
      repository: repository,
      detector: const _IdentityCardDetector(),
    );
    expect(await matcher.match(), isEmpty);
  });

  test('returns empty when nothing ranks within the threshold', () async {
    final frame = syntheticFrame();
    final hash = expectedHash(frame, ArtMatchTuning.artBoxRoi);
    // Every entry is the bitwise complement of the frame's hash (the maximum
    // possible distance).
    final index = HashIndex(
      version: 1,
      algorithm: 'phash',
      hashSize: HashIndex.kExpectedHashSize,
      hashes: {
        darkMagician:
            hash.complement(),
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

  test('rankFrame reports noFrame when the camera has no frame', () async {
    final matcher = PHashArtMatcher(
      camera: _FakeCamera(null),
      index: HashIndex(
        version: 1,
        algorithm: 'phash',
        hashSize: HashIndex.kExpectedHashSize,
        hashes: {darkMagician: PerceptualHash.parseHex('0' * PerceptualHash.hexChars)},
      ),
      repository: repository,
      detector: const _IdentityCardDetector(),
    );
    final result = await matcher.rankFrame(includeNearest: true);
    expect(result.status, ArtFrameStatus.noFrame);
    expect(result.matches, isEmpty);
    expect(result.nearest, isEmpty);
  });

  test('rankFrame(includeNearest) surfaces the nearest hit past the gate',
      () async {
    final frame = syntheticFrame();
    final hash = expectedHash(frame, ArtMatchTuning.artBoxRoi);
    // The only entry is the frame's complement (maximum distance): beyond the match
    // gate, so it is not a match — but the overlay still needs to see it.
    final far = hash.complement();
    final matcher = PHashArtMatcher(
      camera: _FakeCamera(frame),
      index: HashIndex(
        version: 1,
        algorithm: 'phash',
        hashSize: HashIndex.kExpectedHashSize,
        hashes: {'far': far},
      ),
      repository: repository,
      detector: const _IdentityCardDetector(),
    );
    final result = await matcher.rankFrame(includeNearest: true);
    expect(result.status, ArtFrameStatus.detected);
    expect(result.matches, isEmpty); // nothing within the gate
    expect(result.nearest.map((m) => m.passcode), ['far']);
  });

  group('search region fallback', () {
    // The reticle-to-frame mapping is the one part of the pipeline that can be
    // wrong with no visible symptom, and if it were wrong on some device then
    // nothing would ever be detected there. Retrying over the whole frame turns
    // that cliff into a slower path.
    test('retries over the whole frame when the guide box finds nothing',
        () async {
      final frame = syntheticFrame();
      final detector = _RoiSensitiveDetector();
      final matcher = PHashArtMatcher(
        camera: _FakeCamera(frame),
        index: HashIndex(
          version: 1,
          algorithm: 'phash',
          hashSize: HashIndex.kExpectedHashSize,
          hashes: {
            darkMagician: expectedHash(frame, ArtMatchTuning.artBoxRoi),
          },
        ),
        repository: repository,
        detector: detector,
      );

      // A viewport is what makes the first pass a reticle-derived region rather
      // than the whole frame.
      final result = await matcher.rankFrame(
        viewportSize: const Size(1080, 2340),
      );

      expect(result.status, ArtFrameStatus.detected);
      expect(detector.searchRois, hasLength(2));
      expect(detector.searchRois.first, isNot(ArtMatchTuning.cardSearchRoi));
      expect(detector.searchRois.last, ArtMatchTuning.cardSearchRoi);
    });

    test('does not retry when the first pass already searched the whole frame',
        () async {
      final detector = _RoiSensitiveDetector();
      final matcher = PHashArtMatcher(
        camera: _FakeCamera(syntheticFrame()),
        index: HashIndex(
          version: 1,
          algorithm: 'phash',
          hashSize: HashIndex.kExpectedHashSize,
          hashes: {darkMagician: PerceptualHash.parseHex('0' * PerceptualHash.hexChars)},
        ),
        repository: repository,
        detector: detector,
      );

      // No viewport (every host test, and the scan screen before it lays out).
      await matcher.rankFrame();

      expect(detector.searchRois, [ArtMatchTuning.cardSearchRoi]);
    });

    test('reports notDetected when neither pass finds a card', () async {
      final matcher = PHashArtMatcher(
        camera: _FakeCamera(syntheticFrame()),
        index: HashIndex(
          version: 1,
          algorithm: 'phash',
          hashSize: HashIndex.kExpectedHashSize,
          hashes: {darkMagician: PerceptualHash.parseHex('0' * PerceptualHash.hexChars)},
        ),
        repository: repository,
        detector: const _BlindCardDetector(),
      );

      final result = await matcher.rankFrame(
        viewportSize: const Size(1080, 2340),
      );
      expect(result.status, ArtFrameStatus.notDetected);
      expect(result.matches, isEmpty);
      expect(await matcher.match(), isEmpty);
    });
  });
}
