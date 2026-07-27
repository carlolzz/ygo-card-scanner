import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/features/scan/card_detector.dart';

/// The diagnostics line for detection liveness.
///
/// Worth a test for the same reason `describeCameraHealth` has one: this line
/// exists to be believed when a user reports what the overlay said. Detection is
/// the one stage that could stop dead while every other on-screen signal stayed
/// green — the camera keeps delivering frames and the preview keeps painting, so
/// a wedged worker isolate looked exactly like "no card in view".
void main() {
  group('describeDetectorHealth', () {
    test('names where detection runs', () {
      expect(
        describeDetectorHealth(
          const DetectorHealth(
            inIsolate: true,
            lastLatency: null,
            timeouts: 0,
          ),
        ),
        'isolate',
      );
      expect(
        describeDetectorHealth(
          const DetectorHealth(
            inIsolate: false,
            lastLatency: null,
            timeouts: 0,
          ),
        ),
        'in-process',
      );
    });

    test('reports the last pass latency once there is one', () {
      expect(
        describeDetectorHealth(
          const DetectorHealth(
            inIsolate: true,
            lastLatency: Duration(milliseconds: 87),
            timeouts: 0,
          ),
        ),
        'isolate  87ms',
      );
    });

    test('shows timeouts only when non-zero, so they stand out', () {
      const healthy = DetectorHealth(
        inIsolate: true,
        lastLatency: Duration(milliseconds: 20),
        timeouts: 0,
      );
      expect(describeDetectorHealth(healthy), isNot(contains('t=')));
      expect(
        describeDetectorHealth(
          const DetectorHealth(
            inIsolate: false,
            lastLatency: Duration(milliseconds: 20),
            timeouts: 4,
          ),
        ),
        contains('t=4'),
      );
    });
  });
}
