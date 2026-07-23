import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/features/scan/hamming.dart';

void main() {
  group('PerceptualHash.parseHex', () {
    test('splits a 16-hex string into hi/lo lanes', () {
      final h = PerceptualHash.parseHex('0123456789abcdef');
      expect(h.hi, 0x01234567);
      expect(h.lo, 0x89abcdef);
    });

    test('round-trips through toHex, zero-padding each lane', () {
      const hex = '00000001ffffffff';
      expect(PerceptualHash.parseHex(hex).toHex(), hex);
    });

    test('handles the all-ones value without sign/overflow trouble', () {
      final h = PerceptualHash.parseHex('ffffffffffffffff');
      expect(h.hi, 0xffffffff);
      expect(h.lo, 0xffffffff);
      expect(h.toHex(), 'ffffffffffffffff');
    });

    test('rejects a wrong-length string', () {
      expect(() => PerceptualHash.parseHex('abc'), throwsFormatException);
    });
  });

  group('distanceTo', () {
    test('is zero for equal hashes', () {
      final h = PerceptualHash.parseHex('9588fad6c876a28b');
      expect(h.distanceTo(h), 0);
    });

    test('is 64 for all-zeros vs all-ones', () {
      final zero = PerceptualHash.parseHex('0000000000000000');
      final ones = PerceptualHash.parseHex('ffffffffffffffff');
      expect(zero.distanceTo(ones), 64);
      expect(ones.distanceTo(zero), 64);
    });

    test('counts differing bits across both lanes', () {
      // hi differs by 1 bit (0x0 vs 0x1), lo differs by 3 bits (0x0 vs 0x7).
      final a = PerceptualHash.parseHex('0000000000000000');
      final b = PerceptualHash.parseHex('0000000100000007');
      expect(a.distanceTo(b), 4);
    });

    test('is symmetric', () {
      final a = PerceptualHash.parseHex('123456789abcdef0');
      final b = PerceptualHash.parseHex('0fedcba987654321');
      expect(a.distanceTo(b), b.distanceTo(a));
    });
  });

  test('equality is by value', () {
    expect(
      PerceptualHash.parseHex('00ff00ff00ff00ff'),
      PerceptualHash.parseHex('00ff00ff00ff00ff'),
    );
    expect(const PerceptualHash(1, 2) == const PerceptualHash(1, 3), isFalse);
  });
}
