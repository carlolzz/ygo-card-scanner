import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/core/theme/tokens.dart';
import 'package:ygo_scanner/features/scan/hamming.dart';
import 'package:ygo_scanner/features/scan/hash_index.dart';

Map<String, dynamic> validJson(Map<String, String> hashes) => {
      'version': 1,
      'algorithm': 'phash',
      'hash_size': 8,
      'hashes': hashes,
    };

void main() {
  group('HashIndex.fromJson', () {
    test('parses a valid wrapper', () {
      final index = HashIndex.fromJson(validJson({
        '46986414': '9588fad6c876a28b',
        '89631139': '0000000000000000',
      }));
      expect(index.length, 2);
      expect(index.hashes['46986414']!.toHex(), '9588fad6c876a28b');
    });

    test('rejects a non-phash algorithm', () {
      final json = validJson({'1': '0000000000000000'})..['algorithm'] = 'ahash';
      expect(() => HashIndex.fromJson(json), throwsFormatException);
    });

    test('rejects a mismatched hash size', () {
      final json = validJson({'1': '0000000000000000'})..['hash_size'] = 16;
      expect(() => HashIndex.fromJson(json), throwsFormatException);
    });

    test('rejects a missing hashes map', () {
      expect(
        () => HashIndex.fromJson({
          'version': 1,
          'algorithm': 'phash',
          'hash_size': 8,
        }),
        throwsFormatException,
      );
    });

    test('accepts an index whose recorded ROI is the one we crop', () {
      final roi = ArtMatchTuning.artBoxRoi;
      final json = validJson({'1': '0000000000000000'})
        ..['roi'] = [roi.left, roi.top, roi.right, roi.bottom];
      expect(HashIndex.fromJson(json).length, 1);
    });

    test('rejects an index built for a different art-box ROI', () {
      // Silent drift otherwise: every distance would degrade with no error.
      final json = validJson({'1': '0000000000000000'})
        ..['roi'] = [0.05, 0.15, 0.95, 0.72];
      expect(() => HashIndex.fromJson(json), throwsFormatException);
    });

    test('a v1 index without a roi header still parses', () {
      expect(
        HashIndex.fromJson(validJson({'1': '0000000000000000'})).length,
        1,
      );
    });
  });

  group('rank', () {
    // Distances from the query below: a=0, b=1, c=2, far=64.
    final index = HashIndex.fromJson(validJson({
      'a': '0000000000000000',
      'b': '0000000000000001',
      'c': '0000000000000003',
      'far': 'ffffffffffffffff',
    }));
    final query = PerceptualHash.parseHex('0000000000000000');

    test('returns the closest first, capped at n', () {
      final hits = index.rank(query, n: 2, maxDistance: 64);
      expect(hits.map((h) => h.passcode), ['a', 'b']);
      expect(hits.first.distance, 0);
    });

    test('excludes anything beyond maxDistance', () {
      final hits = index.rank(query, n: 10, maxDistance: 2);
      expect(hits.map((h) => h.passcode), ['a', 'b', 'c']);
      expect(hits.every((h) => h.distance <= 2), isTrue);
    });

    test('ties break by passcode for a stable order', () {
      final tied = HashIndex.fromJson(validJson({
        'z': '0000000000000001',
        'a': '0000000000000002',
      }));
      // Both are distance 1 from the query; 'a' sorts before 'z'.
      final hits = tied.rank(query, n: 5, maxDistance: 64);
      expect(hits.map((h) => h.passcode), ['a', 'z']);
    });

    test('returns empty when nothing is close enough', () {
      expect(index.rank(query, n: 5, maxDistance: 1).length, 2);
      final ones = PerceptualHash.parseHex('ffffffffffffff00');
      final hits = index.rank(ones, n: 5, maxDistance: 3);
      expect(hits, isEmpty);
    });
  });
}
