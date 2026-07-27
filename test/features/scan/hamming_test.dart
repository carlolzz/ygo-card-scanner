import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/features/scan/hamming.dart';

/// A [PerceptualHash.hexChars]-length hex string whose *last* 16 chars are
/// [tail] and the rest zeros — so a test can exercise one lane's arithmetic
/// without spelling out all 64 characters.
String _hex(String tail) => tail.padLeft(PerceptualHash.hexChars, '0');

void main() {
  group('PerceptualHash.parseHex', () {
    test('splits the hex string into 32-bit lanes, most significant first', () {
      final h = PerceptualHash.parseHex(_hex('0123456789abcdef'));
      expect(h.lanes.length, PerceptualHash.laneCount);
      expect(h.lanes.first, 0);
      expect(h.lanes[PerceptualHash.laneCount - 2], 0x01234567);
      expect(h.lanes.last, 0x89abcdef);
    });

    test('round-trips through toHex, zero-padding each lane', () {
      final hex = _hex('00000001ffffffff');
      expect(PerceptualHash.parseHex(hex).toHex(), hex);
    });

    test('handles the all-ones value without sign/overflow trouble', () {
      final hex = 'f' * PerceptualHash.hexChars;
      final h = PerceptualHash.parseHex(hex);
      expect(h.lanes.every((lane) => lane == 0xffffffff), isTrue);
      expect(h.toHex(), hex);
    });

    test('rejects a wrong-length string', () {
      expect(() => PerceptualHash.parseHex('abc'), throwsFormatException);
      // A stale 64-bit index entry is exactly this case, and the message names
      // the expected width so the cause is obvious.
      expect(
        () => PerceptualHash.parseHex('9588fad6c876a28b'),
        throwsFormatException,
      );
    });
  });

  group('distanceTo', () {
    test('is zero for equal hashes', () {
      final h = PerceptualHash.parseHex(_hex('9588fad6c876a28b'));
      expect(h.distanceTo(h), 0);
    });

    test('is the full width for all-zeros vs all-ones', () {
      final zero = PerceptualHash.parseHex('0' * PerceptualHash.hexChars);
      final ones = PerceptualHash.parseHex('f' * PerceptualHash.hexChars);
      expect(zero.distanceTo(ones), PerceptualHash.bitCount);
      expect(ones.distanceTo(zero), PerceptualHash.bitCount);
    });

    test('counts differing bits across every lane', () {
      final a = PerceptualHash.parseHex('0' * PerceptualHash.hexChars);
      // One bit set in each of the eight lanes.
      final b = PerceptualHash.parseHex('00000001' * PerceptualHash.laneCount);
      expect(a.distanceTo(b), PerceptualHash.laneCount);
    });

    test('is symmetric', () {
      final a = PerceptualHash.parseHex(_hex('123456789abcdef0'));
      final b = PerceptualHash.parseHex(_hex('0fedcba987654321'));
      expect(a.distanceTo(b), b.distanceTo(a));
    });
  });

  test('complement is the maximally distant hash', () {
    final h = PerceptualHash.parseHex(_hex('123456789abcdef0'));
    expect(h.distanceTo(h.complement()), PerceptualHash.bitCount);
    expect(h.complement().complement(), h);
  });

  test('equality is by value', () {
    expect(
      PerceptualHash.parseHex(_hex('00ff00ff00ff00ff')),
      PerceptualHash.parseHex(_hex('00ff00ff00ff00ff')),
    );
    expect(
      PerceptualHash.parseHex(_hex('1')) ==
          PerceptualHash.parseHex(_hex('2')),
      isFalse,
    );
  });
}
