import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/core/theme/tokens.dart';
import 'package:ygo_scanner/features/scan/frame_quality.dart';
import 'package:ygo_scanner/features/scan/phash.dart';

/// A flat buffer of one value.
Uint8List _flat(int width, int height, int value) =>
    Uint8List(width * height)..fillRange(0, width * height, value);

/// A 1px checkerboard — maximal high-frequency content, i.e. maximal "sharpness".
Uint8List _checker(int width, int height, {int low = 0, int high = 255}) {
  final out = Uint8List(width * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      out[y * width + x] = (x + y).isEven ? high : low;
    }
  }
  return out;
}

/// A 3x3 box blur, standing in for defocus/motion smear.
Uint8List _blur(Uint8List src, int width, int height) {
  final out = Uint8List(width * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      var sum = 0;
      var count = 0;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final ny = y + dy;
          final nx = x + dx;
          if (ny < 0 || ny >= height || nx < 0 || nx >= width) continue;
          sum += src[ny * width + nx];
          count++;
        }
      }
      out[y * width + x] = sum ~/ count;
    }
  }
  return out;
}

void main() {
  const w = 64;
  const h = 64;
  const whole = PixelRect(0, 0, w, h);

  group('assessCrop — sharpness', () {
    test('a flat region has zero Laplacian variance and reads as blurry', () {
      final q = assessCrop(_flat(w, h, 128), w, h, whole);
      expect(q.sharpness, 0);
      expect(q.isBlurry, isTrue);
      expect(q.isUsable, isFalse);
    });

    // Regression: this failed while `assessCrop` strided *both* axes. A lattice
    // sampling a 1px checkerboard lands on one parity every time, so every
    // Laplacian response is identical and the variance is 0 — the sharpest
    // possible input scored as perfectly blurred. Striding rows only fixed it.
    test('a checkerboard scores far above the blur gate', () {
      final q = assessCrop(_checker(w, h), w, h, whole);
      expect(q.sharpness, greaterThan(FrameQualityTuning.minSharpness));
      expect(q.isBlurry, isFalse);
    });

    test('the sampler does not alias against periodic detail', () {
      // Same guard stated directly, at several periods, so a future change to
      // the sampling pattern has to stay honest at more than one frequency.
      for (final period in [1, 2, 3, 4]) {
        final buffer = Uint8List(w * h);
        for (var y = 0; y < h; y++) {
          for (var x = 0; x < w; x++) {
            buffer[y * w + x] = ((x ~/ period) + (y ~/ period)).isEven ? 0 : 255;
          }
        }
        expect(
          assessCrop(buffer, w, h, whole).isBlurry,
          isFalse,
          reason: 'a $period px checkerboard is not blurry',
        );
      }
    });

    test('blurring the same content collapses the score', () {
      final sharp = assessCrop(_checker(w, h), w, h, whole);
      final soft = assessCrop(_blur(_checker(w, h), w, h), w, h, whole);
      // The whole point of the measure: same scene, less focus, lower number.
      expect(soft.sharpness, lessThan(sharp.sharpness / 2));
    });

    test('a degenerate crop is unknown rather than a divide by zero', () {
      final q = assessCrop(_flat(w, h, 128), w, h, const PixelRect(5, 5, 1, 1));
      expect(q.sharpness, FrameQuality.unknown.sharpness);
      expect(q.glare, 0);
    });

    test('a crop reaching past the buffer is clamped, not read out of bounds', () {
      // The ROI is built from rounded fractions, so this is a real possibility
      // rather than a defensive flourish.
      expect(
        () => assessCrop(_checker(w, h), w, h, const PixelRect(-8, -8, w + 32, h + 32)),
        returnsNormally,
      );
    });
  });

  group('assessCrop — glare', () {
    test('an all-white region is fully clipped', () {
      final q = assessCrop(_flat(w, h, 255), w, h, whole);
      expect(q.glare, 1.0);
      expect(q.isGlared, isTrue);
      expect(q.isUsable, isFalse);
    });

    test('a mid-grey region has no clipping', () {
      final q = assessCrop(_flat(w, h, 128), w, h, whole);
      expect(q.glare, 0);
      expect(q.isGlared, isFalse);
    });

    test('glare counts only pixels at or above the level', () {
      final justUnder = FrameQualityTuning.glareLevel - 1;
      expect(assessCrop(_flat(w, h, justUnder), w, h, whole).glare, 0);
      expect(
        assessCrop(_flat(w, h, FrameQualityTuning.glareLevel), w, h, whole).glare,
        1.0,
      );
    });

    test('a sharp but blown-out frame is rejected on glare alone', () {
      // Foil: high contrast structure *and* clipped highlights over most of it.
      final q = assessCrop(_checker(w, h, low: 200), w, h, whole);
      expect(q.isBlurry, isFalse, reason: 'checkerboard is high frequency');
      expect(q.isGlared, isTrue);
      expect(q.isUsable, isFalse);
    });

    test('the crop is respected — glare outside it does not count', () {
      final buffer = _flat(w, h, 128);
      // Blow out the top half only.
      buffer.fillRange(0, w * (h ~/ 2), 255);
      final bottom = assessCrop(buffer, w, h, PixelRect(0, h ~/ 2 + 2, w, h ~/ 2 - 2));
      expect(bottom.glare, 0);
    });
  });

  group('describeFrameQuality', () {
    test('renders both measurements and omits a zero exposure offset', () {
      final line = describeFrameQuality(
        const FrameQuality(sharpness: 182.4, glare: 0.03),
        0,
      );
      expect(line, 'qual: sharp=182  glare=3%');
    });

    test('marks whichever gate is failing', () {
      final blurry = describeFrameQuality(
        const FrameQuality(sharpness: 1, glare: 0),
        0,
      );
      expect(blurry, contains('sharp=1!'));
      expect(blurry, isNot(contains('glare=0%!')));

      final glared = describeFrameQuality(
        const FrameQuality(sharpness: 999, glare: 0.5),
        0,
      );
      expect(glared, contains('glare=50%!'));
      expect(glared, isNot(contains('sharp=999!')));
    });

    test('shows a non-zero exposure offset', () {
      final line = describeFrameQuality(
        const FrameQuality(sharpness: 100, glare: 0),
        -0.9,
      );
      expect(line, endsWith('ev=-0.9'));
    });

    test('renders placeholders when no frame was assessed', () {
      expect(describeFrameQuality(null, 0), contains('sharp=-'));
    });
  });

  group('nextExposureOffset', () {
    const glared = FrameQuality(sharpness: 999, glare: 0.5);
    const clear = FrameQuality(sharpness: 999, glare: 0);

    test('steps down while glare is over the gate', () {
      expect(nextExposureOffset(0, glared), -FrameQualityTuning.exposureStep);
    });

    test('never goes below the floor', () {
      var ev = 0.0;
      for (var i = 0; i < 100; i++) {
        ev = nextExposureOffset(ev, glared);
      }
      expect(ev, FrameQualityTuning.exposureFloor);
    });

    test('recovers back toward zero and stops there', () {
      var ev = FrameQualityTuning.exposureFloor;
      for (var i = 0; i < 100; i++) {
        ev = nextExposureOffset(ev, clear);
      }
      expect(ev, 0);
    });

    test('holds inside the hysteresis band instead of oscillating', () {
      // Between glareRecoveryFraction and maxGlareFraction: not bad enough to
      // stop down further, not good enough to give the compensation back. Equal
      // thresholds here would re-meter the camera on every single frame.
      const between = FrameQuality(sharpness: 999, glare: 0.06);
      expect(between.isGlared, isFalse);
      expect(nextExposureOffset(-0.6, between), -0.6);
    });

    test('the recovery threshold really is stricter than the reject one', () {
      expect(
        FrameQualityTuning.glareRecoveryFraction,
        lessThan(FrameQualityTuning.maxGlareFraction),
      );
    });
  });
}
