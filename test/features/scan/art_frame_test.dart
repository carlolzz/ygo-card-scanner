import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/features/scan/art_frame.dart';

void main() {
  group('lumaFromYPlane', () {
    test('copies a tight buffer when there is no row padding', () {
      final bytes = Uint8List.fromList([1, 2, 3, 4, 5, 6]); // 3x2
      final luma = lumaFromYPlane(bytes, 3, 2, 3);
      expect(luma, [1, 2, 3, 4, 5, 6]);
    });

    test('drops row-stride padding', () {
      // width 2, height 2, stride 4: two padding bytes at the end of each row.
      final bytes = Uint8List.fromList([1, 2, 9, 9, 3, 4, 9, 9]);
      final luma = lumaFromYPlane(bytes, 2, 2, 4);
      expect(luma, [1, 2, 3, 4]);
    });

    test('returns a copy independent of the source buffer', () {
      final bytes = Uint8List.fromList([10, 20, 30, 40]);
      final luma = lumaFromYPlane(bytes, 2, 2, 2);
      bytes[0] = 99;
      expect(luma[0], 10);
    });
  });

  group('lumaFromBgra', () {
    test('applies ITU-R 601 weights', () {
      // One white then one black pixel (BGRA).
      final bytes = Uint8List.fromList([255, 255, 255, 255, 0, 0, 0, 255]);
      final luma = lumaFromBgra(bytes, 2, 1, 8);
      expect(luma[0], 255); // white
      expect(luma[1], 0); // black
    });

    test('pure red maps to ~0.299 luma', () {
      final bytes = Uint8List.fromList([0, 0, 255, 255]); // B G R A
      final luma = lumaFromBgra(bytes, 1, 1, 4);
      expect(luma[0], closeTo(76, 1)); // 255 * 0.299
    });
  });

  group('ArtFrame.oriented', () {
    test('is a no-op at 0 degrees', () {
      final frame = ArtFrame(
        luma: Uint8List.fromList([1, 2, 3, 4]),
        width: 2,
        height: 2,
      );
      expect(identical(frame.oriented(), frame), isTrue);
    });

    test('rotates 90 degrees clockwise and swaps dimensions', () {
      // 3x2 source:
      //   1 2 3
      //   4 5 6
      // 90 CW -> 2x3:
      //   4 1
      //   5 2
      //   6 3
      final frame = ArtFrame(
        luma: Uint8List.fromList([1, 2, 3, 4, 5, 6]),
        width: 3,
        height: 2,
        rotationDegrees: 90,
      );
      final r = frame.oriented();
      expect(r.width, 2);
      expect(r.height, 3);
      expect(r.luma, [4, 1, 5, 2, 6, 3]);
      expect(r.rotationDegrees, 0);
    });

    test('rotates 180 degrees', () {
      final frame = ArtFrame(
        luma: Uint8List.fromList([1, 2, 3, 4, 5, 6]),
        width: 3,
        height: 2,
        rotationDegrees: 180,
      );
      final r = frame.oriented();
      expect(r.width, 3);
      expect(r.height, 2);
      expect(r.luma, [6, 5, 4, 3, 2, 1]);
    });
  });
}
