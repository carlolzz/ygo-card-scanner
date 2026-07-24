import 'package:flutter/painting.dart' show Rect;

import '../../core/theme/tokens.dart';
import '../../data/repositories/card_repository.dart';
import '../../models/ygo_card.dart';
import 'camera_service.dart';
import 'card_detector.dart';
import 'hash_index.dart';
import 'phash.dart';

/// A card proposed by the artwork-match fallback, with its Hamming distance to
/// the captured frame (smaller = closer). Presented to the user to pick from.
class ArtCandidate {
  const ArtCandidate(this.card, this.distance);
  final YgoCard card;
  final int distance;
}

/// What happened when a frame was ranked — surfaced to the diagnostics overlay
/// so a failure can be diagnosed as *detection* (`noFrame`/`notDetected`) vs
/// *matching* (`detected` but distances large).
enum ArtFrameStatus {
  /// The camera hasn't delivered a frame yet.
  noFrame,

  /// A frame arrived but no card quad was found in it (detection failure).
  notDetected,

  /// A card was detected and hashed; [ArtFrameResult.matches] holds the ranked
  /// in-threshold hits (possibly empty when the nearest are still too far).
  detected,
}

/// One frame's ranking outcome: the detection [status], the in-threshold
/// [matches] that drive the controller, and — only when diagnostics ask for it
/// — the unthresholded [nearest] few for on-screen display.
class ArtFrameResult {
  const ArtFrameResult(
    this.status,
    this.matches, {
    this.nearest = const [],
  });

  final ArtFrameStatus status;
  final List<HashMatch> matches;
  final List<HashMatch> nearest;

  static const ArtFrameResult noFrame =
      ArtFrameResult(ArtFrameStatus.noFrame, []);
  static const ArtFrameResult notDetected =
      ArtFrameResult(ArtFrameStatus.notDetected, []);
}

/// Identifies a card by its artwork — the automatic primary path, and the seam
/// the scan controller depends on. Tests override its provider with a fake, so
/// no camera, asset, or image math runs.
abstract class ArtMatcher {
  /// Detects/flattens the card in the most recent camera frame, hashes its art
  /// box, and ranks it against the index — pure and DB-free, cheap enough to run
  /// on every frame. The result carries the detection [ArtFrameResult.status]
  /// and the in-threshold hits (nearest first, within
  /// [ArtMatchTuning.maxHammingDistance]); the controller uses only the top hit.
  ///
  /// [includeNearest] additionally computes the unthresholded nearest few for
  /// the diagnostics overlay — left off on the normal path so a second ranking
  /// pass runs only while the developer overlay is on.
  ArtFrameResult rankFrame({bool includeNearest = false});

  /// [rankFrame]'s in-threshold matches resolved to cards (a DB read per hit,
  /// skipping passcodes absent from the local `cards` table — e.g. alt-arts the
  /// app DB doesn't store). Nearest first. Called once, when a match is
  /// presented.
  Future<List<ArtCandidate>> match();
}

/// Production [ArtMatcher]: camera luma -> art-box crop -> pHash -> Hamming
/// ranking against the bundled index -> resolve passcodes to cards.
class PHashArtMatcher implements ArtMatcher {
  PHashArtMatcher({
    required this._camera,
    required this._index,
    required this._repository,
    required this._detector,
  });

  final CameraService _camera;
  final HashIndex _index;
  final CardRepository _repository;
  final CardDetector _detector;

  @override
  ArtFrameResult rankFrame({bool includeNearest = false}) {
    final raw = _camera.latestArtFrame;
    if (raw == null) return ArtFrameResult.noFrame;

    // Detect and flatten the card first, so the art box is hashed from a clean,
    // aligned crop. No card in frame -> no candidate (better a miss than a
    // garbage match on background pixels).
    final card = _detector.detectCard(raw);
    if (card == null) return ArtFrameResult.notDetected;

    final crop = _cropFromRoi(ArtMatchTuning.artBoxRoi, card.width, card.height);
    final hash = phashFromLuma(card.luma, card.width, card.height, crop: crop);

    final matches = _index.rank(
      hash,
      n: ArtMatchTuning.candidateCount,
      maxDistance: ArtMatchTuning.maxHammingDistance,
    );
    // The unthresholded nearest, for the overlay only, so a "detected but far"
    // frame still shows how far the real card sits (past the match gate).
    final nearest =
        includeNearest ? _index.rank(hash, n: 3, maxDistance: 64) : const <HashMatch>[];
    return ArtFrameResult(ArtFrameStatus.detected, matches, nearest: nearest);
  }

  @override
  Future<List<ArtCandidate>> match() async {
    final candidates = <ArtCandidate>[];
    for (final match in rankFrame().matches) {
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
