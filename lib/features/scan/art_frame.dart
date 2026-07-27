import 'dart:typed_data';

/// A single camera frame reduced to a grayscale (luma) buffer, for perceptual
/// hashing in the artwork-match fallback.
///
/// Deliberately plugin-agnostic (plain [Uint8List] + ints), so the hashing and
/// orientation logic is unit-testable with a hand-built buffer — the same reason
/// `RecognizedSpan` is kept ML-Kit-free for `extractPasscode`. The conversion
/// from a `CameraImage` lives in `CameraScanService` (which owns the plugin) via
/// the pure [lumaFromYPlane] / [lumaFromBgra] helpers below.
class ArtFrame {
  const ArtFrame({
    required this.luma,
    required this.width,
    required this.height,
    this.rotationDegrees = 0,
  }) : assert(rotationDegrees == 0 ||
            rotationDegrees == 90 ||
            rotationDegrees == 180 ||
            rotationDegrees == 270);

  /// Row-major grayscale, length `width*height`, one byte per pixel.
  final Uint8List luma;
  final int width;
  final int height;

  /// Clockwise degrees this buffer must be rotated to appear upright (as ML Kit
  /// reports for the frame). One of 0/90/180/270.
  final int rotationDegrees;

  /// Returns an upright copy (rotation applied, [rotationDegrees] == 0). Runs
  /// once per user tap, so an O(pixels) rotate is fine.
  ArtFrame oriented() {
    if (rotationDegrees == 0) return this;
    final rotated = _rotateCw(luma, width, height, rotationDegrees);
    final swap = rotationDegrees == 90 || rotationDegrees == 270;
    return ArtFrame(
      luma: rotated,
      width: swap ? height : width,
      height: swap ? width : height,
    );
  }
}

/// Returns a 180°-rotated copy of a row-major luma buffer (same dimensions).
///
/// Used to re-hash a card that may be upside-down: the detector's shape gates
/// fold in-plane tilt into [0, 90), so a card held at 180° passes all of them
/// and is warped inverted, hashing to noise with no visible symptom. A 180°
/// rotation is exactly a reversal of the buffer, since the last pixel of the
/// last row becomes the first pixel of the first.
Uint8List rotate180(Uint8List luma, int width, int height) {
  final count = width * height;
  final out = Uint8List(count);
  for (var i = 0; i < count; i++) {
    out[i] = luma[count - 1 - i];
  }
  return out;
}

/// Extracts the Y (luma) plane of an NV21 frame into a tight `width*height`
/// buffer, dropping any row-stride padding. On NV21 the luma plane is the first
/// `width` bytes of each `bytesPerRow`-strided row — already grayscale. Always
/// returns a fresh copy: the caller caches it across frames while the camera
/// plugin may recycle the source buffer.
Uint8List lumaFromYPlane(
  Uint8List bytes,
  int width,
  int height,
  int bytesPerRow,
) {
  final out = Uint8List(width * height);
  for (var row = 0; row < height; row++) {
    final src = row * bytesPerRow;
    out.setRange(row * width, row * width + width, bytes, src);
  }
  return out;
}

/// Converts a BGRA8888 frame to luma using the ITU-R 601 weights PIL's
/// `convert('L')` uses (`0.299R + 0.587G + 0.114B`), matching the index build.
Uint8List lumaFromBgra(
  Uint8List bytes,
  int width,
  int height,
  int bytesPerRow,
) {
  final out = Uint8List(width * height);
  for (var row = 0; row < height; row++) {
    var src = row * bytesPerRow;
    var dst = row * width;
    for (var x = 0; x < width; x++) {
      final b = bytes[src];
      final g = bytes[src + 1];
      final r = bytes[src + 2];
      // Fixed-point 601 luma, rounded: (r*77 + g*150 + b*29) / 256.
      out[dst] = (r * 77 + g * 150 + b * 29 + 128) >> 8;
      src += 4;
      dst++;
    }
  }
  return out;
}

/// Rotates a grayscale buffer clockwise by 90/180/270 degrees.
Uint8List _rotateCw(Uint8List src, int w, int h, int degrees) {
  final out = Uint8List(w * h);
  switch (degrees) {
    case 90:
      // dst dims (h x w); dst[y'][x'] = src[h-1-x'][y']
      for (var yp = 0; yp < w; yp++) {
        for (var xp = 0; xp < h; xp++) {
          out[yp * h + xp] = src[(h - 1 - xp) * w + yp];
        }
      }
    case 180:
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          out[y * w + x] = src[(h - 1 - y) * w + (w - 1 - x)];
        }
      }
    case 270:
      // dst dims (h x w); dst[y'][x'] = src[x'][w-1-y']
      for (var yp = 0; yp < w; yp++) {
        for (var xp = 0; xp < h; xp++) {
          out[yp * h + xp] = src[xp * w + (w - 1 - yp)];
        }
      }
  }
  return out;
}
