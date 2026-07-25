import 'dart:typed_data';

import 'package:flutter/painting.dart' show Offset, Rect, Size;
import 'package:opencv_core/opencv.dart' as cv;

import '../../core/theme/tokens.dart';
import 'art_frame.dart';
import 'card_detector.dart';
import 'card_quad.dart';

/// Production [CardDetector] backed by OpenCV: grayscale edges inside the guide
/// box → the most card-shaped convex quadrilateral → perspective warp to a
/// canonical upright card → a second pass that locates the artwork window
/// inside it. This is the only file in the app that imports OpenCV; everything
/// else depends on the [CardDetector] interface, so host tests never touch the
/// native library.
///
/// It deliberately contains **no decisions**: which quad wins is
/// `card_quad.dart`'s job, and where to look is `scan_geometry.dart`'s — both
/// pure and tested, because a wrong threshold here doesn't crash, it quietly
/// recognises the wrong card. What's left is Mat lifecycle, the edge map, the
/// contour call, the warp, and the art-box locator.
class OpenCvCardDetector implements CardDetector {
  const OpenCvCardDetector();

  /// The canonical warped card size (59:86, scaled). Only the ratio matters —
  /// the art box is resized to 32x32 for hashing afterwards.
  static const int _cardW = 421;
  static const int _cardH = 614;

  /// Longest edge the *detection* runs at. Downscaling keeps the per-frame cost
  /// low; the warp reads from the full-resolution image, since
  /// `warpPerspective`'s cost follows its destination size, not its source.
  static const int _workLongEdge = 480;

  /// approxPolyDP epsilons (as a fraction of the contour perimeter) tried in
  /// order. A single tight value rejects cards whose corners the edge map
  /// rounded off (sleeves, soft focus); trying looser ones recovers them.
  static const List<double> _approxEpsilons = [0.02, 0.03, 0.05];

  /// How far each edge of the artwork window found inside the rectified card
  /// may sit from [ArtMatchTuning.artBoxRoi] (as a fraction of the card) and
  /// still be believed. Wide enough to absorb the sleeve-vs-card scale error
  /// this pass exists to correct, tight enough that a text box or the card
  /// frame can't pose as the artwork.
  static const double _artBoxSlack = 0.06;

  /// …and how far its aspect ratio may deviate from the expected art window's,
  /// as a factor. A thin line or a fragment whose bounding box happens to land
  /// in the right place is rejected here.
  static const double _artBoxAspectTolerance = 1.12;

  @override
  DetectedCard? detectCard(ArtFrame frame, {Rect? searchRoi}) {
    if (frame.luma.length != frame.width * frame.height) return null;
    final scratch = <cv.Mat>[];
    cv.VecVecPoint? contours;
    cv.VecVec4i? hierarchy;
    cv.VecPoint2f? src;
    cv.VecPoint2f? dst;
    try {
      // Grayscale Mat from the luma plane, then rotate upright.
      var gray = cv.Mat.fromList(
        frame.height,
        frame.width,
        cv.MatType.CV_8UC1,
        frame.luma,
      );
      scratch.add(gray);
      final rotateCode = _rotateCode(frame.rotationDegrees);
      if (rotateCode != null) {
        gray = cv.rotate(gray, rotateCode);
        scratch.add(gray);
      }

      final roi = searchRoi ?? ArtMatchTuning.cardSearchRoi;

      // Crop to the search region *before* building the edge map, not merely
      // filter candidates afterwards. Canny's thresholds come from an Otsu
      // split of the histogram; over the whole frame that histogram is
      // dominated by whatever the card is lying on, so on a busy or bright
      // surface the card's own edges wash out. Over the guide box it is
      // dominated by the card. Dilation also can't merge the card into a
      // background blob that isn't in the buffer.
      final region = cv.Rect(
        (roi.left * gray.cols).round().clamp(0, gray.cols - 1),
        (roi.top * gray.rows).round().clamp(0, gray.rows - 1),
        (roi.width * gray.cols).round().clamp(1, gray.cols),
        (roi.height * gray.rows).round().clamp(1, gray.rows),
      );
      final cropped = gray.region(region);
      scratch.add(cropped);

      // Detection resolution. Spending the whole budget on the guide box rather
      // than the frame roughly doubles the card's linear resolution.
      var work = cropped;
      final longEdge = cropped.cols > cropped.rows ? cropped.cols : cropped.rows;
      final workScale = longEdge > _workLongEdge ? _workLongEdge / longEdge : 1.0;
      if (workScale != 1.0) {
        work = cv.resize(cropped, (
          (cropped.cols * workScale).round(),
          (cropped.rows * workScale).round(),
        ));
        scratch.add(work);
      }

      final closed = _edgeMap(work, scratch);
      final found = cv.findContours(
        closed,
        cv.RETR_LIST,
        cv.CHAIN_APPROX_SIMPLE,
      );
      contours = found.$1;
      hierarchy = found.$2;

      // Everything below is in the *cropped, downscaled* image's coordinates.
      // The search region is now the whole buffer, so candidates are gated
      // against the unit rect.
      final workSize = Size(work.cols.toDouble(), work.rows.toDouble());
      final quads = <List<Offset>>[];
      for (final contour in contours) {
        final approx = _approxQuad(contour);
        if (approx == null) continue;
        quads.add(
          orderQuadCorners([
            for (var i = 0; i < approx.length; i++)
              Offset(approx[i].x.toDouble(), approx[i].y.toDouble()),
          ]),
        );
        approx.dispose();
      }

      final best = selectCardQuad(
        quads,
        imageSize: workSize,
        searchRoi: const Rect.fromLTRB(0, 0, 1, 1),
      );
      // No card-shaped candidate is a miss, full stop. A wrong quad still
      // produces a hash, and a hash always ranks *something*, so it would
      // surface as a confidently wrong card rather than as a failure.
      if (best == null) return null;

      // Back to full-resolution coordinates for the warp: free accuracy, since
      // warpPerspective's cost follows the 421x614 destination.
      final fullResCorners = [
        for (final corner in best.corners)
          Offset(
            region.x + corner.dx / workScale,
            region.y + corner.dy / workScale,
          ),
      ];

      src = cv.VecPoint2f.fromList([
        for (final corner in fullResCorners)
          cv.Point2f(corner.dx, corner.dy),
      ]);
      dst = cv.VecPoint2f.fromList([
        cv.Point2f(0, 0),
        cv.Point2f(_cardW.toDouble(), 0),
        cv.Point2f(_cardW.toDouble(), _cardH.toDouble()),
        cv.Point2f(0, _cardH.toDouble()),
      ]);
      final transform = cv.getPerspectiveTransform2f(src, dst);
      scratch.add(transform);
      final warped = cv.warpPerspective(gray, transform, (_cardW, _cardH));
      scratch.add(warped);

      final artBox = _findArtBox(warped, scratch);

      // Copy the pixels out before the native Mats are freed.
      final luma = Uint8List.fromList(warped.data);
      return DetectedCard(
        image: ArtFrame(
          luma: luma,
          width: warped.cols,
          height: warped.rows,
          rotationDegrees: 0,
        ),
        quad: [
          for (final corner in fullResCorners)
            Offset(corner.dx / gray.cols, corner.dy / gray.rows),
        ],
        artBox: artBox,
      );
    } catch (_) {
      // Any detection/OpenCV failure is a miss, never a crash — the frame just
      // yields no candidate and scanning continues.
      return null;
    } finally {
      for (final mat in scratch) {
        mat.dispose();
      }
      contours?.dispose();
      hierarchy?.dispose();
      src?.dispose();
      dst?.dispose();
    }
  }

  /// Edge map: blur → Canny → dilate to close gaps in the card border. Canny
  /// thresholds are derived from Otsu rather than fixed, so the edge map adapts
  /// to the frame's exposure instead of washing out (bright) or vanishing (dim)
  /// under a one-size threshold. Every Mat produced is added to [scratch].
  static cv.Mat _edgeMap(cv.Mat source, List<cv.Mat> scratch) {
    final blurred = cv.gaussianBlur(source, (5, 5), 0);
    scratch.add(blurred);
    final (otsu, otsuMask) = cv.threshold(
      blurred,
      0,
      255,
      cv.THRESH_BINARY | cv.THRESH_OTSU,
    );
    scratch.add(otsuMask);
    final high = otsu <= 0 ? 150.0 : otsu;
    final low = (high * 0.5).clamp(1.0, high);
    final edges = cv.canny(blurred, low, high);
    scratch.add(edges);
    final kernel = cv.getStructuringElement(cv.MORPH_RECT, (3, 3));
    scratch.add(kernel);
    final closed = cv.dilate(edges, kernel);
    scratch.add(closed);
    return closed;
  }

  /// Locates the artwork window inside an already-rectified [card], returned as
  /// fractions of it, or null when nothing convincing was found.
  ///
  /// Why this exists: the bundled index hashes a fixed fractional ROI
  /// ([ArtMatchTuning.artBoxRoi]) of a clean upright card, so the runtime has to
  /// hash *that same region of the card*. Any error in the outer outline — a
  /// sleeve edge, a corner rounded off by the edge map — rescales the whole
  /// rectification, and the fixed ROI then samples the wrong pixels. The
  /// artwork is a strong rectangle in a known place, so finding it says where
  /// the card really is.
  ///
  /// **The assumption, stated plainly:** this treats [ArtMatchTuning.artBoxRoi]
  /// as the artwork window's true position on a card, so the corrected crop is
  /// the window we found. That holds to the precision of those hand-rounded
  /// fractions. The trade is favourable either way — a sleeve misrectifies by
  /// roughly 5-8%, while the ROI approximates the real art window to within a
  /// percent or two — but measuring the true rect across the cached reference
  /// images (`tools/.image_cache/full/`) and, if it differs, rebuilding the
  /// index with the measured value would remove the assumption entirely.
  ///
  /// Deliberately conservative: a candidate must land within [_artBoxSlack] of
  /// the expected box on every edge *and* match its aspect ratio. Pendulum and
  /// full-art frames have no ordinary art box and correctly fall through to
  /// null, leaving the fixed ROI in charge exactly as before.
  static Rect? _findArtBox(cv.Mat card, List<cv.Mat> scratch) {
    cv.VecVecPoint? contours;
    cv.VecVec4i? hierarchy;
    try {
      const expected = ArtMatchTuning.artBoxRoi;
      final expectedAspect =
          (expected.width * _cardW) / (expected.height * _cardH);

      final closed = _edgeMap(card, scratch);
      final found = cv.findContours(
        closed,
        cv.RETR_LIST,
        cv.CHAIN_APPROX_SIMPLE,
      );
      contours = found.$1;
      hierarchy = found.$2;

      Rect? best;
      var bestArea = 0.0;
      for (final contour in contours) {
        final box = cv.boundingRect(contour);
        final rect = Rect.fromLTWH(
          box.x / card.cols,
          box.y / card.rows,
          box.width / card.cols,
          box.height / card.rows,
        );
        if ((rect.left - expected.left).abs() > _artBoxSlack ||
            (rect.top - expected.top).abs() > _artBoxSlack ||
            (rect.right - expected.right).abs() > _artBoxSlack ||
            (rect.bottom - expected.bottom).abs() > _artBoxSlack) {
          continue;
        }
        if (rect.height <= 0) continue;
        final aspect = (rect.width * _cardW) / (rect.height * _cardH);
        final aspectError = aspect > expectedAspect
            ? aspect / expectedAspect
            : expectedAspect / aspect;
        if (aspectError > _artBoxAspectTolerance) continue;

        // Break ties on size, *not* on closeness to the expected box. Ranking
        // by closeness is circular — it prefers making no correction, which
        // discards precisely the shifted art box this pass exists to find.
        final area = rect.width * rect.height;
        if (area > bestArea) {
          bestArea = area;
          best = rect;
        }
      }
      return best;
    } catch (_) {
      // The art box is a refinement; losing it just means the fixed ROI.
      return null;
    } finally {
      contours?.dispose();
      hierarchy?.dispose();
    }
  }

  /// Approximates [contour] to a convex 4-point quad, trying progressively
  /// looser epsilons. Returns an owned [cv.VecPoint] of 4 corners (caller
  /// disposes), or null if no epsilon yields a convex quadrilateral.
  static cv.VecPoint? _approxQuad(cv.VecPoint contour) {
    final perimeter = cv.arcLength(contour, true);
    for (final epsilon in _approxEpsilons) {
      final approx = cv.approxPolyDP(contour, epsilon * perimeter, true);
      if (approx.length == 4 && cv.isContourConvex(approx)) {
        return approx;
      }
      approx.dispose();
    }
    return null;
  }

  static int? _rotateCode(int degrees) => switch (degrees) {
    90 => cv.ROTATE_90_CLOCKWISE,
    180 => cv.ROTATE_180,
    270 => cv.ROTATE_90_COUNTERCLOCKWISE,
    _ => null,
  };
}
