import 'package:riverpod_annotation/riverpod_annotation.dart';

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
@riverpod
Stream<PasscodeReading> passcodeReadings(Ref ref) async* {
  if (!ref.watch(passcodeOcrRequestedProvider)) return;

  final camera = await ref.watch(scanCameraProvider.future);
  final ocr = ref.watch(passcodeOcrProvider);

  var sequence = 0;
  await for (final image in camera.frames) {
    final passcode = await ocr.read(image);
    yield PasscodeReading(sequence++, passcode);
  }
}
