import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/core/theme/tokens.dart';
import 'package:ygo_scanner/features/scan/art_providers.dart';
import 'package:ygo_scanner/features/scan/hash_index.dart';
import 'package:ygo_scanner/features/scan/scan_providers.dart';

/// The scan pipeline's two expensive one-time setups must outlive the screen
/// that uses them.
///
/// This guards a property that is invisible everywhere else: as `autoDispose`
/// providers, both were torn down whenever the scan screen was popped **and**
/// whenever the app was merely backgrounded (`artReadings` returns early when
/// `scanCameraActive` flips, releasing its watch on `artMatcher` and so on
/// these). The next entry or resume then re-read 540 KB of asset, span a fresh
/// isolate, re-decoded ~14 400 hashes and copied them back — the receiving half
/// of that copy landing on the UI isolate, concurrently with
/// `CameraController.initialize()`. Nothing failed; the camera just took about a
/// second longer to appear every time, which is exactly the kind of regression
/// that gets reintroduced by someone tidying `@Riverpod(keepAlive: true)` back
/// to `@riverpod`.
void main() {
  test('the parsed hash index survives its last listener going away', () async {
    final container = ProviderContainer(
      overrides: [
        hashIndexProvider.overrideWith(
          (ref) async => HashIndex(
            version: 3,
            algorithm: 'phash',
            hashSize: HashIndex.kExpectedHashSize,
            hashes: const {},
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final subscription =
        container.listen(hashIndexProvider, (previous, next) {});
    await container.read(hashIndexProvider.future);
    subscription.close();
    // Let a turn pass — an autoDispose provider is collected once nothing
    // holds it, not synchronously at the moment the subscription closes.
    await Future<void>.delayed(Duration.zero);

    expect(
      container.exists(hashIndexProvider),
      isTrue,
      reason:
          'hashIndexProvider must be keepAlive. As autoDispose it is dropped '
          'on leaving the scan screen and on backgrounding the app, so the '
          '540 KB index is re-read and re-parsed on every re-entry and every '
          'resume — on the UI isolate, while the camera is initialising.',
    );
  });

  test('the card detector survives its last listener going away', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Constructing it is free — `IsolateCardDetector` spawns its worker lazily,
    // on the first detection — so simply reading the provider does no work.
    final subscription =
        container.listen(cardDetectorProvider, (previous, next) {});
    final detector = container.read(cardDetectorProvider);
    subscription.close();
    await Future<void>.delayed(Duration.zero);

    expect(container.exists(cardDetectorProvider), isTrue);
    expect(
      container.read(cardDetectorProvider),
      same(detector),
      reason:
          'The worker isolate is deliberately long-lived (see '
          'IsolateCardDetector); that only holds if the provider owning it is '
          'too, or every scan-screen entry pays an Isolate.spawn and handshake.',
    );
  });

  test('the scan-paused flag survives being written and read back', () async {
    // The same trap as above, but this one had actually sprung: nothing watches
    // `scanPaused` — the controller writes it and `artReadings` reads it, both
    // with `ref.read`, which closes its subscription in a `finally` and so
    // schedules disposal. A later `state =` does not undo that. As autoDispose
    // the write below reads back `false`, and the "stop detecting and hashing
    // while a result waits on the user" optimisation was silently inert.
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(scanPausedProvider.notifier).set(paused: true);
    // One poll interval, the gap the reader actually sees.
    await Future<void>.delayed(ScanTuning.artPollInterval);

    expect(
      container.read(scanPausedProvider),
      isTrue,
      reason:
          'ScanPaused must be keepAlive. Written and read only through '
          'ref.read, an autoDispose notifier is disposed between the write and '
          'the next frame, so the pause never reaches artReadings and the '
          'worker isolate keeps detecting behind every review panel.',
    );
  });
}
