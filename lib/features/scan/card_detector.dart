import 'art_frame.dart';

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
  /// Returns an upright, perspective-corrected grayscale image of the whole
  /// card (rotation applied, `rotationDegrees == 0`), or null if no card-like
  /// quadrilateral was found. The caller crops the art box from the result.
  ArtFrame? detectCard(ArtFrame frame);
}
