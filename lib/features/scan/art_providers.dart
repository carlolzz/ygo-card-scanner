import 'dart:convert';

import 'package:flutter/painting.dart' show Offset, Rect;
import 'package:flutter/services.dart' show rootBundle;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/repositories/card_repository.dart';
import 'art_matcher.dart';
import 'card_detector.dart';
import 'hash_index.dart';
import 'opencv_card_detector.dart';
import 'scan_providers.dart';

part 'art_providers.g.dart';

/// Path to the committed perceptual-hash index asset (built by
/// `tools/build_hash_index.py`, registered under `flutter: assets:`).
const String kCardHashesAsset = 'assets/card_hashes.json';

/// Loads and parses the bundled pHash index once. Tests override this with a
/// small in-memory [HashIndex] instead of loading the real asset via
/// `rootBundle`.
@riverpod
Future<HashIndex> hashIndex(Ref ref) async {
  final raw = await rootBundle.loadString(kCardHashesAsset);
  return HashIndex.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}

/// The OpenCV-backed card detector used to flatten the card before hashing.
/// Its own provider so tests that build a real matcher could swap it, and so
/// the one OpenCV-importing class is constructed in exactly one place.
@riverpod
CardDetector cardDetector(Ref ref) => const OpenCvCardDetector();

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
/// than a passcode. Ticks off the camera's frame stream (which the service
/// already emits continuously) and hashes the cached art frame. Tests override
/// this with a fake stream to drive [ScanController] without a camera or index.
@riverpod
Stream<ArtReading> artReadings(Ref ref) async* {
  if (!ref.watch(scanCameraActiveProvider)) return;

  final camera = await ref.watch(scanCameraProvider.future);
  final matcher = await ref.watch(artMatcherProvider.future);

  var sequence = 0;
  await for (final _ in camera.frames) {
    // Skip the detect+hash work entirely while the user is in passcode-reading
    // mode: the controller ignores artwork readings there, so hashing every
    // frame would only stack onto the ML Kit OCR pass that mode runs.
    if (ref.read(passcodeOcrRequestedProvider)) continue;
    // `read`, not `watch`: reflect the current diagnostics toggle each frame
    // without making this stream depend on it (a dependency would tear down and
    // restart the whole camera subscription on every toggle).
    final diagnostics = ref.read(scanDiagnosticsEnabledProvider);
    // `read` for the same reason: a `watch` on the viewport would tear down and
    // restart the whole camera subscription on every rotation or resize.
    final result = matcher.rankFrame(
      includeNearest: diagnostics,
      viewportSize: ref.read(scanViewportSizeProvider),
    );
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
