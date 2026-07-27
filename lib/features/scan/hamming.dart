import 'dart:typed_data';

/// A 256-bit perceptual hash, stored as eight 32-bit lanes.
///
/// The index asset stores each hash as 64 lowercase hex chars. Dart's `int` is
/// 64-bit on the VM but only 53-bit-safe on the web, and
/// `int.parse('ffffffffffffffff', radix: 16)` is a sign/overflow trap. Splitting
/// into 32-bit lanes keeps every parsed chunk under 2^32 — comfortably inside
/// double-exact range — so parsing and Hamming distance stay correct and
/// web-safe. Each lane holds a non-negative value in `0..0xffffffff`.
///
/// A [Uint32List] rather than named fields, for two reasons beyond the obvious
/// one: stores into it truncate to 32 bits automatically, so `~x` needs no
/// `& 0xffffffff` mask and a whole class of masking bug disappears; and the
/// width is a constant, so moving again (to 512 bits, say) is a one-line change.
class PerceptualHash {
  PerceptualHash(this.lanes) : assert(lanes.length == laneCount);

  /// Parses a [hexChars]-length hex string (as produced by Python `imagehash`)
  /// into lanes; lane 0 is the most-significant 32 bits.
  factory PerceptualHash.parseHex(String hex) {
    if (hex.length != hexChars) {
      throw FormatException(
        'expected $hexChars hex chars, got ${hex.length}',
        hex,
      );
    }
    final lanes = Uint32List(laneCount);
    for (var i = 0; i < laneCount; i++) {
      lanes[i] = int.parse(hex.substring(i * 8, i * 8 + 8), radix: 16);
    }
    return PerceptualHash(lanes);
  }

  /// Width of the descriptor. Must equal `kPhashHashSize^2` in `phash.dart`;
  /// `phash_test.dart` asserts they agree, since nothing else can (the
  /// dependency runs one way, `phash.dart` -> here).
  static const int bitCount = 256;
  static const int laneCount = bitCount ~/ 32;
  static const int hexChars = bitCount ~/ 4;

  /// Lane 0 holds bits 255..224, lane 7 holds bits 31..0.
  final Uint32List lanes;

  /// The hex form, matching the index asset (`imagehash` output).
  String toHex() {
    final buffer = StringBuffer();
    for (var i = 0; i < laneCount; i++) {
      buffer.write(lanes[i].toRadixString(16).padLeft(8, '0'));
    }
    return buffer.toString();
  }

  /// The number of differing bits between this hash and [other] (0..[bitCount]).
  int distanceTo(PerceptualHash other) {
    var distance = 0;
    for (var i = 0; i < laneCount; i++) {
      distance += _popcount32(lanes[i] ^ other.lanes[i]);
    }
    return distance;
  }

  /// The bitwise complement — the maximally distant hash. For tests, which need
  /// an entry that is definitely past every gate and were open-coding the mask.
  PerceptualHash complement() {
    final out = Uint32List(laneCount);
    for (var i = 0; i < laneCount; i++) {
      out[i] = ~lanes[i]; // Uint32List truncates the sign extension away.
    }
    return PerceptualHash(out);
  }

  @override
  bool operator ==(Object other) {
    if (other is! PerceptualHash) return false;
    for (var i = 0; i < laneCount; i++) {
      if (lanes[i] != other.lanes[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(lanes);

  @override
  String toString() => 'PerceptualHash(${toHex()})';
}

/// Population count of the low 32 bits of [x] via the standard SWAR trick.
/// [x] is treated as an unsigned 32-bit value.
///
/// Stays 32-bit deliberately: a 64-bit SWAR would halve the loop on the VM but
/// needs 64-bit magic constants, which is exactly the web-unsafety this file's
/// lane split exists to avoid.
int _popcount32(int x) {
  x &= 0xffffffff;
  x = x - ((x >> 1) & 0x55555555);
  x = (x & 0x33333333) + ((x >> 2) & 0x33333333);
  x = (x + (x >> 4)) & 0x0f0f0f0f;
  return ((x * 0x01010101) & 0xffffffff) >> 24;
}
