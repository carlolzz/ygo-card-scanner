import 'package:flutter/painting.dart' show Size;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/theme/tokens.dart';
import '../settings/settings_providers.dart';
import 'camera_service.dart';
import 'passcode_ocr.dart';

part 'scan_providers.g.dart';

/// One frame's OCR outcome. Deliberately a plain class with *identity*
/// equality (no `==` override): a fresh instance per frame means consecutive
/// identical reads (two nulls, or the same passcode twice) are never collapsed
/// by Riverpod's value-dedup, so the state machine's frame-agreement and
/// empty-frame debounce counters actually see every frame.
class PasscodeReading {
  const PasscodeReading(this.sequence, this.passcode);

  /// Monotonic frame counter, for debugging/logging only.
  final int sequence;

  /// The 8-digit passcode read this frame, or null if none was read.
  final String? passcode;
}

@riverpod
CameraService cameraService(Ref ref) {
  final service = CameraScanService();
  // `dispose`, not `stop`: this fires only when nothing scans any more (the
  // scan screen is gone), so the frame stream can be closed for good. Releasing
  // the camera on a mere background is [scanCamera]'s job, via `stop`.
  ref.onDispose(service.dispose);
  return service;
}

@riverpod
PasscodeOcr passcodeOcr(Ref ref) {
  final ocr = MlKitPasscodeOcr();
  ref.onDispose(ocr.close);
  return ocr;
}

/// Whether the camera should be running. Flipped off by the scan screen when
/// the app is backgrounded so the camera is released, and back on when it
/// returns — [scanCamera] watches this and tears the camera down/up.
@riverpod
class ScanCameraActive extends _$ScanCameraActive {
  @override
  bool build() => true;

  void set({required bool active}) => state = active;
}

/// The scan preview's viewport size, published by the screen once it has laid
/// out, so the detector can map the on-screen reticle into frame coordinates
/// and search only the guide box.
///
/// Null until the screen lays out, and again after it disposes — the detector
/// then falls back to [ArtMatchTuning.cardSearchRoi], i.e. the whole frame, so
/// every host test that never renders the screen behaves exactly as before.
///
/// `keepAlive` is load-bearing: both the writer (the screen's probe) and the
/// readers ([artReadings], [ScanController]) use `ref.read`, which holds no
/// subscription. An autoDispose provider would be torn down the instant each
/// read released it, so the size would never survive from the write to the
/// next frame and the ROI would silently stay whole-frame forever.
@Riverpod(keepAlive: true)
class ScanViewportSize extends _$ScanViewportSize {
  @override
  Size? build() => null;

  void set(Size? size) {
    if (state != size) state = size;
  }
}

/// Whether the developer diagnostics overlay is on. Derived from the persisted
/// [AppSettings.showScanDiagnostics] so the same value backs both the Settings
/// switch and the scan screen's bug-icon shortcut. Read per frame by
/// [artReadings] to decide whether to compute the unthresholded nearest hits.
@riverpod
bool scanDiagnosticsEnabled(Ref ref) =>
    ref.watch(settingsControllerProvider).value?.showScanDiagnostics ?? false;

/// Whether the "three ways to log a card" help box is shown while scanning.
/// Derived from the persisted [AppSettings.showScanHelp] the same way
/// [scanDiagnosticsEnabled] is, so the Settings switch is the single control.
/// Defaults to true so a fresh install (settings not yet resolved) still
/// explains itself.
@riverpod
bool scanHelpEnabled(Ref ref) =>
    ref.watch(settingsControllerProvider).value?.showScanHelp ?? true;

/// Whether the artwork pipeline should stand still because a result is waiting
/// on the user (a review, a candidate list, an unknown code, a camera error).
///
/// [ScanController] already ignores artwork readings in those states, but the
/// detection and hashing still ran — tens of milliseconds of work per frame, on
/// a worker isolate, for a reading that is thrown away. This lets `artReadings`
/// skip it entirely.
///
/// Its own provider rather than a read of `scanControllerProvider`: the
/// controller *listens* to `artReadings`, so reading the controller from there
/// would be a dependency cycle. Same shape and same reason as
/// [PasscodeOcrRequested].
///
/// `keepAlive` for exactly the reason [ScanViewportSize] documents, and this
/// provider was the counter-example: writer ([ScanController]) and reader
/// (`artReadings`) both use `ref.read`, which closes its subscription
/// immediately and schedules disposal, and a later `state =` does not undo
/// that. Measured before the fix — set `true`, read back one `artPollInterval`
/// later, get `false` — so the pause was inert and every review panel was
/// backed by a worker isolate still detecting and hashing. [PasscodeOcrRequested]
/// survives as plain autoDispose only because `passcodeReadings` genuinely
/// `ref.watch`es it.
///
/// **`keepAlive` means this outlives its only writer, so something has to own
/// its reset.** That half was missing and cost the app its primary feature:
/// [ScanController] is autoDispose, so leaving the scan screen with a review
/// panel open (declining a card, then backing out) left this pinned `true` for
/// the rest of the process. The camera restarted correctly on every re-entry and
/// `artReadings` skipped every frame regardless — recognition dead until the app
/// was relaunched, with every on-screen signal green.
///
/// Two things fixed it, and both are needed: the controller now releases the
/// pause in a `finally` on every resolution path, and `_ScanScreenState`
/// clears any residue from a post-frame callback when the screen opens. It is
/// cleared on **entry** rather than exit because Riverpod asserts on provider
/// writes from every widget life-cycle and from a provider's own `onDispose`,
/// so there is no legal exit-time hook — and because a fresh [ScanController]
/// always starts in `detecting`, which makes unpaused the only correct state
/// there regardless of how the last session ended.
@Riverpod(keepAlive: true)
class ScanPaused extends _$ScanPaused {
  @override
  bool build() => false;

  void set({required bool paused}) => state = paused;
}

/// Whether the user has asked for the on-demand 8-digit passcode fallback.
/// Artwork recognition is the automatic primary path; ML Kit OCR only runs
/// while this is true, so the camera doesn't burn battery reading text unless
/// asked. The controller flips it on from the "Read the code" action and off
/// again once a read resolves (or times out).
@riverpod
class PasscodeOcrRequested extends _$PasscodeOcrRequested {
  @override
  bool build() => false;

  void set({required bool requested}) => state = requested;
}

/// Single owner of the camera's start/stop lifecycle. Both reading streams
/// ([passcodeReadings] and `artReadings`) depend on this instead of starting or
/// stopping the camera themselves, so one stream disposing can never release
/// the camera out from under the other. It rebuilds — and so starts or stops
/// the camera — only when [scanCameraActive] flips.
@riverpod
Future<CameraService> scanCamera(Ref ref) async {
  final camera = ref.watch(cameraServiceProvider);
  ref.onDispose(camera.stop);
  if (ref.watch(scanCameraActiveProvider)) {
    await camera.start();
  }
  return camera;
}

/// The stream of per-frame OCR readings for the fallback. Inert (never touches
/// ML Kit) unless [passcodeOcrRequested] is true. Tests override this with a
/// fake stream to drive the OCR branch of [ScanController] without a camera.
///
/// **Self-paced**, for the same reason `artReadings` is: this used to
/// `await for` over `camera.frames` with an awaited ML Kit read in the body. A
/// broadcast controller buffers for a paused subscriber, and an `await for` is
/// paused while its body awaits — so any read slower than
/// [ScanTuning.ocrFrameInterval] (likely at 720p on mid-range hardware) grew an
/// unbounded backlog, and the agreement / empty-frame counters then ran over
/// frames from seconds ago. Polling the newest cached frame instead means a slow
/// read skips frames rather than falling behind, and comparing
/// [CameraService.frameSequence] is what stops one physical frame being read
/// twice and satisfying the agreement gate on its own.
@riverpod
Stream<PasscodeReading> passcodeReadings(Ref ref) async* {
  if (!ref.watch(passcodeOcrRequestedProvider)) return;

  final camera = await ref.watch(scanCameraProvider.future);
  final ocr = ref.watch(passcodeOcrProvider);

  // An explicit flag, not just a `yield`-point check: an iteration that
  // `continue`s never reaches the `yield` where cancellation would be observed.
  var disposed = false;
  ref.onDispose(() => disposed = true);

  var sequence = 0;
  var lastFrame = -1;
  while (!disposed) {
    await Future<void>.delayed(ScanTuning.artPollInterval);
    if (disposed) return;
    final frame = camera.frameSequence;
    if (frame == lastFrame) continue;
    final image = camera.latestInputImage;
    if (image == null) continue;
    lastFrame = frame;

    final passcode = await ocr.read(image);
    if (disposed) return;
    yield PasscodeReading(sequence++, passcode);
  }
}
