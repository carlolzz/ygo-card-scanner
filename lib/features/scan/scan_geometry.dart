/// Geometry shared by the scan preview and anything drawn over it.
///
/// The preview is a `BoxFit.cover` of the camera frame (see `_FullBleedPreview`
/// in `scan_screen.dart`): the frame is scaled up until it fills the viewport on
/// both axes, so one axis overflows and is clipped, and what the user sees is a
/// centred *sub-rectangle* of the sensor frame. Anything positioned from frame
/// coordinates — the detection outline — has to repeat that transform exactly,
/// or it lands next to the card instead of on it.
///
/// Pure and host-testable on purpose: this is the one piece of the overlay that
/// can be got wrong silently, since a misplaced outline still looks plausible.
library;

import 'package:flutter/painting.dart' show Offset, Rect, Size;

import '../../core/theme/tokens.dart';

/// The scale `BoxFit.cover` applies when fitting [frame] into [viewport].
/// Only the *aspect* of [frame] matters, so callers may pass any size with the
/// right shape.
double previewCoverScale(Size frame, Size viewport) {
  if (frame.width <= 0 || frame.height <= 0) return 1;
  final scaleX = viewport.width / frame.width;
  final scaleY = viewport.height / frame.height;
  return scaleX > scaleY ? scaleX : scaleY;
}

/// Maps a point expressed as fractions (0..1) of the upright camera frame to a
/// point in viewport coordinates, matching how the preview is displayed.
///
/// Points on the clipped axis can legitimately fall outside the viewport — a
/// card corner just off the visible edge — so the result is not clamped.
Offset frameFractionToViewport(
  Offset fraction,
  Size frame,
  Size viewport,
) {
  final scale = previewCoverScale(frame, viewport);
  final displayedWidth = frame.width * scale;
  final displayedHeight = frame.height * scale;
  final originX = (viewport.width - displayedWidth) / 2;
  final originY = (viewport.height - displayedHeight) / 2;
  return Offset(
    originX + fraction.dx * displayedWidth,
    originY + fraction.dy * displayedHeight,
  );
}

/// Inverse of [frameFractionToViewport]: a viewport point as fractions of the
/// upright frame. Not clamped — a point outside the preview maps outside 0..1.
Offset viewportToFrameFraction(Offset point, Size frame, Size viewport) {
  final scale = previewCoverScale(frame, viewport);
  final displayedWidth = frame.width * scale;
  final displayedHeight = frame.height * scale;
  if (displayedWidth <= 0 || displayedHeight <= 0) return Offset.zero;
  final originX = (viewport.width - displayedWidth) / 2;
  final originY = (viewport.height - displayedHeight) / 2;
  return Offset(
    (point.dx - originX) / displayedWidth,
    (point.dy - originY) / displayedHeight,
  );
}

/// The reticle guide box, in viewport coordinates.
///
/// The single source of truth for the guide's geometry: `_ReticleOverlay` draws
/// this rect and the detector searches it, so the box the user is asked to fill
/// and the box actually searched can never drift apart. That is also why the
/// vertical offset lives here rather than in the painting code — moving the box
/// moves the searched region and the diagnostics search-ROI outline with it, by
/// construction.
///
/// The box sits [ScanReticleTokens.verticalOffsetFraction] below the viewport's
/// centre, to leave a readable band between the app bar and the guide. The
/// offset is **clamped against the detection margin, not the box**:
/// [detectionRoiInFrame] inflates this rect by
/// [ScanDetectionTokens.reticleRoiMargin] on every side before mapping it into
/// frame space, where it is clamped to `[0, 1]` — so an offset that pushed the
/// *inflated* rect off the bottom would silently truncate the searched region
/// on one edge only, with no visible symptom beyond worse recognition.
Rect reticleRectInViewport(Size viewport) {
  var width = viewport.width * ScanReticleTokens.widthFraction;
  var height = width / ScanReticleTokens.cardAspectRatio;
  final maxHeight = viewport.height * ScanReticleTokens.maxHeightFraction;
  if (height > maxHeight) {
    height = maxHeight;
    width = height * ScanReticleTokens.cardAspectRatio;
  }
  final slack =
      (viewport.height - height) / 2 - height * ScanDetectionTokens.reticleRoiMargin;
  final offset = slack <= 0
      ? 0.0
      : (viewport.height * ScanReticleTokens.verticalOffsetFraction)
            .clamp(0.0, slack);
  return Rect.fromCenter(
    center: Offset(viewport.width / 2, viewport.height / 2 + offset),
    width: width,
    height: height,
  );
}

/// The region of the *upright* camera frame the detector should search, as
/// fractions (0..1), given the on-screen reticle and the preview's
/// `BoxFit.cover` crop.
///
/// This mapping is the whole point of the file, and it is not the identity: the
/// preview shows a **centred sub-rectangle** of the sensor frame, so the
/// reticle's on-screen fractions are *not* its frame fractions. On a 1080x2340
/// viewport against a 4:3 sensor the guide box covers 78% of the screen's width
/// but only about 48% of the frame's — using the on-screen fractions directly
/// would search a region 60% too wide, which is exactly the kind of error that
/// produces no visible symptom beyond "recognition is unreliable".
///
/// Falls back to [ArtMatchTuning.cardSearchRoi] — the previous whole-frame-ish
/// behaviour — when either size is degenerate, e.g. before the screen has laid
/// out.
Rect detectionRoiInFrame({
  required Size viewport,
  required Size frame,
  double margin = ScanDetectionTokens.reticleRoiMargin,
}) {
  if (viewport.width <= 0 ||
      viewport.height <= 0 ||
      frame.width <= 0 ||
      frame.height <= 0) {
    return ArtMatchTuning.cardSearchRoi;
  }
  final reticle = reticleRectInViewport(viewport);
  final topLeft = viewportToFrameFraction(reticle.topLeft, frame, viewport);
  final bottomRight = viewportToFrameFraction(
    reticle.bottomRight,
    frame,
    viewport,
  );
  final roi = Rect.fromLTRB(
    topLeft.dx,
    topLeft.dy,
    bottomRight.dx,
    bottomRight.dy,
  );
  // The reticle is a guide, not a wall: a card held slightly large must still
  // be found rather than silently dropped for overhanging the box.
  return Rect.fromLTRB(
    (roi.left - roi.width * margin).clamp(0.0, 1.0),
    (roi.top - roi.height * margin).clamp(0.0, 1.0),
    (roi.right + roi.width * margin).clamp(0.0, 1.0),
    (roi.bottom + roi.height * margin).clamp(0.0, 1.0),
  );
}
