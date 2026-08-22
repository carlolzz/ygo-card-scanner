// `widgets`, not the narrower `painting` this used to take `Size` from:
// [ScanCameraActive] now owns an `AppLifecycleListener`.
import 'package:flutter/widgets.dart'
    show AppLifecycleListener, AppLifecycleState, Size;
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

/// The camera, pinned for the life of the process while [keepCameraReady] is on.
///
/// **The two halves of the user's "Keep the camera ready" switch.**
///
/// *Pinned* (the default): the camera opens on the first Log Cards entry of an
/// app run and stays open until the app is backgrounded ([ScanCameraActive] owns
/// that signal). This is the fix for "the camera reloads every time I go back to
/// Log Cards" — see the unpinned case for what that reload actually was. The
/// cost is a bound camera, and a lit privacy indicator, while browsing the
/// collection afterwards; [CameraService.frameProcessingEnabled] is what keeps
/// that to an idle preview rather than a running recognition pipeline.
///
/// *Unpinned*: leaving the screen is a full teardown again, and every link in
/// the chain is load-bearing. `ScanScreen` unmounts → [ScanController] disposes →
/// `artReadings` disposes → [scanCamera] disposes → its `onDispose(camera.stop)`
/// fires → this provider loses its last listener → `service.dispose()` sets
/// `_disposed` **permanently**. Re-entry cannot reuse that instance and must
/// build a new one, paying `initialize()` plus eight metering round-trips and a
/// `startImageStream` — a visible second or two of black. That the *provider*
/// disposes alongside the service is what makes the fresh instance automatic.
///
/// `dispose`, not `stop`, on teardown, in both cases: releasing the camera on a
/// mere background is [scanCamera]'s job, via `stop`. Reaching here means the
/// service is finished with, so the frame stream can be closed for good.
@riverpod
CameraService cameraService(Ref ref) {
  final service = CameraScanService();
  ref.onDispose(service.dispose);
  _pinWhileCameraKeptReady(ref);
  return service;
}

/// Pins the calling provider for the life of the process while the user's
/// "keep the camera ready" setting is on, and releases it the moment they turn
/// it off. The per-value form of `@Riverpod(keepAlive: true)`, which the
/// annotation itself cannot express.
///
/// `ref.read` for the decision, never `ref.watch`: watching would *rebuild* the
/// camera on a toggle, and a rebuild of [cameraService] replaces the
/// `CameraScanService` while [scanCamera] reopens the camera behind it. The user
/// is sitting in Settings at that moment, so a camera opening there is the exact
/// thing the switch exists to prevent. The listener therefore only ever
/// **closes** the link; turning the setting back on takes effect at the next
/// build, i.e. the next Log Cards entry, which is soon enough for a preference
/// about how that entry feels.
///
/// Only closing also keeps `ref.keepAlive()` out of a listener callback, where
/// `Ref` asserts it is being used inside a life-cycle. `KeepAliveLink.close`
/// touches no `Ref` and a second close is a no-op, so registering it on
/// `onDispose` as well is safe, and closing the last link only *schedules*
/// disposal rather than reentering it here.
void _pinWhileCameraKeptReady(Ref ref) {
  if (!ref.read(keepCameraReadyProvider)) return;
  final link = ref.keepAlive();
  ref.onDispose(link.close);
  ref.listen(keepCameraReadyProvider, (_, keep) {
    if (!keep) link.close();
  });
}

@riverpod
PasscodeOcr passcodeOcr(Ref ref) {
  final ocr = MlKitPasscodeOcr();
  ref.onDispose(ocr.close);
  return ocr;
}

/// Whether the camera should be running: true while the app is in the
/// foreground, false once it is genuinely backgrounded. [scanCamera] watches
/// this and tears the camera down/up.
///
/// **It owns the lifecycle listener itself, and that is load-bearing.** This
/// signal used to come from a [WidgetsBindingObserver] on `_ScanScreenState`,
/// which only exists while the scan screen is mounted. That was fine while the
/// camera died with the screen; now that it outlives the screen, there would be
/// nothing left to release it on background — the camera would stay bound while
/// the app sat in the recents list. The provider that *means* "the camera should
/// be running" owning the signal that decides it is the smallest correct home,
/// and it keeps `App` stateless.
///
/// `keepAlive` unconditionally, unlike [cameraService], which the user's "keep
/// the camera ready" setting only pins: this is one bool and one lifecycle
/// listener, so there is nothing to release. An autoDispose notifier would be
/// torn down between scan sessions, taking the listener with it and resetting
/// the state — and it is read with `ref.read` from a callback, which holds no
/// subscription of its own.
///
/// `inactive` deliberately keeps the camera: on first launch the OS
/// camera-permission dialog briefly makes the app inactive, and releasing there
/// (then restarting on resume) is exactly the churn that used to leave the
/// preview dead until the screen was re-entered.
@Riverpod(keepAlive: true)
class ScanCameraActive extends _$ScanCameraActive {
  @override
  bool build() {
    final listener = AppLifecycleListener(onStateChange: _onLifecycleState);
    ref.onDispose(listener.dispose);
    return true;
  }

  void _onLifecycleState(AppLifecycleState lifecycle) {
    switch (lifecycle) {
      case AppLifecycleState.resumed:
      case AppLifecycleState.inactive:
        set(active: true);
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        set(active: false);
    }
  }

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

/// Whether the camera is held open after the scan screen goes away. Derived
/// from the persisted [AppSettings.keepCameraReady] the same way
/// [scanHelpEnabled] is, and consumed only by [_pinWhileCameraKeptReady] —
/// which reads it once per build and then listens only for it going off. See
/// [cameraService] for what each half actually does.
///
/// Defaults to true so a fresh install (settings not yet resolved) behaves as
/// it did before this was a choice.
@riverpod
bool keepCameraReady(Ref ref) =>
    ref.watch(settingsControllerProvider).value?.keepCameraReady ?? true;

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
///
/// Pinned by [keepCameraReady] alongside [cameraService], and both halves are
/// needed: a pinned service reached through an unpinned gate would still be
/// stopped the moment the scan screen's readers went away, and re-entry would
/// still pay `initialize()`. Nothing reads this before the first Log Cards
/// entry, so the camera is not opened at launch — only kept once opened.
@riverpod
Future<CameraService> scanCamera(Ref ref) async {
  final camera = ref.watch(cameraServiceProvider);
  ref.onDispose(camera.stop);
  _pinWhileCameraKeptReady(ref);
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
