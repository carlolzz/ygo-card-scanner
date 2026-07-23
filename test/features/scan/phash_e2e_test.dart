import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/features/scan/hamming.dart';
import 'package:ygo_scanner/features/scan/phash.dart';

/// Tier 2 of the reproducibility spike: run the *full* [phashFromLuma] (its own
/// area-average resize + DCT) over the same source art the index was built from,
/// and measure the Hamming gap our non-LANCZOS resize introduces. This is what
/// `ArtMatchTuning.maxHammingDistance` must comfortably exceed. It is *not* a
/// handheld-camera measurement (same clean source pixels) — the on-device gap
/// will be larger, which is exactly why matching presents ranked candidates
/// rather than auto-logging.
void main() {
  test('phashFromLuma stays close to imagehash on the source art (Tier 2)', () {
    final dir = Directory('test/features/scan/fixtures/phash_tier2');
    final manifest = jsonDecode(
      File('${dir.path}/manifest.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final samples = (manifest['samples'] as List).cast<Map<String, dynamic>>();
    expect(samples, isNotEmpty);

    final distances = <int>[];
    for (final sample in samples) {
      final passcode = sample['passcode'] as String;
      final width = sample['width'] as int;
      final height = sample['height'] as int;
      final expected =
          PerceptualHash.parseHex(sample['expectedHash'] as String);

      final luma = Uint8List.fromList(
        gzip.decode(File('${dir.path}/$passcode.luma.gz').readAsBytesSync()),
      );
      expect(luma, hasLength(width * height));

      final actual = phashFromLuma(luma, width, height);
      final d = actual.distanceTo(expected);
      distances.add(d);
      // Per-sample guard: even the worst source-art gap must stay well within
      // a threshold that still discriminates among 14k cards.
      expect(
        d,
        lessThanOrEqualTo(12),
        reason: '$passcode gap $d (${actual.toHex()} vs ${expected.toHex()})',
      );
    }

    final mean = distances.reduce((a, b) => a + b) / distances.length;
    // ignore: avoid_print
    print('Tier 2 Hamming gaps: $distances (mean ${mean.toStringAsFixed(1)})');
  });
}
