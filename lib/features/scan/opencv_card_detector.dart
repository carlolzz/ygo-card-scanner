import 'dart:typed_data';

import 'package:opencv_core/opencv.dart' as cv;

import 'art_frame.dart';
import 'card_detector.dart';

/// Production [CardDetector] backed by OpenCV: grayscale edges → largest convex
/// quadrilateral → perspective warp to a canonical upright card. This is the
/// only file in the app that imports OpenCV; everything else depends on the
/// [CardDetector] interface, so host tests never touch the native library.
class OpenCvCardDetector implements CardDetector {
  const OpenCvCardDetector();

  /// The canonical warped card size (59:86, scaled). Only the ratio matters —
  /// the art box is resized to 32x32 for hashing afterwards.
  static const int _cardW = 421;
  static const int _cardH = 614;

  /// Longest edge the detection runs at. Downscaling keeps the per-frame cost
  /// low; the warp reads from this same downscaled image, which is plenty of
  /// detail for a 32x32 hash.
  static const int _workLongEdge = 480;

  /// A candidate must cover at least this fraction of the (downscaled) frame to
  /// count as the card — rejects small background rectangles.
  static const double _minAreaFraction = 0.15;

  /// …and at most this much, so a near-full-frame rectangle (a wall behind the
  /// card, or the image border itself) is never mistaken for the card.
  static const double _maxAreaFraction = 0.98;

  /// approxPolyDP epsilons (as a fraction of the contour perimeter) tried in
  /// order. A single tight value rejects cards whose corners the edge map
  /// rounded off (sleeves, soft focus); trying looser ones recovers them.
  static const List<double> _approxEpsilons = [0.02, 0.03, 0.05];

  @override
  ArtFrame? detectCard(ArtFrame frame) {
    if (frame.luma.length != frame.width * frame.height) return null;
    final scratch = <cv.Mat>[];
    cv.VecVecPoint? contours;
    cv.VecVec4i? hierarchy;
    cv.VecPoint? bestQuad;
    cv.VecPoint? src;
    cv.VecPoint? dst;
    try {
      // Grayscale Mat from the luma plane, then rotate upright.
      var gray =
          cv.Mat.fromList(frame.height, frame.width, cv.MatType.CV_8UC1, frame.luma);
      scratch.add(gray);
      final rotateCode = _rotateCode(frame.rotationDegrees);
      if (rotateCode != null) {
        gray = cv.rotate(gray, rotateCode);
        scratch.add(gray);
      }

      // Downscale for speed; the warp reads from this same image.
      var work = gray;
      final longEdge = gray.cols > gray.rows ? gray.cols : gray.rows;
      if (longEdge > _workLongEdge) {
        final scale = _workLongEdge / longEdge;
        work = cv.resize(
          gray,
          ((gray.cols * scale).round(), (gray.rows * scale).round()),
        );
        scratch.add(work);
      }

      // Edge map: blur → Canny → dilate to close gaps in the card border.
      // Canny thresholds are derived from Otsu rather than fixed, so the edge
      // map adapts to the frame's exposure instead of washing out (bright) or
      // vanishing (dim) under a one-size threshold.
      final blurred = cv.gaussianBlur(work, (5, 5), 0);
      scratch.add(blurred);
      final (otsu, otsuMask) =
          cv.threshold(blurred, 0, 255, cv.THRESH_BINARY | cv.THRESH_OTSU);
      scratch.add(otsuMask);
      final high = otsu <= 0 ? 150.0 : otsu;
      final low = (high * 0.5).clamp(1.0, high);
      final edges = cv.canny(blurred, low, high);
      scratch.add(edges);
      final kernel = cv.getStructuringElement(cv.MORPH_RECT, (3, 3));
      scratch.add(kernel);
      final closed = cv.dilate(edges, kernel);
      scratch.add(closed);

      final found =
          cv.findContours(closed, cv.RETR_LIST, cv.CHAIN_APPROX_SIMPLE);
      contours = found.$1;
      hierarchy = found.$2;
      final frameArea = work.rows * work.cols;
      final minArea = frameArea * _minAreaFraction;
      final maxArea = frameArea * _maxAreaFraction;

      // First choice: the largest convex 4-point contour within the area band.
      // Fallback: the largest in-band contour's bounding box, so a card whose
      // outline never approximated to a clean quad still gets warped instead of
      // dropped (an axis-aligned box, so no perspective correction — good
      // enough when the user has framed the card roughly square to the reticle).
      var bestArea = 0.0;
      cv.VecPoint? largestContour;
      var largestArea = 0.0;
      for (final contour in contours) {
        final area = cv.contourArea(contour);
        if (area < minArea || area > maxArea) continue;
        if (area > largestArea) {
          largestArea = area;
          largestContour = contour; // owned by `contours`; never disposed here
        }
        final quad = _approxQuad(contour);
        if (quad == null) continue;
        if (area > bestArea) {
          bestQuad?.dispose();
          bestQuad = quad;
          bestArea = area;
        } else {
          quad.dispose();
        }
      }

      final cv.VecPoint? corners = bestQuad ??
          (largestContour == null ? null : _boundingQuad(largestContour));
      if (corners == null) return null;
      if (!identical(corners, bestQuad)) {
        // The bounding-box fallback allocated a new vec; track it for disposal.
        bestQuad = corners;
      }

      // Warp the ordered corners onto a canonical upright card.
      src = cv.VecPoint.fromList(_orderedCorners(corners));
      dst = cv.VecPoint.fromList([
        cv.Point(0, 0),
        cv.Point(_cardW, 0),
        cv.Point(_cardW, _cardH),
        cv.Point(0, _cardH),
      ]);
      final transform = cv.getPerspectiveTransform(src, dst);
      scratch.add(transform);
      final warped = cv.warpPerspective(work, transform, (_cardW, _cardH));
      scratch.add(warped);

      // Copy the pixels out before the native Mats are freed.
      final luma = Uint8List.fromList(warped.data);
      return ArtFrame(
        luma: luma,
        width: warped.cols,
        height: warped.rows,
        rotationDegrees: 0,
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
      bestQuad?.dispose();
      src?.dispose();
      dst?.dispose();
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

  /// The axis-aligned bounding box of [contour] as an ordered 4-point vec — the
  /// fallback when no clean quad was found. Owned by the caller.
  static cv.VecPoint _boundingQuad(cv.VecPoint contour) {
    final r = cv.boundingRect(contour);
    return cv.VecPoint.fromList([
      cv.Point(r.x, r.y),
      cv.Point(r.x + r.width, r.y),
      cv.Point(r.x + r.width, r.y + r.height),
      cv.Point(r.x, r.y + r.height),
    ]);
  }

  /// Orders a 4-point quad into [top-left, top-right, bottom-right, bottom-left]
  /// using the coordinate sum (TL smallest, BR largest) and difference
  /// (TR largest x-y, BL smallest).
  static List<cv.Point> _orderedCorners(cv.VecPoint quad) {
    final points = [for (var i = 0; i < quad.length; i++) quad[i]];
    cv.Point byMin(int Function(cv.Point) key) =>
        points.reduce((a, b) => key(a) <= key(b) ? a : b);
    cv.Point byMax(int Function(cv.Point) key) =>
        points.reduce((a, b) => key(a) >= key(b) ? a : b);
    final tl = byMin((p) => p.x + p.y);
    final br = byMax((p) => p.x + p.y);
    final tr = byMax((p) => p.x - p.y);
    final bl = byMin((p) => p.x - p.y);
    return [tl, tr, br, bl];
  }

  static int? _rotateCode(int degrees) => switch (degrees) {
        90 => cv.ROTATE_90_CLOCKWISE,
        180 => cv.ROTATE_180,
        270 => cv.ROTATE_90_COUNTERCLOCKWISE,
        _ => null,
      };
}
