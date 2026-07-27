import 'package:flutter/painting.dart' show Offset, Rect;

import 'art_frame.dart';

/// A card located in a camera frame.
class DetectedCard {
  const DetectedCard({
    required this.image,
    required this.quad,
    this.artBox,
  });

  /// The card, perspective-corrected to a canonical upright rectangle
  /// (`rotationDegrees == 0`). The caller crops the art box from this.
  final ArtFrame image;

  /// Where the card was found, as [top-left, top-right, bottom-right,
  /// bottom-left] fractions (0..1) of the *upright* camera frame. Purely for
  /// drawing the detection outline over the preview — nothing in the matching
  /// path reads it.
  final List<Offset> quad;

  /// The artwork window located inside [image], as fractions of it, or null
  /// when it could not be found (full-art and Pendulum frames have no ordinary
  /// art box). Null means "fall back to `ArtMatchTuning.artBoxRoi`".
  ///
  /// This is a *correction*, not a different crop: the index hashes a fixed
  /// fractional ROI of a clean upright card, so the runtime must hash the same
  /// region. Locating the real art box is how we find that region when the
  /// outer quad landed on a sleeve edge or an inner border rather than the
  /// card's true outline — see `OpenCvCardDetector`.
  final Rect? artBox;
}

/// Finds the card in a camera frame and perspective-corrects it to a flat,
/// upright rectangle, so the artwork can be hashed from a clean, aligned crop
/// instead of a misaligned slice of the whole frame (the accuracy bug behind
/// the earlier pHash matcher).
///
/// An abstraction so the matcher can be exercised in host tests without the
/// OpenCV native library (which doesn't load off-device): tests inject a fake
/// that just orients the frame. The real, OpenCV-backed implementation lives in
/// `opencv_card_detector.dart` (the only file that imports OpenCV), keeping the
/// native dependency's blast radius to that one file.
abstract class CardDetector {
  /// Returns the card found in [frame], or null if no card-like quadrilateral
  /// was found.
  ///
  /// [searchRoi] restricts the search to a region of the upright frame, given
  /// as fractions (0..1) — candidates outside it are ignored, so the clutter of
  /// a busy desk around the card can't win. Defaults to
  /// `ArtMatchTuning.cardSearchRoi`.
  ///
  /// Asynchronous because the production implementation runs the OpenCV work on
  /// a background isolate (see `detector_isolate.dart`): edge map, contours,
  /// perspective warp and the art-box pass together cost tens of milliseconds,
  /// and on the UI isolate — every 300 ms, forever — that is enough to stop
  /// Flutter painting the camera preview, which looks to the user exactly like
  /// the camera having died.
  Future<DetectedCard?> detectCard(ArtFrame frame, {Rect? searchRoi});
}

/// A snapshot of the detector's liveness, for the scan screen's diagnostics box.
///
/// Its own readout because detection is the one stage of the pipeline that could
/// stop dead while every other on-screen signal stayed green: the camera keeps
/// delivering frames and the preview keeps painting, so a wedged detector was
/// indistinguishable from "nothing is being pointed at a card".
class DetectorHealth {
  const DetectorHealth({
    required this.inIsolate,
    required this.lastLatency,
    required this.timeouts,
  });

  /// Running on the worker isolate, rather than the in-process fallback.
  final bool inIsolate;

  /// How long the most recent detection took, or null before the first.
  final Duration? lastLatency;

  /// Detections written off after exceeding the request timeout.
  final int timeouts;
}

/// One dense line describing [health], for the diagnostics box. Pure and here
/// rather than in the widget so it can be host-tested, matching
/// `describeCameraHealth`.
///
/// Reads as `det: isolate  87ms` — where it runs and how long the last pass
/// took. `t=` is omitted while zero (the normal case) so a non-zero value stands
/// out, which is the whole reason the line exists.
String describeDetectorHealth(DetectorHealth health) {
  final latency = health.lastLatency;
  return [
    health.inIsolate ? 'isolate' : 'in-process',
    if (latency != null) '${latency.inMilliseconds}ms',
    if (health.timeouts > 0) 't=${health.timeouts}',
  ].join('  ');
}
