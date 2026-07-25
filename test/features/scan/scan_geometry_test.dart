import 'package:flutter/painting.dart' show Offset, Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/features/scan/scan_geometry.dart';

/// A 3:4 sensor frame (portrait) against a taller, narrower phone viewport —
/// the real case: `BoxFit.cover` scales to fill the height and crops the sides.
const _frame = Size(3, 4);
const _tallViewport = Size(360, 720);

/// …and the opposite, where the viewport is relatively wider than the frame, so
/// cover fills the width and crops top and bottom.
const _wideViewport = Size(400, 400);

void main() {
  group('previewCoverScale', () {
    test('fills the axis that needs the most scaling', () {
      // 360/3 = 120, 720/4 = 180 -> height binds.
      expect(previewCoverScale(_frame, _tallViewport), 180);
      // 400/3 = 133.3, 400/4 = 100 -> width binds.
      expect(previewCoverScale(_frame, _wideViewport), closeTo(133.33, 0.01));
    });

    test('degenerate frames do not divide by zero', () {
      expect(previewCoverScale(Size.zero, _tallViewport), 1);
    });
  });

  group('frameFractionToViewport', () {
    test('the frame centre is the viewport centre', () {
      expect(
        frameFractionToViewport(const Offset(0.5, 0.5), _frame, _tallViewport),
        const Offset(180, 360),
      );
      expect(
        frameFractionToViewport(const Offset(0.5, 0.5), _frame, _wideViewport),
        const Offset(200, 200),
      );
    });

    test('the cropped axis overflows the viewport symmetrically', () {
      // Height binds, so the frame's full width (3*180 = 540) overflows the
      // 360-wide viewport by 90 on each side.
      final left =
          frameFractionToViewport(const Offset(0, 0.5), _frame, _tallViewport);
      final right =
          frameFractionToViewport(const Offset(1, 0.5), _frame, _tallViewport);
      expect(left.dx, -90);
      expect(right.dx, 450);
      // The binding axis lines up exactly with the viewport edges.
      final top =
          frameFractionToViewport(const Offset(0.5, 0), _frame, _tallViewport);
      final bottom =
          frameFractionToViewport(const Offset(0.5, 1), _frame, _tallViewport);
      expect(top.dy, 0);
      expect(bottom.dy, 720);
    });

    test('crops top and bottom when the viewport is the wider shape', () {
      final top =
          frameFractionToViewport(const Offset(0.5, 0), _frame, _wideViewport);
      final bottom =
          frameFractionToViewport(const Offset(0.5, 1), _frame, _wideViewport);
      // 4 * 133.33 = 533.3 tall against a 400 viewport -> 66.67 off each end.
      expect(top.dy, closeTo(-66.67, 0.01));
      expect(bottom.dy, closeTo(466.67, 0.01));
      expect(
        frameFractionToViewport(const Offset(0, 0.5), _frame, _wideViewport).dx,
        0,
      );
    });

    test('a matching aspect ratio maps fractions straight through', () {
      const square = Size(10, 10);
      const viewport = Size(200, 200);
      expect(
        frameFractionToViewport(const Offset(0.25, 0.75), square, viewport),
        const Offset(50, 150),
      );
    });
  });
}
