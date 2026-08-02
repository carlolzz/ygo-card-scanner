import 'dart:typed_data';

import '../../core/theme/tokens.dart';
import 'phash.dart';

/// How usable one frame's artwork crop is, as two independent measurements of
/// the *exact pixels about to be hashed*.
///
/// The point is not to grade the photograph — it is to tell three failures apart
/// that the pipeline otherwise reports identically as "no match":
///
///  * **motion blur**, which flattens the high-frequency detail a DCT hash is
///    built from, so the descriptor drifts far from the indexed one;
///  * **specular glare**, which is the common case on Ultra/Secret rares — foil
///    clips whole regions of the artwork to white, destroying the structure
///    there outright;
///  * a genuinely unknown or mis-rectified card, where the frame is *fine* and
///    the distance is still large.
///
/// The third is the one worth knowing about, and today it is invisible: a
/// sharp, glare-free frame that still ranks at distance 60 means the crop is
/// wrong, not the optics. See `docs/next-session-brief.md` on the `art box:`
/// line, which is still unverified on device.
class FrameQuality {
  const FrameQuality({required this.sharpness, required this.glare});

  /// Variance of the 3x3 Laplacian over the crop — the standard cheap focus
  /// measure. Scene-dependent in absolute terms (a busy artwork scores higher
  /// than a plain one at equal focus), which is why the threshold is generous
  /// and why [FrameQualityTuning.maxConsecutiveSkips] exists.
  final double sharpness;

  /// Fraction (0..1) of sampled pixels at or above
  /// [FrameQualityTuning.glareLevel] — i.e. clipped highlights.
  final double glare;

  bool get isBlurry => sharpness < FrameQualityTuning.minSharpness;

  bool get isGlared => glare > FrameQualityTuning.maxGlareFraction;

  /// Whether this frame is worth hashing at all.
  bool get isUsable => !isBlurry && !isGlared;

  /// A frame with no measurement — used where a crop was never assessed, so
  /// callers can stay non-nullable without pretending a frame was good.
  static const FrameQuality unknown =
      FrameQuality(sharpness: double.infinity, glare: 0);
}

/// Measures [crop] within a row-major luma buffer.
///
/// Runs on the UI isolate, at the artwork cadence, so it samples every
/// [FrameQualityTuning.sampleStride]-th **row** and every column within it. A
/// frame this rejects skips the far more expensive `phashFromLuma` +
/// `HashIndex.rank` that would have followed, so rejection is *cheaper* than
/// today's behaviour, not dearer.
///
/// **Rows, not a strided grid, and that is not an optimisation detail.** Striding
/// both axes samples a fixed lattice, which aliases against any spatial frequency
/// that shares its period: on a 1px checkerboard every sampled pixel lands on the
/// same parity, so the Laplacian responses are all identical and the variance
/// reads **zero** — maximum detail scored as maximum blur. Real sensor noise
/// makes that exact degeneracy unlikely, but a focus measure that can be fooled
/// by a periodic pattern into rejecting the sharpest possible frame is not one to
/// keep. Striding rows leaves the inner loop contiguous (also the faster memory
/// order) and preserves variation along x.
///
/// Pure and here rather than inside `OpenCvCardDetector` on purpose, following
/// `card_quad.dart`: the detector imports OpenCV and so cannot be host-tested,
/// and a wrong threshold in this file does not crash — it silently stops
/// recognising cards.
FrameQuality assessCrop(
  Uint8List luma,
  int width,
  int height,
  PixelRect crop,
) {
  final stride = FrameQualityTuning.sampleStride;
  // The Laplacian reads one pixel out on every side, so the window is inset by
  // one *and* clamped into the buffer — the ROI comes from rounded fractions and
  // must not be trusted to land inside it.
  final x0 = _clampInt(crop.left, 0, width) + 1;
  final y0 = _clampInt(crop.top, 0, height) + 1;
  final x1 = _clampInt(crop.left + crop.width, 0, width) - 1;
  final y1 = _clampInt(crop.top + crop.height, 0, height) - 1;
  if (x1 <= x0 || y1 <= y0) return FrameQuality.unknown;

  // Welford would be tidier, but the values here are small integers and the
  // sample count is bounded, so the naive sum/sum-of-squares is exact enough and
  // one pass cheaper.
  var sum = 0.0;
  var sumSq = 0.0;
  var laplacianCount = 0;
  var bright = 0;
  var sampled = 0;

  for (var y = y0; y < y1; y += stride) {
    final row = y * width;
    final rowAbove = row - width;
    final rowBelow = row + width;
    for (var x = x0; x < x1; x++) {
      final centre = luma[row + x];
      // 4-neighbour Laplacian: |4c - N - S - E - W|.
      final l =
          4 * centre -
          luma[rowAbove + x] -
          luma[rowBelow + x] -
          luma[row + x - 1] -
          luma[row + x + 1];
      final v = l.toDouble();
      sum += v;
      sumSq += v * v;
      laplacianCount++;
      if (centre >= FrameQualityTuning.glareLevel) bright++;
      sampled++;
    }
  }

  if (laplacianCount == 0 || sampled == 0) return FrameQuality.unknown;
  final mean = sum / laplacianCount;
  final variance = (sumSq / laplacianCount) - (mean * mean);
  return FrameQuality(
    // Floating-point cancellation can push a perfectly flat region a hair below
    // zero; a negative "variance" would read as maximally blurry, which is
    // technically right but arrives via a route worth not depending on.
    sharpness: variance < 0 ? 0 : variance,
    glare: bright / sampled,
  );
}

/// `num.clamp` returns `num`, which cannot index a [Uint8List] without a cast at
/// every use. This keeps the arithmetic in `int` where it belongs.
int _clampInt(int value, int min, int max) =>
    value < min ? min : (value > max ? max : value);

/// One dense line for the diagnostics box, e.g. `qual: sharp=182 glare=3% ev=-0.7`.
///
/// Pure and here rather than in the widget so it can be host-tested, matching
/// `describeCameraHealth` and `describeDetectorHealth`. A `!` marks whichever
/// measurement is currently failing its gate, so the reason a frame was dropped
/// is readable at a glance rather than by comparing two numbers against
/// constants you'd have to remember.
String describeFrameQuality(FrameQuality? quality, double exposureOffset) {
  final parts = <String>[];
  if (quality == null) {
    parts.add('sharp=-  glare=-');
  } else {
    final blur = quality.isBlurry ? '!' : '';
    final glare = quality.isGlared ? '!' : '';
    parts.add('sharp=${quality.sharpness.round()}$blur');
    parts.add('glare=${(quality.glare * 100).round()}%$glare');
  }
  if (exposureOffset != 0) {
    parts.add('ev=${exposureOffset.toStringAsFixed(1)}');
  }
  return 'qual: ${parts.join('  ')}';
}

/// The exposure compensation to apply after observing [quality], given the
/// [current] offset.
///
/// Foil glare is *specular*: the camera meters for the average scene, the foil
/// returns a mirror highlight, and the artwork under it clips to white. Stopping
/// down recovers that structure. This is safe for matching specifically because
/// a pHash thresholds each DCT coefficient against the **median** of the block,
/// so a uniform darkening barely moves the descriptor while un-clipping the
/// highlights moves it a great deal — in the right direction.
///
/// Steps rather than jumps, and only reverses once glare is comfortably clear of
/// the gate ([FrameQualityTuning.glareRecoveryFraction], strictly below
/// [FrameQualityTuning.maxGlareFraction]): equal thresholds in both directions
/// would oscillate around the boundary, re-metering the camera every frame on a
/// device whose camera stack is already the least reliable part of the app.
double nextExposureOffset(double current, FrameQuality quality) {
  final next = quality.isGlared
      ? current - FrameQualityTuning.exposureStep
      : quality.glare <= FrameQualityTuning.glareRecoveryFraction
      ? current + FrameQualityTuning.exposureStep
      : current;
  return next.clamp(FrameQualityTuning.exposureFloor, 0.0).toDouble();
}
