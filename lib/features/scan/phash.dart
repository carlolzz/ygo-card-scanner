import 'dart:math' as math;
import 'dart:typed_data';

import 'hamming.dart';

/// Perceptual-hash computation that reproduces Python
/// `imagehash.phash(img, hash_size=16, highfreq_factor=4)` — the algorithm
/// `tools/build_hash_index.py` used to build `assets/card_hashes.json`.
///
/// imagehash does, in order:
///   1. grayscale (`convert('L')`) and resize to 64x64 (`hash_size*4`) LANCZOS,
///   2. 2D DCT-II: `dct(dct(pixels, axis=0), axis=1)`,
///   3. keep the top-left 16x16 low-frequency block (DC included),
///   4. threshold each cell strictly against the block's median,
///   5. pack the 256 booleans row-major, first element = most-significant bit,
///      into a 64-hex-char string.
///
/// Steps 2–5 are exact, deterministic arithmetic and are reproduced here bit for
/// bit (see `phash_test.dart` Tier 1, which asserts distance 0 against the index
/// on identical pixels). Step 1's LANCZOS resize is *not* reproducible in pure
/// Dart; [phashFromLuma] uses an area-average resize, whose small residual gap
/// is measured by `phash_e2e_test.dart` (Tier 2) and absorbed by the top-N +
/// threshold ranking in `ArtMatcher`.
///
/// **Why 16 and not 8.** At 64 bits the descriptor could not separate 14.6k
/// cards: measured over the shipped index, *every* card had another within
/// Hamming 18 (28% of the width, the runtime's own gate), and 41 hash values
/// were shared outright by 82 cards. At 256 bits over the same ROI the same
/// fraction of the width leaves only ~1.4% of cards with any neighbour at all.
/// The cost is 8x the DCT multiply-adds (10k -> 82k, single-digit milliseconds
/// against a 300ms frame cadence) and a ~1.2MB asset.
const int kPhashHashSize = 16;
const int kPhashImgSize = kPhashHashSize * 4; // 64
const int kPhashBitCount = kPhashHashSize * kPhashHashSize; // 256

/// `_cos[k][n] = cos(pi * k * (2n+1) / (2*imgSize))` for a DCT-II of length
/// `imgSize`, restricted to the `k in 0..hashSize-1` outputs we keep.
final List<Float64List> _cos = _buildCosTable();

List<Float64List> _buildCosTable() {
  final table = List.generate(kPhashHashSize, (_) => Float64List(kPhashImgSize));
  for (var k = 0; k < kPhashHashSize; k++) {
    for (var n = 0; n < kPhashImgSize; n++) {
      table[k][n] = math.cos(math.pi * k * (2 * n + 1) / (2 * kPhashImgSize));
    }
  }
  return table;
}

/// Computes the pHash of an already-resized `kPhashImgSize` square grayscale block.
///
/// [pixels] is row-major, length `imgSize*imgSize` (4096), values 0..255. This
/// is the exact-arithmetic entry point: given the same pixels PIL produced, the
/// result equals the `imagehash` hash bit for bit.
PerceptualHash phashFromBlock(Uint8List pixels) {
  assert(pixels.length == kPhashImgSize * kPhashImgSize);

  // Separable 2D DCT-II, mirroring scipy's `dct(dct(P, axis=0), axis=1)` but
  // computing only the `k,j in 0..hashSize-1` outputs the low-frequency slice
  // needs. The constant scipy scale factor (2 per axis) is uniform and
  // irrelevant to a median comparison, so it is omitted.
  //
  // axis=0 (over rows r), keeping frequencies k in 0..hashSize-1:
  //   t[k][c] = sum_r P[r][c] * cos[k][r]
  final t = List.generate(kPhashHashSize, (_) => Float64List(kPhashImgSize));
  for (var k = 0; k < kPhashHashSize; k++) {
    final cosK = _cos[k];
    final tk = t[k];
    for (var c = 0; c < kPhashImgSize; c++) {
      var sum = 0.0;
      for (var r = 0; r < kPhashImgSize; r++) {
        sum += pixels[r * kPhashImgSize + c] * cosK[r];
      }
      tk[c] = sum;
    }
  }

  // axis=1 (over cols c), keeping frequencies j in 0..hashSize-1:
  //   b[k][j] = sum_c t[k][c] * cos[j][c]
  final b = Float64List(kPhashBitCount);
  for (var k = 0; k < kPhashHashSize; k++) {
    final tk = t[k];
    for (var j = 0; j < kPhashHashSize; j++) {
      final cosJ = _cos[j];
      var sum = 0.0;
      for (var c = 0; c < kPhashImgSize; c++) {
        sum += tk[c] * cosJ[c];
      }
      b[k * kPhashHashSize + j] = sum;
    }
  }

  final med = _medianBlock(b);

  // Pack row-major, first cell = the MSB of lane 0 — the same convention as
  // imagehash's `_binary_array_to_hex` over a row-major flatten.
  //
  // Built by shifting *in* (`v * 2 + bit`) rather than or-ing `1 << (31 - i)`:
  // under dart2js a `1 << 31` and the `|` that follows go through JS's signed
  // 32-bit bitwise ops, while this form never leaves double-exact range.
  final lanes = Uint32List(PerceptualHash.laneCount);
  for (var lane = 0; lane < PerceptualHash.laneCount; lane++) {
    final base = lane * 32;
    var value = 0;
    for (var bit = 0; bit < 32; bit++) {
      value = value * 2 + (b[base + bit] > med ? 1 : 0);
    }
    lanes[lane] = value;
  }
  return PerceptualHash(lanes);
}

/// Median of the DCT block, matching `numpy.median` (mean of the two middle
/// elements of the sorted values, the block being even-length).
double _medianBlock(Float64List values) {
  assert(values.length == kPhashBitCount);
  final sorted = Float64List.fromList(values)..sort();
  final mid = kPhashBitCount ~/ 2;
  return (sorted[mid - 1] + sorted[mid]) / 2.0;
}

/// Computes the pHash of a grayscale luma buffer, cropping an optional region
/// and area-averaging it down to a `kPhashImgSize` square first.
///
/// [luma] is row-major, length `width*height`, one byte per pixel (0..255) —
/// e.g. an Android nv21 Y plane or an iOS BGRA frame converted to luma. [crop]
/// selects a sub-rectangle in pixel coordinates (defaults to the whole frame);
/// callers pass the card's art box here so the hashed region matches the cropped
/// art the index was built from.
PerceptualHash phashFromLuma(
  Uint8List luma,
  int width,
  int height, {
  PixelRect? crop,
}) {
  final region = crop ?? PixelRect(0, 0, width, height);
  final resized = _areaResizeToBlock(luma, width, height, region);
  return phashFromBlock(resized);
}

/// A rectangle in source-pixel coordinates.
class PixelRect {
  const PixelRect(this.left, this.top, this.width, this.height);
  final int left;
  final int top;
  final int width;
  final int height;
}

/// Area-average downscale of [region] within [luma] to a `kPhashImgSize` square. Each
/// destination cell is the coverage-weighted mean of the source pixels it
/// overlaps — the standard "box" antialiased downscale, a close-enough stand-in
/// for PIL's LANCZOS for perceptual hashing (the residual is measured by Tier 2).
Uint8List _areaResizeToBlock(
  Uint8List luma,
  int width,
  int height,
  PixelRect region,
) {
  final out = Uint8List(kPhashImgSize * kPhashImgSize);
  final left = region.left.clamp(0, width).toDouble();
  final top = region.top.clamp(0, height).toDouble();
  final right = (region.left + region.width).clamp(0, width).toDouble();
  final bottom = (region.top + region.height).clamp(0, height).toDouble();
  final spanX = (right - left) <= 0 ? 1.0 : right - left;
  final spanY = (bottom - top) <= 0 ? 1.0 : bottom - top;

  for (var ty = 0; ty < kPhashImgSize; ty++) {
    final fy0 = top + ty * spanY / kPhashImgSize;
    final fy1 = top + (ty + 1) * spanY / kPhashImgSize;
    final sy0 = fy0.floor();
    final sy1 = fy1.ceil();
    for (var tx = 0; tx < kPhashImgSize; tx++) {
      final fx0 = left + tx * spanX / kPhashImgSize;
      final fx1 = left + (tx + 1) * spanX / kPhashImgSize;
      final sx0 = fx0.floor();
      final sx1 = fx1.ceil();

      var sum = 0.0;
      var area = 0.0;
      for (var sy = sy0; sy < sy1; sy++) {
        if (sy < 0 || sy >= height) continue;
        final wy = math.min(sy + 1.0, fy1) - math.max(sy.toDouble(), fy0);
        if (wy <= 0) continue;
        final rowBase = sy * width;
        for (var sx = sx0; sx < sx1; sx++) {
          if (sx < 0 || sx >= width) continue;
          final wx = math.min(sx + 1.0, fx1) - math.max(sx.toDouble(), fx0);
          if (wx <= 0) continue;
          final w = wy * wx;
          sum += luma[rowBase + sx] * w;
          area += w;
        }
      }
      out[ty * kPhashImgSize + tx] =
          area <= 0 ? 0 : (sum / area).round().clamp(0, 255);
    }
  }
  return out;
}
