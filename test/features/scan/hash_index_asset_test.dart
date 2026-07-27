import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/core/theme/tokens.dart';
import 'package:ygo_scanner/features/scan/hamming.dart';
import 'package:ygo_scanner/features/scan/hash_index.dart';

/// Guards the *committed* `assets/card_hashes.json` against the build that ships
/// with it.
///
/// This test exists because the failure mode here is a **silent green**. Every
/// other consumer overrides `hashIndexProvider` with a small in-memory index, so
/// nothing else in the suite ever opens the real asset — changing
/// [ArtMatchTuning.artBoxRoi] or the descriptor width without re-running
/// `tools/build_hash_index.py` would leave `flutter test` entirely green and
/// break only the running app. And there it surfaces badly: the
/// [FormatException] arrives down the artwork stream, so it used to render as
/// *"the camera could not be started"*, cached for the process lifetime by
/// `hashIndexProvider`'s `keepAlive`.
///
/// Read with `dart:io` rather than `rootBundle` deliberately — the point is to
/// check the file in the repository, not a bundled copy.
void main() {
  late Map<String, dynamic> json;

  setUpAll(() {
    json =
        jsonDecode(File('assets/card_hashes.json').readAsStringSync())
            as Map<String, dynamic>;
  });

  group('committed hash index', () {
    test('header matches this build\'s descriptor', () {
      expect(json['algorithm'], 'phash');
      expect(json['hash_size'], HashIndex.kExpectedHashSize);
    });

    test('was built for the ROI this build crops', () {
      final roi = (json['roi'] as List).cast<num>();
      const expected = ArtMatchTuning.artBoxRoi;
      const tolerance = 0.0005;
      expect(roi[0], closeTo(expected.left, tolerance));
      expect(roi[1], closeTo(expected.top, tolerance));
      expect(roi[2], closeTo(expected.right, tolerance));
      expect(roi[3], closeTo(expected.bottom, tolerance));
    });

    test('parses end to end and is the full card database', () {
      final index = HashIndex.fromJson(json);
      expect(index.length, greaterThan(14000));
      expect(index.length, json['count']);
    });

    test('every hash has exactly half its bits set', () {
      // Not a curiosity: `imagehash` thresholds each DCT coefficient against the
      // block's *median*, so exactly half the bits are set — and two equal-weight
      // vectors always differ in an even number of positions. That is why
      // `ArtMatchTuning`'s thresholds are written as even numbers, and a hash
      // that violated it would mean the builder and the runtime had diverged.
      final index = HashIndex.fromJson(json);
      for (final hash in index.hashes.values) {
        expect(
          hash.distanceTo(hash.complement()),
          PerceptualHash.bitCount,
          reason: 'complement distance must be the full width',
        );
      }
      final half = PerceptualHash.bitCount ~/ 2;
      final zero = PerceptualHash(PerceptualHash.parseHex('0' * 64).lanes);
      for (final hash in index.hashes.values) {
        expect(hash.distanceTo(zero), half);
      }
    });
  });
}
