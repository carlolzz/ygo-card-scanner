import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/features/scan/hamming.dart';
import 'package:ygo_scanner/features/scan/phash.dart';

/// Tier 1 of the reproducibility spike (see the plan / `dump_phash_fixtures.py`):
/// prove the Dart DCT -> median -> bit-pack path matches Python `imagehash`
/// *exactly* when fed the identical 32x32 grayscale pixels PIL produced. This
/// isolates the deterministic arithmetic from the (non-reproducible) resize.
void main() {
  group('phashFrom32x32 exactness (Tier 1)', () {
    final fixture = jsonDecode(
      File('test/features/scan/fixtures/phash_tier1.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final samples = (fixture['samples'] as List).cast<Map<String, dynamic>>();

    test('fixture is present and non-trivial', () {
      expect(samples, hasLength(greaterThanOrEqualTo(8)));
    });

    for (final sample in samples) {
      final passcode = sample['passcode'] as String;
      test('matches imagehash exactly for $passcode', () {
        final pixels = base64.decode(sample['pixels'] as String);
        expect(pixels, hasLength(kPhashImgSize * kPhashImgSize));

        final expected =
            PerceptualHash.parseHex(sample['expectedHash'] as String);
        final actual = phashFrom32x32(Uint8List.fromList(pixels));

        expect(
          actual.distanceTo(expected),
          0,
          reason: 'expected ${expected.toHex()} got ${actual.toHex()}',
        );
      });
    }
  });

  group('phashFrom32x32 basic properties', () {
    test('a flat image yields a stable hash and self-distance 0', () {
      final flat = Uint8List(kPhashImgSize * kPhashImgSize)
        ..fillRange(0, kPhashImgSize * kPhashImgSize, 128);
      final h = phashFrom32x32(flat);
      expect(h.distanceTo(h), 0);
    });

    test('round-trips through hex', () {
      final ramp = Uint8List.fromList(
        List.generate(kPhashImgSize * kPhashImgSize, (i) => i % 256),
      );
      final h = phashFrom32x32(ramp);
      expect(PerceptualHash.parseHex(h.toHex()), h);
    });
  });
}
