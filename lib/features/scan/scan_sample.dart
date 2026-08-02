import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'frame_quality.dart';
import 'hash_index.dart';
import 'phash.dart';

/// One captured frame from the recognition pipeline: the rectified card and the
/// exact artwork window that was hashed from it.
///
/// **This exists to make the next change legitimate.**
/// `.claude/skills/scan-pipeline.md` says not to add aggressive image
/// preprocessing "before you have real failure samples to test against", and
/// until now there was no way to obtain one — the pixels the pipeline actually
/// hashes live for a few milliseconds inside a detector isolate and are never
/// written anywhere. Highlight normalisation, a wider art-box search, a
/// different descriptor: none of them can be evaluated honestly against
/// synthetic buffers or against clean YGOPRODeck renders, because the whole
/// problem is what a phone camera does to a foil card on a kitchen table.
class ArtSample {
  const ArtSample({
    required this.luma,
    required this.width,
    required this.height,
    required this.crop,
    required this.quality,
    required this.artBoxLocked,
    required this.matches,
  });

  /// The perspective-corrected card, row-major grayscale.
  final Uint8List luma;
  final int width;
  final int height;

  /// The artwork window within it — the pixels that were hashed.
  final PixelRect crop;

  final FrameQuality? quality;

  /// Whether the crop came from a located art box or the fixed fractional ROI.
  /// The single most useful field here: a sample that ranks badly *and* reads
  /// `false` is a rectification problem, not an optics one.
  final bool artBoxLocked;

  /// What the index said about this frame, nearest first.
  final List<({String passcode, int distance})> matches;
}

/// Encodes a grayscale buffer as binary PGM (`P5`).
///
/// PGM rather than PNG because it needs no encoder, no dependency and no
/// isolate: a 15-byte header followed by the raw bytes we already hold. PIL,
/// OpenCV and ImageMagick all open it directly, so `tools/` can analyse a
/// captured sample with the same `Image.open` the index builder already uses.
Uint8List encodePgm(Uint8List luma, int width, int height) {
  final header = ascii.encode('P5\n$width $height\n255\n');
  final out = Uint8List(header.length + width * height);
  out.setRange(0, header.length, header);
  // A short buffer would otherwise write a truncated image that still *opens*,
  // which is a worse failure than not writing one.
  final pixels = width * height;
  out.setRange(
    header.length,
    header.length + pixels,
    luma.length >= pixels ? luma : Uint8List(pixels),
  );
  return out;
}

/// Copies [crop] out of a row-major luma buffer into a tight one.
Uint8List cropLuma(
  Uint8List luma,
  int width,
  int height,
  PixelRect crop,
) {
  final left = crop.left < 0 ? 0 : (crop.left > width ? width : crop.left);
  final top = crop.top < 0 ? 0 : (crop.top > height ? height : crop.top);
  var right = crop.left + crop.width;
  var bottom = crop.top + crop.height;
  if (right > width) right = width;
  if (bottom > height) bottom = height;
  final w = right - left;
  final h = bottom - top;
  if (w <= 0 || h <= 0) return Uint8List(0);
  final out = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    final src = (top + y) * width + left;
    out.setRange(y * w, y * w + w, luma, src);
  }
  return out;
}

/// The JSON sidecar describing a sample — everything needed to interpret the
/// two images without having been there when they were taken.
String sampleMetadataJson(ArtSample sample, {required DateTime at}) {
  final quality = sample.quality;
  return const JsonEncoder.withIndent('  ').convert({
    'captured_at': at.toUtc().toIso8601String(),
    'card': {'width': sample.width, 'height': sample.height},
    'art_box': {
      'left': sample.crop.left,
      'top': sample.crop.top,
      'width': sample.crop.width,
      'height': sample.crop.height,
      'locked': sample.artBoxLocked,
    },
    'quality': quality == null
        ? null
        : {'sharpness': quality.sharpness, 'glare': quality.glare},
    'matches': [
      for (final match in sample.matches)
        {'passcode': match.passcode, 'distance': match.distance},
    ],
  });
}

/// Writes a sample to `<app documents>/scan_samples/` as two PGMs plus a JSON
/// sidecar, and returns the paths (card, art, metadata).
///
/// The app-documents directory is not browsable on Android, so the caller hands
/// these to the share sheet — the same route the CSV export takes.
Future<List<String>> writeArtSample(ArtSample sample, {DateTime? now}) async {
  final at = now ?? DateTime.now();
  final dir = Directory(
    p.join((await getApplicationDocumentsDirectory()).path, 'scan_samples'),
  );
  await dir.create(recursive: true);

  final stamp = at
      .toUtc()
      .toIso8601String()
      .replaceAll(':', '-')
      .replaceAll('.', '-');
  final cardPath = p.join(dir.path, '$stamp-card.pgm');
  final artPath = p.join(dir.path, '$stamp-art.pgm');
  final metaPath = p.join(dir.path, '$stamp.json');

  await File(cardPath).writeAsBytes(
    encodePgm(sample.luma, sample.width, sample.height),
  );
  final art = cropLuma(sample.luma, sample.width, sample.height, sample.crop);
  await File(artPath).writeAsBytes(
    encodePgm(art, sample.crop.width, sample.crop.height),
  );
  await File(metaPath).writeAsString(sampleMetadataJson(sample, at: at));
  return [cardPath, artPath, metaPath];
}

/// Builds a sample from a ranked frame. Kept here rather than in
/// [PHashArtMatcher] so the matcher only has to retain the pixels.
ArtSample buildArtSample({
  required Uint8List luma,
  required int width,
  required int height,
  required PixelRect crop,
  required FrameQuality? quality,
  required bool artBoxLocked,
  required List<HashMatch> matches,
}) => ArtSample(
  luma: luma,
  width: width,
  height: height,
  crop: crop,
  quality: quality,
  artBoxLocked: artBoxLocked,
  matches: [
    for (final match in matches)
      (passcode: match.passcode, distance: match.distance),
  ],
);
