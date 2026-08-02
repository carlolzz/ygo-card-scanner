import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/features/scan/frame_quality.dart';
import 'package:ygo_scanner/features/scan/phash.dart';
import 'package:ygo_scanner/features/scan/scan_sample.dart';

void main() {
  group('encodePgm', () {
    test('writes a binary P5 header followed by the raw pixels', () {
      final luma = Uint8List.fromList([0, 64, 128, 255]);
      final pgm = encodePgm(luma, 2, 2);

      // The header has to be exactly this or nothing will open the file.
      expect(ascii.decode(pgm.sublist(0, 11)), 'P5\n2 2\n255\n');
      expect(pgm.sublist(11), [0, 64, 128, 255]);
      expect(pgm.length, 11 + 4);
    });

    test('a short buffer is padded rather than silently truncated', () {
      // A truncated PGM still *opens*, showing a partial image — a worse
      // failure than a blank one, because it looks like real data.
      final pgm = encodePgm(Uint8List.fromList([9]), 4, 4);
      expect(pgm.length, ascii.encode('P5\n4 4\n255\n').length + 16);
    });
  });

  group('cropLuma', () {
    // 4x4 counting up, so a crop's contents identify its position exactly.
    final source = Uint8List.fromList(List.generate(16, (i) => i));

    test('copies the requested rectangle', () {
      final out = cropLuma(source, 4, 4, const PixelRect(1, 1, 2, 2));
      expect(out, [5, 6, 9, 10]);
    });

    test('clamps a rectangle reaching past the buffer', () {
      final out = cropLuma(source, 4, 4, const PixelRect(2, 2, 10, 10));
      expect(out, [10, 11, 14, 15]);
    });

    test('a degenerate rectangle yields nothing rather than throwing', () {
      expect(cropLuma(source, 4, 4, const PixelRect(9, 9, 2, 2)), isEmpty);
    });
  });

  group('sampleMetadataJson', () {
    final sample = ArtSample(
      luma: Uint8List(16),
      width: 4,
      height: 4,
      crop: const PixelRect(1, 1, 2, 2),
      quality: const FrameQuality(sharpness: 12.5, glare: 0.25),
      artBoxLocked: false,
      matches: const [
        (passcode: '46986414', distance: 40),
        (passcode: '89631139', distance: 61),
      ],
    );

    test('records everything needed to interpret the images later', () {
      final json =
          jsonDecode(
                sampleMetadataJson(
                  sample,
                  at: DateTime.utc(2026, 8, 2, 10, 30),
                ),
              )
              as Map<String, dynamic>;

      expect(json['captured_at'], '2026-08-02T10:30:00.000Z');
      expect(json['card'], {'width': 4, 'height': 4});
      expect(json['art_box'], {
        'left': 1,
        'top': 1,
        'width': 2,
        'height': 2,
        // The most useful field in the file: a sample that ranks badly *and*
        // reads false is a rectification problem, not an optics one.
        'locked': false,
      });
      expect(json['quality'], {'sharpness': 12.5, 'glare': 0.25});
      expect((json['matches'] as List).first, {
        'passcode': '46986414',
        'distance': 40,
      });
    });

    test('an unassessed frame records a null quality rather than zeros', () {
      final json =
          jsonDecode(
                sampleMetadataJson(
                  ArtSample(
                    luma: Uint8List(4),
                    width: 2,
                    height: 2,
                    crop: const PixelRect(0, 0, 2, 2),
                    quality: null,
                    artBoxLocked: true,
                    matches: const [],
                  ),
                  at: DateTime.utc(2026),
                ),
              )
              as Map<String, dynamic>;
      expect(json['quality'], isNull);
    });
  });
}
