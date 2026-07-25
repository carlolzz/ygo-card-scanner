/// Choosing which quadrilateral in a camera frame is the card.
///
/// Pure Dart, deliberately split out of `opencv_card_detector.dart`: that file
/// imports the OpenCV native library, which doesn't load on the host, so
/// nothing in it can ever be tested. Every *decision* therefore lives here —
/// the detector keeps only Mat lifecycle, the edge map, the contour call and
/// the warp. Getting one of these thresholds wrong doesn't crash, it silently
/// recognises the wrong card, so this is exactly the logic that needs tests.
library;

import 'dart:math' as math;

import 'package:flutter/painting.dart' show Offset, Rect, Size;

import '../../core/theme/tokens.dart';

/// Why a candidate quad was rejected, for the diagnostics overlay.
enum CardQuadRejection {
  /// Not (entirely) inside the search region.
  outsideRoi,

  /// Too small or too large a share of the search region.
  area,

  /// Not shaped like a 59:86 card.
  aspect,

  /// Four corners that don't describe a rectangle.
  rectangularity,

  /// One side wildly longer than the one opposite it.
  sideBalance,

  /// Rotated too far in-plane for corner ordering to be trustworthy.
  tilt,

  /// Passed every gate but scored below [CardDetectionTuning.minScore].
  score,
}

/// A quad that passed the shape gate, with the metrics behind its score.
class CardQuadCandidate {
  const CardQuadCandidate({
    required this.corners,
    required this.area,
    required this.aspectError,
    required this.rectangularity,
    required this.tiltDegrees,
    required this.score,
  });

  /// [top-left, top-right, bottom-right, bottom-left], in image pixels.
  final List<Offset> corners;
  final double area;

  /// Ratio of this quad's aspect to a card's, folded to >= 1.
  final double aspectError;
  final double rectangularity;
  final double tiltDegrees;

  /// 0..1, higher is more card-like. Every term is bounded, so shape genuinely
  /// competes with size — an earlier version multiplied by raw pixel area,
  /// which made it "largest wins" with a shape prefilter.
  final double score;
}

/// Orders four corners into [top-left, top-right, bottom-right, bottom-left]
/// using the coordinate sum (TL smallest, BR largest) and difference (TR
/// largest x-y, BL smallest). Only trustworthy for modest in-plane rotation —
/// see [CardDetectionTuning.maxTiltDegrees].
List<Offset> orderQuadCorners(List<Offset> corners) {
  Offset byMin(double Function(Offset) key) =>
      corners.reduce((a, b) => key(a) <= key(b) ? a : b);
  Offset byMax(double Function(Offset) key) =>
      corners.reduce((a, b) => key(a) >= key(b) ? a : b);
  return [
    byMin((p) => p.dx + p.dy),
    byMax((p) => p.dx - p.dy),
    byMax((p) => p.dx + p.dy),
    byMin((p) => p.dx - p.dy),
  ];
}

/// Shoelace area of an ordered quad.
double quadArea(List<Offset> quad) {
  var sum = 0.0;
  for (var i = 0; i < 4; i++) {
    final a = quad[i];
    final b = quad[(i + 1) % 4];
    sum += a.dx * b.dy - b.dx * a.dy;
  }
  return sum.abs() / 2;
}

/// Mean width / mean height of an ordered quad.
double quadAspect(List<Offset> quad) {
  final height = _meanHeight(quad);
  if (height <= 0) return double.infinity;
  return _meanWidth(quad) / height;
}

/// Area / (mean width x mean height): 1 for a parallelogram, less for a shape
/// whose corners don't describe one.
double quadRectangularity(List<Offset> quad) {
  final box = _meanWidth(quad) * _meanHeight(quad);
  if (box <= 0) return 0;
  return quadArea(quad) / box;
}

/// Product of the two opposite-side length ratios, each folded to <= 1.
double quadSideBalance(List<Offset> quad) {
  final top = (quad[1] - quad[0]).distance;
  final right = (quad[2] - quad[1]).distance;
  final bottom = (quad[2] - quad[3]).distance;
  final left = (quad[3] - quad[0]).distance;
  if (top <= 0 || right <= 0 || bottom <= 0 || left <= 0) return 0;
  return (math.min(top, bottom) / math.max(top, bottom)) *
      (math.min(left, right) / math.max(left, right));
}

/// In-plane rotation of the quad's top edge, in degrees, folded to [0, 90).
double quadTiltDegrees(List<Offset> quad) {
  final edge = quad[1] - quad[0];
  if (edge.dx == 0 && edge.dy == 0) return 0;
  final degrees = math.atan2(edge.dy, edge.dx) * 180 / math.pi;
  return (degrees.abs() % 180).clamp(0, 180) > 90
      ? 180 - (degrees.abs() % 180)
      : degrees.abs() % 180;
}

Offset quadCentroid(List<Offset> quad) {
  var x = 0.0;
  var y = 0.0;
  for (final corner in quad) {
    x += corner.dx;
    y += corner.dy;
  }
  return Offset(x / quad.length, y / quad.length);
}

/// Whether every corner of [inner] lies within the convex quad [outer].
bool quadContains(List<Offset> outer, List<Offset> inner) {
  for (final point in inner) {
    if (!_containsPoint(outer, point)) return false;
  }
  return true;
}

/// Gates and scores one ordered quad. Returns null when it isn't card-like,
/// reporting the failed gate through [onReject].
CardQuadCandidate? evaluateCardQuad(
  List<Offset> corners, {
  required Size imageSize,
  required Rect searchRoi,
  void Function(CardQuadRejection)? onReject,
}) {
  CardQuadCandidate? reject(CardQuadRejection reason) {
    onReject?.call(reason);
    return null;
  }

  const slack = CardDetectionTuning.searchRoiSlack;
  final left = (searchRoi.left - slack) * imageSize.width;
  final right = (searchRoi.right + slack) * imageSize.width;
  final top = (searchRoi.top - slack) * imageSize.height;
  final bottom = (searchRoi.bottom + slack) * imageSize.height;
  for (final corner in corners) {
    if (corner.dx < left ||
        corner.dx > right ||
        corner.dy < top ||
        corner.dy > bottom) {
      return reject(CardQuadRejection.outsideRoi);
    }
  }

  final roiArea =
      searchRoi.width * imageSize.width * searchRoi.height * imageSize.height;
  if (roiArea <= 0) return reject(CardQuadRejection.area);
  final area = quadArea(corners);
  final areaFraction = area / roiArea;
  if (areaFraction < CardDetectionTuning.minRoiAreaFraction ||
      areaFraction > CardDetectionTuning.maxRoiAreaFraction) {
    return reject(CardQuadRejection.area);
  }

  final aspect = quadAspect(corners);
  if (!aspect.isFinite || aspect <= 0) return reject(CardQuadRejection.aspect);
  const ideal = ScanReticleTokens.cardAspectRatio;
  final aspectError = aspect > ideal ? aspect / ideal : ideal / aspect;
  if (aspectError > CardDetectionTuning.aspectTolerance) {
    return reject(CardQuadRejection.aspect);
  }

  final rectangularity = quadRectangularity(corners);
  if (rectangularity < CardDetectionTuning.minRectangularity) {
    return reject(CardQuadRejection.rectangularity);
  }

  if (quadSideBalance(corners) < CardDetectionTuning.minSideBalance) {
    return reject(CardQuadRejection.sideBalance);
  }

  final tilt = quadTiltDegrees(corners);
  if (tilt > CardDetectionTuning.maxTiltDegrees) {
    return reject(CardQuadRejection.tilt);
  }

  final aspectScore = _unit(
    1 -
        (aspectError - 1) /
            (CardDetectionTuning.aspectTolerance - 1),
  );
  final rectScore = _unit(
    (rectangularity - CardDetectionTuning.minRectangularity) /
        (1 - CardDetectionTuning.minRectangularity),
  );
  final fillScore = _unit(
    areaFraction / CardDetectionTuning.targetRoiAreaFraction,
  );
  final roiCentre = Offset(
    searchRoi.center.dx * imageSize.width,
    searchRoi.center.dy * imageSize.height,
  );
  final roiDiagonal = math.sqrt(
    math.pow(searchRoi.width * imageSize.width, 2) +
        math.pow(searchRoi.height * imageSize.height, 2),
  );
  final centreScore = roiDiagonal <= 0
      ? 0.0
      : _unit(1 - 2 * (quadCentroid(corners) - roiCentre).distance / roiDiagonal);

  final score =
      CardDetectionTuning.aspectWeight * aspectScore +
      CardDetectionTuning.rectangularityWeight * rectScore +
      CardDetectionTuning.fillWeight * fillScore +
      CardDetectionTuning.centreWeight * centreScore;
  if (score < CardDetectionTuning.minScore) {
    return reject(CardQuadRejection.score);
  }

  return CardQuadCandidate(
    corners: corners,
    area: area,
    aspectError: aspectError,
    rectangularity: rectangularity,
    tiltDegrees: tilt,
    score: score,
  );
}

/// Gates every quad, then picks the winner: highest score, then **one** step
/// inward if a qualifying quad is nested inside it.
///
/// The inward step is the sleeved-card fix. A sleeve shows its own outline
/// concentric with, and a few percent larger than, the card's; taking the
/// larger one shifts every subsequent crop. Exactly one step is allowed —
/// see [CardDetectionTuning.maxNestedDescents].
CardQuadCandidate? selectCardQuad(
  Iterable<List<Offset>> quads, {
  required Size imageSize,
  required Rect searchRoi,
  void Function(CardQuadRejection)? onReject,
}) {
  final candidates = <CardQuadCandidate>[];
  for (final quad in quads) {
    final candidate = evaluateCardQuad(
      quad,
      imageSize: imageSize,
      searchRoi: searchRoi,
      onReject: onReject,
    );
    if (candidate != null) candidates.add(candidate);
  }
  if (candidates.isEmpty) return null;

  final distinct = _collapseDuplicates(candidates, imageSize);
  var best = distinct.reduce((a, b) => a.score >= b.score ? a : b);

  for (var step = 0; step < CardDetectionTuning.maxNestedDescents; step++) {
    CardQuadCandidate? inner;
    for (final candidate in distinct) {
      if (identical(candidate, best)) continue;
      if (candidate.area >= best.area) continue;
      if (candidate.area <
          best.area * CardDetectionTuning.innerQuadMinAreaRatio) {
        continue;
      }
      if (!quadContains(best.corners, candidate.corners)) continue;
      // Take the innermost qualifying quad in this one pass.
      if (inner == null || candidate.area < inner.area) inner = candidate;
    }
    if (inner == null) break;
    best = inner;
  }
  return best;
}

/// Collapses the two sides of one dilated edge band into a single candidate,
/// keeping the outer. Without this a duplicate pair would consume the single
/// permitted nested descent before the sleeve rule ever got to run.
List<CardQuadCandidate> _collapseDuplicates(
  List<CardQuadCandidate> candidates,
  Size imageSize,
) {
  final sorted = [...candidates]..sort((a, b) => b.area.compareTo(a.area));
  final diagonal = math.sqrt(
    imageSize.width * imageSize.width + imageSize.height * imageSize.height,
  );
  final maxCentreGap = diagonal * CardDetectionTuning.duplicateCentreFraction;
  final kept = <CardQuadCandidate>[];
  for (final candidate in sorted) {
    final duplicate = kept.any((other) {
      if (other.area <= 0) return false;
      final ratio = candidate.area / other.area;
      if (ratio < CardDetectionTuning.duplicateAreaRatio) return false;
      return (quadCentroid(other.corners) - quadCentroid(candidate.corners))
              .distance <=
          maxCentreGap;
    });
    if (!duplicate) kept.add(candidate);
  }
  return kept;
}

double _meanWidth(List<Offset> quad) =>
    ((quad[1] - quad[0]).distance + (quad[2] - quad[3]).distance) / 2;

double _meanHeight(List<Offset> quad) =>
    ((quad[3] - quad[0]).distance + (quad[2] - quad[1]).distance) / 2;

double _unit(double value) => value.clamp(0.0, 1.0);

/// Point-in-convex-quad by consistent cross-product sign around the edges.
bool _containsPoint(List<Offset> quad, Offset point) {
  var positive = false;
  var negative = false;
  for (var i = 0; i < 4; i++) {
    final a = quad[i];
    final b = quad[(i + 1) % 4];
    final cross =
        (b.dx - a.dx) * (point.dy - a.dy) - (b.dy - a.dy) * (point.dx - a.dx);
    if (cross > 0) positive = true;
    if (cross < 0) negative = true;
    if (positive && negative) return false;
  }
  return true;
}
