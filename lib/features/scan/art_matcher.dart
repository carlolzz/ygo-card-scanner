import 'package:flutter/painting.dart' show Offset, Rect, Size;

import '../../core/theme/tokens.dart';
import '../../data/repositories/card_repository.dart';
import '../../models/ygo_card.dart';
import 'art_frame.dart';
import 'camera_service.dart';
import 'card_detector.dart';
import 'frame_quality.dart';
import 'hash_index.dart';
import 'phash.dart';
import 'scan_geometry.dart';
import 'scan_sample.dart';

/// A card proposed by the artwork-match fallback, with its Hamming distance to
/// the captured frame (smaller = closer). Presented to the user to pick from.
class ArtCandidate {
  const ArtCandidate(this.card, this.distance, {this.rankedPasscode});

  final YgoCard card;
  final int distance;

  /// The index key this candidate was ranked under, when it differs from the
  /// card's own. Null when the caller didn't record one (fakes in tests).
  final String? rankedPasscode;

  /// The index key this candidate was ranked under. Usually equal to
  /// `card.passcode`, but *not* for an alt-art: the index keys every
  /// `card_images[i].id` while the `cards` table stores only `card_images[0]`,
  /// so a match on an alt-art hash resolves to a card with a *different*
  /// passcode. The scan controller debounces on this, since it is what the next
  /// frame's reading will carry. See `ScanState.matchedIndexPasscode`.
  String get indexPasscode => rankedPasscode ?? card.passcode;
}

/// What happened when a frame was ranked — surfaced to the diagnostics overlay
/// so a failure can be diagnosed as *detection* (`noFrame`/`notDetected`),
/// *optics* (`lowQuality`) or *matching* (`detected` but distances large).
enum ArtFrameStatus {
  /// The camera hasn't delivered a frame yet.
  noFrame,

  /// A frame arrived but no card quad was found in it (detection failure).
  notDetected,

  /// A card was found and rectified, but its artwork crop was too blurred or too
  /// glare-blown to be worth hashing — see [FrameQuality]. Distinct from
  /// [detected] because the pipeline's response differs: this frame is *skipped*
  /// (it neither confirms nor contradicts the run in progress), and the user is
  /// told what to change rather than that no card is visible.
  lowQuality,

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
    this.quality,
  });

  final ArtFrameStatus status;
  final List<HashMatch> matches;
  final List<HashMatch> nearest;

  /// How usable this frame's artwork crop was, or null when no crop was assessed
  /// (no frame at all, or no card found).
  ///
  /// Nullable rather than defaulted because [noFrame] and [notDetected] are
  /// `const` statics: a non-nullable field would force them to become factories,
  /// and "not assessed" is genuinely different from "assessed as fine".
  final FrameQuality? quality;

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
  Future<ArtFrameResult> rankFrame({
    bool includeNearest = false,
    Size? viewportSize,
  });

  /// The last [rankFrame]'s in-threshold matches resolved to cards (one batched
  /// DB read, skipping passcodes absent from the local `cards` table — e.g.
  /// alt-arts the app DB doesn't store). Nearest first. Called once, when a
  /// match is presented.
  Future<List<ArtCandidate>> match({Size? viewportSize});

  /// The pixels the last [rankFrame] actually hashed, for the diagnostics-only
  /// sample capture, or null when nothing has been ranked (which is what the
  /// test fakes return — only the production matcher retains a frame, and only
  /// while the developer overlay is on).
  ArtSample? get lastSample;
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

  /// The last ranked frame's pixels, retained **only while diagnostics is on**
  /// (`rankFrame(includeNearest: …)` carries that flag already). A rectified
  /// card is ~260 KB and nothing on the normal path reads it, so keeping one
  /// unconditionally would be a permanent cost for a developer feature.
  ArtSample? _lastSample;

  @override
  ArtSample? get lastSample => _lastSample;

  @override
  Future<ArtFrameResult> rankFrame({
    bool includeNearest = false,
    Size? viewportSize,
  }) async {
    _lastSample = null;
    final result = await _rank(
      includeNearest: includeNearest,
      viewportSize: viewportSize,
      retainSample: includeNearest,
    );
    _lastResult = result;
    return result;
  }

  Future<ArtFrameResult> _rank({
    required bool includeNearest,
    Size? viewportSize,
    bool retainSample = false,
  }) async {
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
    var card = await _detector.detectCard(raw, searchRoi: searchRoi);
    // Nothing in the guide box: try the whole frame once before giving up.
    //
    // The reticle-to-frame mapping is the one thing in this pipeline that can be
    // wrong with no visible symptom, and if it is wrong on some device then
    // detection would never work there at all. This retry turns that cliff into
    // a slower path, and it costs nothing on frames that already succeed —
    // a failing frame is exactly when there is budget to spare.
    if (card == null && searchRoi != ArtMatchTuning.cardSearchRoi) {
      card = await _detector.detectCard(
        raw,
        searchRoi: ArtMatchTuning.cardSearchRoi,
      );
    }
    if (card == null) return ArtFrameResult.notDetected;

    // The artwork window the detector located, when it found one: the index
    // hashes a fixed fractional ROI of a clean card, and a located art box is
    // where that ROI actually landed on the card we captured. Falls back to the
    // fixed fractions when the detector couldn't find it (full-art frames).
    final image = card.image;
    final roi = card.artBox ?? ArtMatchTuning.artBoxRoi;
    final crop = _cropFromRoi(roi, image.width, image.height);

    // Judge the exact pixels about to be hashed, *before* hashing them. A
    // smeared or glare-blown crop produces a descriptor genuinely far from the
    // indexed one, and every stage downstream would report that identically to
    // "there is no card here" — which is what put the scan screen in a silent
    // loop telling the user to point at a card already centred in the reticle.
    //
    // Checking first rather than after ranking is deliberate: it skips the DCT
    // and the index scan on a frame whose answer would not be trusted anyway, so
    // the gate costs less than it saves. The trade is that we never learn
    // whether a rejected frame *would* have matched — acceptable, because the
    // next good frame arrives in `artFrameInterval` and a wrong answer accepted
    // from a bad frame is far more expensive than a skipped one.
    final quality = assessCrop(image.luma, image.width, image.height, crop);
    if (!quality.isUsable) {
      // Retained too: a rejected frame is exactly the kind of sample worth
      // capturing, since the gate's thresholds are the thing least verified
      // against real cards.
      if (retainSample) {
        _lastSample = buildArtSample(
          luma: image.luma,
          width: image.width,
          height: image.height,
          crop: crop,
          quality: quality,
          artBoxLocked: card.artBox != null,
          matches: const [],
        );
      }
      return ArtFrameResult(
        ArtFrameStatus.lowQuality,
        const [],
        quad: card.quad,
        artBox: card.artBox,
        quality: quality,
      );
    }

    var hash = phashFromLuma(image.luma, image.width, image.height, crop: crop);

    var matches = _index.rank(
      hash,
      n: ArtMatchTuning.candidateCount,
      maxDistance: ArtMatchTuning.maxHammingDistance,
    );
    // Nothing in range: the card may simply be upside-down. `quadTiltDegrees`
    // folds tilt into [0, 90), so a card held at 180° reads as tilt 0 and passes
    // every shape gate — it is warped inverted and hashes to noise, with no
    // symptom beyond "it won't recognise this one". Re-hash the rotated crop
    // and keep whichever ranks. Gated on the first pass having failed, so the
    // common case pays nothing.
    if (matches.isEmpty) {
      final flipped = phashFromLuma(
        rotate180(image.luma, image.width, image.height),
        image.width,
        image.height,
        crop: crop,
      );
      final flippedMatches = _index.rank(
        flipped,
        n: ArtMatchTuning.candidateCount,
        maxDistance: ArtMatchTuning.maxHammingDistance,
      );
      if (flippedMatches.isNotEmpty) {
        hash = flipped;
        matches = flippedMatches;
      }
    }
    // The unthresholded nearest, for the overlay only, so a "detected but far"
    // frame still shows how far the real card sits (past the match gate).
    final nearest = includeNearest
        ? _index.rank(hash, n: ArtMatchTuning.diagnosticsNearestCount)
        : const <HashMatch>[];
    if (retainSample) {
      _lastSample = buildArtSample(
        luma: image.luma,
        width: image.width,
        height: image.height,
        crop: crop,
        quality: quality,
        artBoxLocked: card.artBox != null,
        // The unthresholded nearest when we have them: a sample is only worth
        // studying alongside what the index actually said about it, and the
        // in-gate `matches` list is empty in precisely the failing case.
        matches: nearest.isNotEmpty ? nearest : matches,
      );
    }
    return ArtFrameResult(
      ArtFrameStatus.detected,
      matches,
      nearest: nearest,
      quad: card.quad,
      artBox: card.artBox,
      quality: quality,
    );
  }

  @override
  Future<List<ArtCandidate>> match({Size? viewportSize}) async {
    // Resolve the frame that was just ranked. Re-ranking here would hash a
    // *newer* frame than the one the agreement gate accepted, so the card the
    // user is shown could differ from the one the outline locked onto.
    final result =
        _lastResult ?? await rankFrame(viewportSize: viewportSize);
    if (result.matches.isEmpty) return const [];

    // One query, not one per candidate. This sits *after* the agreement gate, so
    // every round trip through the sqflite isolate is latency the user waits
    // through before the review panel can appear.
    final cards = await _repository.getByPasscodes([
      for (final match in result.matches) match.passcode,
    ]);
    final byPasscode = {for (final card in cards) card.passcode: card};

    // Walk the matches, not the rows: the query returns them in rowid order, and
    // nearest-first is the whole point of a ranked list.
    final candidates = <ArtCandidate>[];
    for (final match in result.matches) {
      // Absent from `cards` — an alt-art the app DB doesn't store. The query
      // filtered on these very keys, so a miss here is exactly the null that
      // `getByPasscode` used to return, and skipping it is load-bearing.
      final card = byPasscode[match.passcode];
      if (card == null) continue;
      candidates.add(
        // Carry the index key alongside the card: they differ for alt-arts,
        // and the controller's debounce is keyed on the index side.
        ArtCandidate(card, match.distance, rankedPasscode: match.passcode),
      );
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
