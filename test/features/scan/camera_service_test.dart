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

  // The watchdog's whole decision, and the half of it that used to be missing.
  // A `_start` that throws has its error swallowed by the service's serialising
  // queue — nothing retries it and nothing surfaces an error — and while the
  // watchdog was armed by the *tail* of a successful `_start`, a throw meant no
  // watchdog existed at all. The camera stayed black and silent for the rest of
  // the process with every on-screen signal green, which is the "camera freezes
  // and goes black for unknown reasons" report.
  group('cameraNeedsRestart', () {
    final past = ScanTuning.cameraFrameTimeout + const Duration(seconds: 1);

    test('wanting a camera with no controller is a failed start', () {
      expect(
        cameraNeedsRestart(
          wantRunning: true,
          startInFlight: false,
          hasController: false,
          sinceLastFrame: null,
          initialized: false,
        ),
        isTrue,
      );
    });

    test('a start still in flight is left alone', () {
      // Opening a camera takes far longer than one watchdog interval, so
      // without this every start would be aborted by a restart of itself on the
      // very next tick.
      expect(
        cameraNeedsRestart(
          wantRunning: true,
          startInFlight: true,
          hasController: false,
          sinceLastFrame: null,
          initialized: false,
        ),
        isFalse,
      );
    });

    test('a camera the app asked to release is never restarted', () {
      // The other bug this flag fixes: a watchdog restart landing after a
      // lifecycle stop used to reopen the camera while the app was backgrounded.
      expect(
        cameraNeedsRestart(
          wantRunning: false,
          startInFlight: false,
          hasController: false,
          sinceLastFrame: past,
          initialized: true,
        ),
        isFalse,
      );
    });

    test('a stalled stream still restarts', () {
      expect(
        cameraNeedsRestart(
          wantRunning: true,
          startInFlight: false,
          hasController: true,
          sinceLastFrame: past,
          initialized: true,
        ),
        isTrue,
      );
    });

    test('a healthy camera is left alone', () {
      expect(
        cameraNeedsRestart(
          wantRunning: true,
          startInFlight: false,
          hasController: true,
          sinceLastFrame: const Duration(milliseconds: 180),
          initialized: true,
        ),
        isFalse,
      );
    });

    test('a controller that has not streamed yet is opening, not stalled', () {
      expect(
        cameraNeedsRestart(
          wantRunning: true,
          startInFlight: false,
          hasController: true,
          sinceLastFrame: null,
          initialized: true,
        ),
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
      // count stands out. Same for dropped frames.
      expect(line, isNot(contains('r=')));
      expect(line, isNot(contains('x=')));
    });

    // The failure this field exists for is otherwise invisible: a frame layout
    // the conversion never accepts leaves the camera healthy by every other
    // measure — streaming, frames rising, gap small — while nothing is ever
    // recognised, and the watchdog cannot help because frames genuinely are
    // arriving.
    test('surfaces frames that failed to convert', () {
      final line = describeCameraHealth(
        const CameraHealth(
          initialized: true,
          streaming: true,
          framesSeen: 90,
          sinceLastFrame: Duration(milliseconds: 160),
          restarts: 0,
          droppedFrames: 90,
        ),
      );
      expect(line, contains(AppStrings.scanDiagnosticsCamStreaming));
      expect(line, contains('x=90'));
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
    final sub = service.frames.listen(
      (_) {},
      onDone: () => doneAfterStop = true,
    );

    // stop() before any start() is a valid no-op; the point is it must not
    // close the stream.
    await service.stop();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(
      doneAfterStop,
      isFalse,
      reason:
          'stop() must not close the frame stream — the service has to '
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
