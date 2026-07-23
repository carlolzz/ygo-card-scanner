/// A 64-bit perceptual hash, stored as two 32-bit lanes.
///
/// The index asset stores each hash as 16 lowercase hex chars (a 64-bit value).
/// Dart's `int` is 64-bit on the VM but only 53-bit-safe on the web, and
/// `int.parse('ffffffffffffffff', radix: 16)` is a sign/overflow trap. Splitting
/// into a high and low 32-bit lane keeps parsing and Hamming distance correct and
/// web-safe. Each lane holds a non-negative value in `0..0xffffffff`.
class PerceptualHash {
  const PerceptualHash(this.hi, this.lo);

  /// Parses a 16-hex-char string (as produced by Python `imagehash`) into two
  /// 32-bit lanes: `hi` is the most-significant half.
  factory PerceptualHash.parseHex(String hex) {
    if (hex.length != 16) {
      throw FormatException('expected 16 hex chars, got ${hex.length}', hex);
    }
    return PerceptualHash(
      int.parse(hex.substring(0, 8), radix: 16),
      int.parse(hex.substring(8, 16), radix: 16),
    );
  }

  /// The most-significant 32 bits (bits 63..32).
  final int hi;

  /// The least-significant 32 bits (bits 31..0).
  final int lo;

  /// The 16-hex-char form, matching the index asset (`imagehash` output).
  String toHex() =>
      hi.toRadixString(16).padLeft(8, '0') + lo.toRadixString(16).padLeft(8, '0');

  /// The number of differing bits between this hash and [other] (0..64).
  int distanceTo(PerceptualHash other) =>
      _popcount32(hi ^ other.hi) + _popcount32(lo ^ other.lo);

  @override
  bool operator ==(Object other) =>
      other is PerceptualHash && other.hi == hi && other.lo == lo;

  @override
  int get hashCode => Object.hash(hi, lo);

  @override
  String toString() => 'PerceptualHash(${toHex()})';
}

/// Population count of the low 32 bits of [x] via the standard SWAR trick.
/// [x] is treated as an unsigned 32-bit value.
int _popcount32(int x) {
  x &= 0xffffffff;
  x = x - ((x >> 1) & 0x55555555);
  x = (x & 0x33333333) + ((x >> 2) & 0x33333333);
  x = (x + (x >> 4)) & 0x0f0f0f0f;
  return ((x * 0x01010101) & 0xffffffff) >> 24;
}
