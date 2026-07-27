import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/core/constants.dart';
import 'package:ygo_scanner/core/theme/tokens.dart';
import 'package:ygo_scanner/features/scan/camera_service.dart';

/// Regression for the "must leave and re-enter Log Cards" bug: the OS
/// permission dialog backgrounds the app, which called [CameraService.stop] on
/// the shared service — and the old `stop()` permanently *closed* the frame
/// stream, so the resumed camera never emitted again. `stop()` must leave the
/// service restartable; only [CameraService.dispose] tears it down for good.
///
/// Plus the two pure pieces of the frame-stall watchdog. Everything else in the
/// service needs a camera, but these two are exactly where a mistake is
/// invisible: a wrong predicate either restarts a healthy camera on a timer or
/// never notices a dead one, and a wrong readout misleads the next bug report.
void main() {
  group('cameraFrameStalled', () {
    final past = ScanTuning.cameraFrameTimeout + const Duration(seconds: 1);

    test('a long gap while initialized is a stall', () {
      expect(
        cameraFrameStalled(sinceLastFrame: past, initialized: true),
        isTrue,
      );
    });

    test('a gap inside the timeout is not', () {
      expect(
        cameraFrameStalled(
          sinceLastFrame: ScanTuning.cameraFrameTimeout,
          initialized: true,
        ),
        isFalse,
      );
    });

    test('an uninitialized camera is never stalled, however long the gap', () {
      // It is either still opening or already released — restarting would fight
      // whatever start/stop is actually in progress.
      expect(
        cameraFrameStalled(sinceLastFrame: past, initialized: false),
        isFalse,
      );
    });
  });

  group('describeCameraHealth', () {
    test('reports opening before the stream starts', () {
      final line = describeCameraHealth(
        const CameraHealth(
          initialized: true,
          streaming: false,
          framesSeen: 0,
          sinceLastFrame: null,
          restarts: 0,
        ),
      );
      expect(line, contains(AppStrings.scanDiagnosticsCamOpening));
      expect(line, contains('f=0'));
    });

    test('reports streaming with the frame count and gap', () {
      final line = describeCameraHealth(
        const CameraHealth(
          initialized: true,
          streaming: true,
          framesSeen: 124,
          sinceLastFrame: Duration(milliseconds: 180),
          restarts: 0,
        ),
      );
      expect(line, contains(AppStrings.scanDiagnosticsCamStreaming));
      expect(line, contains('f=124'));
      expect(line, contains('180ms'));
      // Zero restarts is the normal case and stays off the line, so a non-zero
      // count stands out.
      expect(line, isNot(contains('r=')));
    });

    test('reports a stall, and surfaces the restart count', () {
      final line = describeCameraHealth(
        CameraHealth(
          initialized: true,
          streaming: true,
          framesSeen: 7,
          sinceLastFrame:
              ScanTuning.cameraFrameTimeout + const Duration(seconds: 2),
          restarts: 3,
        ),
      );
      expect(line, contains(AppStrings.scanDiagnosticsCamStalled));
      expect(line, contains('r=3'));
    });
  });

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
