import 'package:riverpod_annotation/riverpod_annotation.dart';

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
  ref.onDispose(service.stop);
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
/// returns — [passcodeReadings] watches this and tears the camera down/up.
@riverpod
class ScanCameraActive extends _$ScanCameraActive {
  @override
  bool build() => true;

  void set({required bool active}) => state = active;
}

/// The live stream of per-frame OCR readings. Tests override this with a fake
/// stream to drive [ScanController] without a camera or ML Kit.
@riverpod
Stream<PasscodeReading> passcodeReadings(Ref ref) async* {
  if (!ref.watch(scanCameraActiveProvider)) return;

  final camera = ref.watch(cameraServiceProvider);
  final ocr = ref.watch(passcodeOcrProvider);
  ref.onDispose(camera.stop);

  await camera.start();

  var sequence = 0;
  await for (final image in camera.frames) {
    final passcode = await ocr.read(image);
    yield PasscodeReading(sequence++, passcode);
  }
}
