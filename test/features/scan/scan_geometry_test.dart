import 'package:flutter/painting.dart' show Offset, Rect, Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/core/theme/tokens.dart';
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

  // The guide box sits below the viewport's centre so the overlays above it —
  // the diagnostics readout above all — have a band tall enough to be read in
  // one glance. Everything here is really one invariant: the box the user is
  // asked to fill and the region the detector searches are the same rectangle,
  // wherever that rectangle is.
  group('reticleRectInViewport', () {
    const phone = Size(393, 851);

    test('the box sits the configured fraction below centre', () {
      final rect = reticleRectInViewport(phone);
      expect(
        rect.center.dy - phone.height / 2,
        closeTo(phone.height * ScanReticleTokens.verticalOffsetFraction, 0.01),
      );
      expect(rect.center.dx, closeTo(phone.width / 2, 0.01));
    });

    test('the offset changes the position and nothing else', () {
      final rect = reticleRectInViewport(phone);
      expect(rect.width, closeTo(phone.width * ScanReticleTokens.widthFraction, 0.01));
      expect(
        rect.width / rect.height,
        closeTo(ScanReticleTokens.cardAspectRatio, 0.0001),
      );
    });

    // The clamp is against the *inflated* rect, not the box: `detectionRoiInFrame`
    // grows it by `reticleRoiMargin` on every side and then clamps in frame
    // space, so an offset that pushed the inflated rect off the bottom would
    // silently truncate the searched region on one edge — worse recognition
    // with no visible symptom at all.
    for (final viewport in const [
      phone,
      Size(360, 640),
      Size(800, 600),
      Size(851, 393), // landscape
      Size(320, 480),
    ]) {
      test('the box plus its search margin stays inside $viewport', () {
        final rect = reticleRectInViewport(viewport);
        final margin = rect.height * ScanDetectionTokens.reticleRoiMargin;
        expect(rect.top - margin, greaterThanOrEqualTo(-0.01));
        expect(
          rect.bottom + margin,
          lessThanOrEqualTo(viewport.height + 0.01),
          reason: 'the inflated search region must not run off the bottom',
        );
      });
    }

    test('the offset is clamped, never negative, when there is no slack', () {
      // Short and wide: `maxHeightFraction` binds and the margin eats what is
      // left, so the box has to stay centred rather than move up.
      const squat = Size(900, 300);
      final rect = reticleRectInViewport(squat);
      expect(rect.center.dy, greaterThanOrEqualTo(squat.height / 2 - 0.01));
    });

    test('the detection ROI follows the box down and stays in range', () {
      const frame = Size(720, 1280);
      final roi = detectionRoiInFrame(viewport: phone, frame: frame);
      final centred = Rect.fromCenter(
        center: Offset(phone.width / 2, phone.height / 2),
        width: reticleRectInViewport(phone).width,
        height: reticleRectInViewport(phone).height,
      );

      expect(roi.top, greaterThanOrEqualTo(0));
      expect(roi.bottom, lessThanOrEqualTo(1));
      // Strictly lower than it would be for a centred box — the pairing of the
      // drawn rect and the searched region is what is under test, not either on
      // its own.
      expect(
        roi.center.dy,
        greaterThan(
          viewportToFrameFraction(centred.center, frame, phone).dy,
        ),
      );
    });
  });
}
