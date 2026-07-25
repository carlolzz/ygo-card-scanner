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
  DetectedCard? detectCard(ArtFrame frame, {Rect? searchRoi});
}
