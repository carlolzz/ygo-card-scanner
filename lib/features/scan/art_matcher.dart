import 'package:flutter/painting.dart' show Rect;

import '../../core/theme/tokens.dart';
import '../../data/repositories/card_repository.dart';
import '../../models/ygo_card.dart';
import 'camera_service.dart';
import 'hash_index.dart';
import 'phash.dart';

/// A card proposed by the artwork-match fallback, with its Hamming distance to
/// the captured frame (smaller = closer). Presented to the user to pick from.
class ArtCandidate {
  const ArtCandidate(this.card, this.distance);
  final YgoCard card;
  final int distance;
}

/// Identifies a card by its artwork when OCR can't read the passcode. The single
/// seam the scan controller depends on — tests override its provider with a fake
/// returning canned candidates, so no camera, asset, or image math runs.
abstract class ArtMatcher {
  /// Hashes the most recent camera frame's art box and returns the nearest
  /// cards, nearest first. Empty when there is no frame yet or nothing ranks
  /// within [ArtMatchTuning.maxHammingDistance].
  Future<List<ArtCandidate>> match();
}

/// Production [ArtMatcher]: camera luma -> art-box crop -> pHash -> Hamming
/// ranking against the bundled index -> resolve passcodes to cards.
class PHashArtMatcher implements ArtMatcher {
  PHashArtMatcher({
    required this._camera,
    required this._index,
    required this._repository,
  });

  final CameraService _camera;
  final HashIndex _index;
  final CardRepository _repository;

  @override
  Future<List<ArtCandidate>> match() async {
    final frame = _camera.latestArtFrame?.oriented();
    if (frame == null) return const [];

    final crop = _cropFromRoi(ArtMatchTuning.artBoxRoi, frame.width, frame.height);
    final hash = phashFromLuma(frame.luma, frame.width, frame.height, crop: crop);

    final ranked = _index.rank(
      hash,
      n: ArtMatchTuning.candidateCount,
      maxDistance: ArtMatchTuning.maxHammingDistance,
    );

    final candidates = <ArtCandidate>[];
    for (final match in ranked) {
      final card = await _repository.getByPasscode(match.passcode);
      if (card != null) candidates.add(ArtCandidate(card, match.distance));
    }
    return candidates;
  }
}

/// Converts a normalized ROI (fractions of the upright card) to a pixel rect.
PixelRect _cropFromRoi(Rect roi, int width, int height) {
  final left = (roi.left * width).round();
  final top = (roi.top * height).round();
  final right = (roi.right * width).round();
  final bottom = (roi.bottom * height).round();
  return PixelRect(left, top, right - left, bottom - top);
}
