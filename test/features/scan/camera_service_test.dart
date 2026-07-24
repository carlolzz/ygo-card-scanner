import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/features/scan/camera_service.dart';

/// Regression for the "must leave and re-enter Log Cards" bug: the OS
/// permission dialog backgrounds the app, which called [CameraService.stop] on
/// the shared service — and the old `stop()` permanently *closed* the frame
/// stream, so the resumed camera never emitted again. `stop()` must leave the
/// service restartable; only [CameraService.dispose] tears it down for good.
void main() {
  test('stop() keeps the frame stream open so the service can restart', () async {
    final service = CameraScanService();

    var doneAfterStop = false;
    final sub = service.frames.listen((_) {}, onDone: () => doneAfterStop = true);

    // stop() before any start() is a valid no-op; the point is it must not
    // close the stream.
    await service.stop();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(
      doneAfterStop,
      isFalse,
      reason: 'stop() must not close the frame stream — the service has to '
          'survive a stop()/start() cycle (backgrounding, the permission dialog).',
    );
    await sub.cancel();

    // dispose() is the terminal teardown: now the stream closes for good.
    var doneAfterDispose = false;
    service.frames.listen((_) {}, onDone: () => doneAfterDispose = true);
    await service.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(doneAfterDispose, isTrue);
  });
}
