import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/painting.dart' show Offset, Rect;
import 'package:flutter/services.dart' show rootBundle;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/theme/tokens.dart';
import '../../data/repositories/card_repository.dart';
import 'art_matcher.dart';
import 'card_detector.dart';
import 'detector_isolate.dart';
import 'hash_index.dart';
import 'scan_providers.dart';

part 'art_providers.g.dart';

/// Path to the committed perceptual-hash index asset (built by
/// `tools/build_hash_index.py`, registered under `flutter: assets:`).
const String kCardHashesAsset = 'assets/card_hashes.json';

/// Loads and parses the bundled pHash index once. Tests override this with a
/// small in-memory [HashIndex] instead of loading the real asset via
/// `rootBundle`.
///
/// The decode and parse run via [compute], off the UI isolate: this is ~14 400
/// entries of JSON, and it used to land at exactly the wrong moment — the scan
/// screen opening, while the camera is initialising — where a few hundred
/// milliseconds of blocked UI isolate shows up as a preview that is slow to
/// appear or stays black. [HashIndex] holds only strings and plain
/// `PerceptualHash` objects, so it copies back across the port, and the ROI
/// mismatch [FormatException] still propagates.
///
/// **`keepAlive` is the point.** Offloading the parse was only half the fix
/// while the provider was autoDispose: leaving the scan screen dropped the
/// parsed index, and so did merely backgrounding the app (`artReadings` returns
/// early when `scanCameraActive` flips, releasing its watch on
/// `artMatcher` → this). Every re-entry and every resume then re-read 540 KB of
/// asset, spawned a fresh isolate, re-decoded ~14 400 entries and copied the
/// whole map back — and the *receiving* end of that copy runs on the UI isolate,
/// concurrently with `CameraController.initialize()`. Parsed once per app run it
/// costs a couple of MB of resident memory, which is the right trade for an app
/// whose main screen is the scanner.
///
/// One consequence worth stating: a [FormatException] from the ROI header check
/// is now cached for the app's lifetime rather than retried per visit. That is
/// fine — the failure means the committed index and [ArtMatchTuning.artBoxRoi]
/// disagree, which is a property of the build, identical on every attempt.
@Riverpod(keepAlive: true)
Future<HashIndex> hashIndex(Ref ref) async {
  final raw = await rootBundle.load(kCardHashesAsset);
  return compute(_parseHashIndex, raw.buffer.asUint8List());
}

HashIndex _parseHashIndex(Uint8List bytes) => HashIndex.fromJson(
  jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
);

/// The card detector used to flatten the card before hashing: the OpenCV
/// pipeline, run on a worker isolate (see [IsolateCardDetector] for why).
///
/// Its own provider so tests that build a real matcher can swap it, and so the
/// detector is constructed in exactly one place.
///
/// `keepAlive` for the same reason as [hashIndex], and with the same shape of
/// waste: autoDispose killed the worker on every exit from the scan screen and
/// on every background, so the next visit paid an `Isolate.spawn` plus the
/// handshake again — [IsolateCardDetector]'s own doc explains why the worker is
/// long-lived, and that reasoning only holds if the provider holding it is too.
/// The construction itself stays free (the spawn is lazy, on first detection),
/// so nothing happens until something actually detects.
@Riverpod(keepAlive: true)
CardDetector cardDetector(Ref ref) {
  final detector = IsolateCardDetector();
  ref.onDispose(detector.dispose);
  return detector;
}

/// The artwork matcher the scan controller invokes. Composes the live camera,
/// the card detector, the parsed index, and the card repository. Tests override
/// this provider with a fake returning canned candidates.
@riverpod
Future<ArtMatcher> artMatcher(Ref ref) async {
  final index = await ref.watch(hashIndexProvider.future);
  final repository = await ref.watch(cardRepositoryProvider.future);
  final camera = ref.watch(cameraServiceProvider);
  final detector = ref.watch(cardDetectorProvider);
  return PHashArtMatcher(
    camera: camera,
    index: index,
    repository: repository,
    detector: detector,
  );
}

/// One frame's artwork-match outcome: the nearest indexed card and its Hamming
/// distance, or null when nothing ranked within the loose gate.
///
/// A plain identity-equality class, for the same reason [PasscodeReading] is:
/// Riverpod value-dedup must not collapse consecutive identical top matches, or
/// the controller's frame-agreement counter would miss frames.
class ArtReading {
  const ArtReading(
    this.sequence,
    this.top, {
    this.status = ArtFrameStatus.noFrame,
    this.nearest = const [],
    this.quad,
    this.artBox,
  });

  /// Monotonic frame counter, for debugging/logging only.
  final int sequence;

  /// The nearest indexed card this frame, or null if nothing ranked close.
  final HashMatch? top;

  /// Detection outcome for this frame, for the diagnostics overlay.
  final ArtFrameStatus status;

  /// The unthresholded nearest few hits, populated only while diagnostics is on
  /// (see [artReadings]); empty otherwise.
  final List<HashMatch> nearest;

  /// The detected card's corners as fractions of the upright frame, for the
  /// on-screen outline. Null when nothing was detected this frame.
  final List<Offset>? quad;

  /// The artwork window located inside the card, as fractions of it, or null
  /// when the fixed ROI was used. The overlay outlines this, so what the user
  /// sees highlighted is the region actually being hashed.
  final Rect? artBox;

  bool get artBoxLocked => artBox != null;
}

/// The automatic primary path: per-frame artwork ranking. Drives the same
/// N-agreement machine the OCR path uses, but on the top artwork hit rather
/// than a passcode. Tests override this with a fake stream to drive
/// [ScanController] without a camera or index.
///
/// **Self-paced, by polling [CameraService.frameSequence] rather than
/// subscribing to `camera.frames`.** Ranking is now asynchronous (detection runs
/// on a worker isolate), and a broadcast `StreamController` *buffers* for a
/// paused subscriber — so an `await for` whose body outran
/// [ScanTuning.frameInterval] would grow an unbounded backlog and the outline
/// would drift further behind reality the longer scanning went on. Polling
/// always works on the newest cached frame, so the loop naturally paces itself
/// at `max(frameInterval, detection time)` and can never fall behind. Comparing
/// the sequence is what stops the same physical frame being ranked twice, which
/// would otherwise let one frame satisfy [ScanTuning.artAgreementFrames] on its
/// own.
@riverpod
Stream<ArtReading> artReadings(Ref ref) async* {
  if (!ref.watch(scanCameraActiveProvider)) return;

  final camera = await ref.watch(scanCameraProvider.future);
  final matcher = await ref.watch(artMatcherProvider.future);

  // An iteration that `continue`s never reaches a `yield`, which is where
  // cancellation would otherwise be observed — so the loop has to be told.
  var disposed = false;
  ref.onDispose(() => disposed = true);

  var sequence = 0;
  var lastFrame = -1;
  while (!disposed) {
    await Future<void>.delayed(ScanTuning.artPollInterval);
    if (disposed) return;
    // Skip the detect+hash work entirely while the user is in passcode-reading
    // mode: the controller ignores artwork readings there, so ranking every
    // frame would only stack onto the ML Kit OCR pass that mode runs.
    if (ref.read(passcodeOcrRequestedProvider)) continue;
    // Likewise while a result is waiting on the user — the controller would
    // discard the reading anyway.
    if (ref.read(scanPausedProvider)) continue;
    // No new frame from the camera since the last pass.
    final frame = camera.frameSequence;
    if (frame == lastFrame) continue;
    lastFrame = frame;

    // `read`, not `watch`, for both of these: a dependency would tear down and
    // restart this whole stream on every diagnostics toggle or resize.
    final diagnostics = ref.read(scanDiagnosticsEnabledProvider);
    final result = await matcher.rankFrame(
      includeNearest: diagnostics,
      viewportSize: ref.read(scanViewportSizeProvider),
    );
    if (disposed) return;
    yield ArtReading(
      sequence++,
      result.matches.isEmpty ? null : result.matches.first,
      status: result.status,
      nearest: result.nearest,
      quad: result.quad,
      artBox: result.artBox,
    );
  }
}
