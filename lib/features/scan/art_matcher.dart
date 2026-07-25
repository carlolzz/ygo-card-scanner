import 'package:flutter/painting.dart' show Offset, Rect, Size;

import '../../core/theme/tokens.dart';
import '../../data/repositories/card_repository.dart';
import '../../models/ygo_card.dart';
import 'camera_service.dart';
import 'card_detector.dart';
import 'hash_index.dart';
import 'phash.dart';
import 'scan_geometry.dart';

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
    this.quad,
    this.artBox,
  });

  final ArtFrameStatus status;
  final List<HashMatch> matches;
  final List<HashMatch> nearest;

  /// Where the card was found, as fractions of the upright frame — for the
  /// on-screen detection outline only. Null when nothing was detected.
  final List<Offset>? quad;

  /// The artwork window located inside the rectified card, as fractions of it,
  /// or null when the fixed [ArtMatchTuning.artBoxRoi] was used instead. Drives
  /// both the overlay (which must outline the region actually hashed, not a
  /// nominal one) and the diagnostics readout, since "was the crop corrected?"
  /// is the first thing worth knowing when a real card ranks far away.
  final Rect? artBox;

  bool get artBoxLocked => artBox != null;

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
  ///
  /// [viewportSize] is the scan preview's size, used to map the on-screen guide
  /// box into frame coordinates so only that region is searched. Null (no
  /// screen laid out, e.g. every host test) searches the whole frame, which is
  /// the behaviour this had before the guide box was honoured.
  ArtFrameResult rankFrame({bool includeNearest = false, Size? viewportSize});

  /// The last [rankFrame]'s in-threshold matches resolved to cards (a DB read
  /// per hit, skipping passcodes absent from the local `cards` table — e.g.
  /// alt-arts the app DB doesn't store). Nearest first. Called once, when a
  /// match is presented.
  Future<List<ArtCandidate>> match({Size? viewportSize});
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

  /// The most recent [rankFrame] result, so [match] resolves the very frame the
  /// controller's agreement gate fired on instead of re-detecting a fresh one —
  /// otherwise the review panel could present a different card than the outline
  /// was sitting on.
  ArtFrameResult? _lastResult;

  @override
  ArtFrameResult rankFrame({bool includeNearest = false, Size? viewportSize}) {
    final result = _rank(includeNearest: includeNearest, viewportSize: viewportSize);
    _lastResult = result;
    return result;
  }

  ArtFrameResult _rank({required bool includeNearest, Size? viewportSize}) {
    final raw = _camera.latestArtFrame;
    if (raw == null) return ArtFrameResult.noFrame;

    // Search only the on-screen guide box. The preview is a `BoxFit.cover` crop
    // of the sensor frame, so the reticle's screen fractions are not its frame
    // fractions — `detectionRoiInFrame` does that conversion. Without a laid-out
    // screen (host tests) this stays the whole frame.
    final upright = raw.rotationDegrees == 90 || raw.rotationDegrees == 270
        ? Size(raw.height.toDouble(), raw.width.toDouble())
        : Size(raw.width.toDouble(), raw.height.toDouble());
    final searchRoi = viewportSize == null
        ? ArtMatchTuning.cardSearchRoi
        : detectionRoiInFrame(viewport: viewportSize, frame: upright);

    // Detect and flatten the card first, so the art box is hashed from a clean,
    // aligned crop. No card in frame -> no candidate (better a miss than a
    // garbage match on background pixels).
    final card = _detector.detectCard(raw, searchRoi: searchRoi);
    if (card == null) return ArtFrameResult.notDetected;

    // The artwork window the detector located, when it found one: the index
    // hashes a fixed fractional ROI of a clean card, and a located art box is
    // where that ROI actually landed on the card we captured. Falls back to the
    // fixed fractions when the detector couldn't find it (full-art frames).
    final image = card.image;
    final roi = card.artBox ?? ArtMatchTuning.artBoxRoi;
    final crop = _cropFromRoi(roi, image.width, image.height);
    final hash = phashFromLuma(image.luma, image.width, image.height, crop: crop);

    final matches = _index.rank(
      hash,
      n: ArtMatchTuning.candidateCount,
      maxDistance: ArtMatchTuning.maxHammingDistance,
    );
    // The unthresholded nearest, for the overlay only, so a "detected but far"
    // frame still shows how far the real card sits (past the match gate).
    final nearest = includeNearest
        ? _index.rank(hash, n: 3, maxDistance: 64)
        : const <HashMatch>[];
    return ArtFrameResult(
      ArtFrameStatus.detected,
      matches,
      nearest: nearest,
      quad: card.quad,
      artBox: card.artBox,
    );
  }

  @override
  Future<List<ArtCandidate>> match({Size? viewportSize}) async {
    // Resolve the frame that was just ranked. Re-ranking here would hash a
    // *newer* frame than the one the agreement gate accepted, so the card the
    // user is shown could differ from the one the outline locked onto.
    final result =
        _lastResult ?? rankFrame(viewportSize: viewportSize);
    final candidates = <ArtCandidate>[];
    for (final match in result.matches) {
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
