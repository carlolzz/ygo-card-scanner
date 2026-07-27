import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/core/theme/tokens.dart';
import 'package:ygo_scanner/features/scan/hamming.dart';
import 'package:ygo_scanner/features/scan/hash_index.dart';

Map<String, dynamic> validJson(Map<String, String> hashes) => {
  'version': 3,
  'algorithm': 'phash',
  'hash_size': HashIndex.kExpectedHashSize,
  'hashes': hashes,
};

/// A full-width hex hash whose trailing chars are [tail] and the rest zeros.
String hex(String tail) => tail.padLeft(PerceptualHash.hexChars, '0');

final zeros = hex('');
final ones = 'f' * PerceptualHash.hexChars;

void main() {
  group('HashIndex.fromJson', () {
    test('parses a valid wrapper', () {
      final sample = hex('9588fad6c876a28b');
      final index = HashIndex.fromJson(
        validJson({'46986414': sample, '89631139': zeros}),
      );
      expect(index.length, 2);
      expect(index.hashes['46986414']!.toHex(), sample);
    });

    test('rejects a non-phash algorithm', () {
      final json = validJson({'1': zeros})..['algorithm'] = 'ahash';
      expect(() => HashIndex.fromJson(json), throwsFormatException);
    });

    test('rejects a mismatched hash size', () {
      // 8 is the previous descriptor width — the case that actually matters, an
      // index built before the 256-bit migration.
      final json = validJson({'1': zeros})..['hash_size'] = 8;
      expect(() => HashIndex.fromJson(json), throwsFormatException);
    });

    test('rejects hashes of the wrong width', () {
      // A header can say 16 while the values are the old 64-bit form; parseHex
      // is what catches that.
      final json = validJson({'1': '9588fad6c876a28b'});
      expect(() => HashIndex.fromJson(json), throwsFormatException);
    });

    test('rejects a missing hashes map', () {
      expect(
        () => HashIndex.fromJson({
          'version': 3,
          'algorithm': 'phash',
          'hash_size': HashIndex.kExpectedHashSize,
        }),
        throwsFormatException,
      );
    });

    test('accepts an index whose recorded ROI is the one we crop', () {
      const roi = ArtMatchTuning.artBoxRoi;
      final json = validJson({'1': zeros})
        ..['roi'] = [roi.left, roi.top, roi.right, roi.bottom];
      expect(HashIndex.fromJson(json).length, 1);
    });

    test('rejects an index built for a different art-box ROI', () {
      // Silent drift otherwise: every distance would degrade with no error.
      final json = validJson({'1': zeros})..['roi'] = [0.05, 0.15, 0.95, 0.72];
      expect(() => HashIndex.fromJson(json), throwsFormatException);
    });

    test('an index without a roi header still parses', () {
      expect(HashIndex.fromJson(validJson({'1': zeros})).length, 1);
    });
  });

  group('rank', () {
    // Distances from the all-zero query: a=0, b=1, c=2, far=bitCount.
    final index = HashIndex.fromJson(
      validJson({
        'a': zeros,
        'b': hex('1'),
        'c': hex('3'),
        'far': ones,
      }),
    );
    final query = PerceptualHash.parseHex(zeros);

    test('returns the closest first, capped at n', () {
      final hits = index.rank(query, n: 2);
      expect(hits.map((h) => h.passcode), ['a', 'b']);
      expect(hits.first.distance, 0);
    });

    test('excludes anything beyond maxDistance', () {
      final hits = index.rank(query, n: 10, maxDistance: 2);
      expect(hits.map((h) => h.passcode), ['a', 'b', 'c']);
      expect(hits.every((h) => h.distance <= 2), isTrue);
    });

    test('ties break by passcode for a stable order', () {
      final tied = HashIndex.fromJson(
        validJson({'z': hex('1'), 'a': hex('2')}),
      );
      // Both are distance 1 from the query; 'a' sorts before 'z'.
      expect(tied.rank(query, n: 5).map((h) => h.passcode), ['a', 'z']);
    });

    test('returns empty when nothing is close enough', () {
      expect(index.rank(query, n: 5, maxDistance: 1).length, 2);
      // 8 bits set, none of them shared with a/b/c: distance 8, 9 and 10 to
      // those and 248 to 'far', so a radius of 3 reaches nothing.
      final hits = index.rank(
        PerceptualHash.parseHex(hex('ff0000')),
        n: 5,
        maxDistance: 3,
      );
      expect(hits, isEmpty);
    });

    test('n larger than the index returns everything, still ordered', () {
      final hits = index.rank(query, n: 100);
      expect(hits.map((h) => h.passcode), ['a', 'b', 'c', 'far']);
    });

    test('n of zero returns nothing', () {
      expect(index.rank(query, n: 0), isEmpty);
    });

    test('the partial selection agrees with a full sort at every n', () {
      // The bounded selection replaced a collect-then-sort, and its whole value
      // is being *indistinguishable* from it — so compare against one directly.
      final entries = index.hashes.entries.toList()
        ..sort((a, b) {
          final byDistance = query
              .distanceTo(a.value)
              .compareTo(query.distanceTo(b.value));
          return byDistance != 0 ? byDistance : a.key.compareTo(b.key);
        });
      for (var n = 1; n <= index.length + 1; n++) {
        expect(
          index.rank(query, n: n).map((h) => h.passcode),
          entries.take(n).map((e) => e.key),
          reason: 'n=$n',
        );
      }
    });
  });
}
