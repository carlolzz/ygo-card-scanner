import 'dart:math' as math;
import 'dart:typed_data';

import 'hamming.dart';

/// Perceptual-hash computation that reproduces Python
/// `imagehash.phash(img, hash_size=8, highfreq_factor=4)` — the algorithm
/// `tools/build_hash_index.py` used to build `assets/card_hashes.json`.
///
/// imagehash does, in order:
///   1. grayscale (`convert('L')`) and resize to 32x32 (`hash_size*4`) LANCZOS,
///   2. 2D DCT-II: `dct(dct(pixels, axis=0), axis=1)`,
///   3. keep the top-left 8x8 low-frequency block (DC included),
///   4. threshold each cell strictly against the block's median,
///   5. pack the 64 booleans row-major, first element = most-significant bit,
///      into a 16-hex-char string.
///
/// Steps 2–5 are exact, deterministic arithmetic and are reproduced here bit for
/// bit (see `phash_test.dart` Tier 1, which asserts distance 0 against the index
/// on the identical 32x32 pixels). Step 1's LANCZOS resize is *not* reproducible
/// in pure Dart; [phashFromLuma] uses an area-average resize, whose small
/// residual gap is measured by `phash_e2e_test.dart` (Tier 2) and absorbed by
/// the top-N + threshold ranking in `ArtMatcher`.
const int kPhashHashSize = 8;
const int kPhashImgSize = kPhashHashSize * 4; // 32

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

/// Computes the pHash of an already-resized 32x32 grayscale block.
///
/// [pixels] is row-major, length `imgSize*imgSize` (1024), values 0..255. This
/// is the exact-arithmetic entry point: given the same pixels PIL produced, the
/// result equals the `imagehash` hash bit for bit.
PerceptualHash phashFrom32x32(Uint8List pixels) {
  assert(pixels.length == kPhashImgSize * kPhashImgSize);

  // Separable 2D DCT-II, mirroring scipy's `dct(dct(P, axis=0), axis=1)` but
  // computing only the k,j in 0..7 outputs the 8x8 slice needs. The constant
  // scipy scale factor (2 per axis) is uniform and irrelevant to a median
  // comparison, so it is omitted.
  //
  // axis=0 (over rows r), keeping frequencies k in 0..7:
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

  // axis=1 (over cols c), keeping frequencies j in 0..7:
  //   b[k][j] = sum_c t[k][c] * cos[j][c]
  final b = Float64List(kPhashHashSize * kPhashHashSize);
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

  final med = _median64(b);

  // Pack row-major, first cell = MSB (bit 63). Bits 63..32 -> hi, 31..0 -> lo.
  var hi = 0;
  var lo = 0;
  for (var i = 0; i < 64; i++) {
    if (b[i] > med) {
      if (i < 32) {
        hi |= 1 << (31 - i);
      } else {
        lo |= 1 << (63 - i);
      }
    }
  }
  return PerceptualHash(hi, lo);
}

/// Median of 64 values, matching `numpy.median` (mean of the two middle
/// elements of the sorted values).
double _median64(Float64List values) {
  assert(values.length == 64);
  final sorted = Float64List.fromList(values)..sort();
  return (sorted[31] + sorted[32]) / 2.0;
}

/// Computes the pHash of a grayscale luma buffer, cropping an optional region
/// and area-averaging it down to 32x32 first.
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
  final resized = _areaResizeTo32(luma, width, height, region);
  return phashFrom32x32(resized);
}

/// A rectangle in source-pixel coordinates.
class PixelRect {
  const PixelRect(this.left, this.top, this.width, this.height);
  final int left;
  final int top;
  final int width;
  final int height;
}

/// Area-average downscale of [region] within [luma] to a 32x32 block. Each
/// destination cell is the coverage-weighted mean of the source pixels it
/// overlaps — the standard "box" antialiased downscale, a close-enough stand-in
/// for PIL's LANCZOS for perceptual hashing (the residual is measured by Tier 2).
Uint8List _areaResizeTo32(
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
