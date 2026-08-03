import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ygo_scanner/core/constants.dart';
import 'package:ygo_scanner/core/router.dart';
import 'package:ygo_scanner/core/theme/tokens.dart';
import 'package:ygo_scanner/data/db/dao/collection_dao.dart';
import 'package:ygo_scanner/data/db/database.dart';
import 'package:ygo_scanner/data/seed/fake_collection_seed.dart';
import 'package:ygo_scanner/features/scan/art_frame.dart';
import 'package:ygo_scanner/features/scan/art_matcher.dart';
import 'package:ygo_scanner/features/scan/art_providers.dart';
import 'package:ygo_scanner/features/scan/camera_service.dart';
import 'package:ygo_scanner/features/scan/hash_index.dart';
import 'package:ygo_scanner/features/scan/scan_geometry.dart';
import 'package:ygo_scanner/features/scan/scan_providers.dart';
import 'package:ygo_scanner/features/scan/scan_sample.dart';
import 'package:ygo_scanner/features/scan/scan_screen.dart';
import 'package:ygo_scanner/features/settings/settings_providers.dart';
import 'package:ygo_scanner/models/card_condition.dart';
import 'package:ygo_scanner/models/ygo_card.dart';

import '../../data/db/test_db.dart';
import '../../support/widget_test_harness.dart';

const _darkMagician = '46986414';
const _dmCard = YgoCard(
  passcode: _darkMagician,
  name: 'Dark Magician',
  type: 'Normal Monster',
);

/// Resolves the agreed artwork run to a fixed candidate — no camera or index.
class _FakeArtMatcher implements ArtMatcher {
  _FakeArtMatcher(this.result);
  final List<ArtCandidate> result;
  @override
  Future<List<ArtCandidate>> match({Size? viewportSize}) async => result;
  @override
  Future<List<ArtCandidate>> bestGuesses() async => result;
  @override
  Future<ArtFrameResult> rankFrame({
    bool includeNearest = false,
    Size? viewportSize,
  }) async => const ArtFrameResult(ArtFrameStatus.notDetected, []);
  @override
  ArtSample? get lastSample => null;
}

void main() {
  late Database testDb;

  setUp(() async {
    testDb = await openInMemoryTestDb();
    await seedFakeCollectionIfEmpty(testDb);
  });

  tearDown(() async {
    await testDb.close();
  });

  testWidgets('an artwork match is reviewable and confirming logs it', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final artReadings = StreamController<ArtReading>.broadcast();
      addTearDown(artReadings.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWith((ref) async => testDb),
            artReadingsProvider.overrideWith((ref) => artReadings.stream),
            passcodeReadingsProvider
                .overrideWith((ref) => const Stream<PasscodeReading>.empty()),
            artMatcherProvider.overrideWith(
              (ref) async => _FakeArtMatcher(const [ArtCandidate(_dmCard, 2)]),
            ),
          ],
          child: MaterialApp.router(routerConfig: buildAppRouter()),
        ),
      );

      // Home -> Log Cards opens the camera scan screen.
      await tester.tap(find.text(AppStrings.homeTileLogCards));
      await pumpUntilSettled(tester);

      // Three agreeing, in-gate artwork frames drive the machine to a match.
      for (var i = 0; i < 3; i++) {
        artReadings.add(ArtReading(i, const HashMatch(_darkMagician, 2)));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump(const Duration(milliseconds: 20));
      }
      await pumpUntilSettled(tester);

      // The review panel shows the card and its default (Near Mint) grade.
      expect(find.text('Dark Magician'), findsOneWidget);
      expect(find.text(AppStrings.scanConfirmButton), findsOneWidget);

      // Downgrade to Excellent before confirming, proving the grade is editable.
      await tester.tap(find.text(CardCondition.excellent.shortCode));
      await pumpUntilSettled(tester);

      await tester.tap(find.text(AppStrings.scanConfirmButton));
      await pumpUntilSettled(tester);

      expect(find.text(AppStrings.scanSavedMessage), findsOneWidget);

      final entries = await CollectionDao(
        testDb,
      ).getEntriesForPasscode(_darkMagician);
      final scanned = entries.where(
        (e) => e.condition == CardCondition.excellent && e.printingId == null,
      );
      expect(scanned, hasLength(1));
    });
  });

  // Every hit the index ranks is now presented, however far out it sat, so the
  // review gate has to (a) say when it is guessing and (b) always offer a way
  // off the guess — a single candidate used to hide the escape hatch entirely.
  testWidgets('a marginal match is hedged and always escapable', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final artReadings = StreamController<ArtReading>.broadcast();
      addTearDown(artReadings.close);
      const far = ArtMatchTuning.autoMatchMaxDistance + 2;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWith((ref) async => testDb),
            artReadingsProvider.overrideWith((ref) => artReadings.stream),
            passcodeReadingsProvider
                .overrideWith((ref) => const Stream<PasscodeReading>.empty()),
            artMatcherProvider.overrideWith(
              // Exactly one candidate: the case that used to render no escape.
              (ref) async => _FakeArtMatcher(const [ArtCandidate(_dmCard, far)]),
            ),
          ],
          child: MaterialApp.router(routerConfig: buildAppRouter()),
        ),
      );

      await tester.tap(find.text(AppStrings.homeTileLogCards));
      await pumpUntilSettled(tester);

      for (var i = 0; i < 3; i++) {
        artReadings.add(ArtReading(i, const HashMatch(_darkMagician, far)));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump(const Duration(milliseconds: 20));
      }
      await pumpUntilSettled(tester);

      expect(find.text('Dark Magician'), findsOneWidget);
      expect(find.text(AppStrings.scanLowConfidence), findsOneWidget);
      expect(find.text(AppStrings.scanNotThisCardButton), findsOneWidget);
    });
  });

  testWidgets('a confident match is not hedged', (tester) async {
    await tester.runAsync(() async {
      final artReadings = StreamController<ArtReading>.broadcast();
      addTearDown(artReadings.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWith((ref) async => testDb),
            artReadingsProvider.overrideWith((ref) => artReadings.stream),
            passcodeReadingsProvider
                .overrideWith((ref) => const Stream<PasscodeReading>.empty()),
            artMatcherProvider.overrideWith(
              (ref) async => _FakeArtMatcher(const [ArtCandidate(_dmCard, 2)]),
            ),
          ],
          child: MaterialApp.router(routerConfig: buildAppRouter()),
        ),
      );

      await tester.tap(find.text(AppStrings.homeTileLogCards));
      await pumpUntilSettled(tester);

      for (var i = 0; i < 3; i++) {
        artReadings.add(ArtReading(i, const HashMatch(_darkMagician, 2)));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump(const Duration(milliseconds: 20));
      }
      await pumpUntilSettled(tester);

      expect(find.text('Dark Magician'), findsOneWidget);
      expect(find.text(AppStrings.scanLowConfidence), findsNothing);
    });
  });

  testWidgets('the how-to box follows its Settings toggle', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWith((ref) async => testDb),
            // Both streams inert: this test is about chrome, not recognition.
            artReadingsProvider
                .overrideWith((ref) => const Stream<ArtReading>.empty()),
            passcodeReadingsProvider
                .overrideWith((ref) => const Stream<PasscodeReading>.empty()),
          ],
          child: MaterialApp.router(routerConfig: buildAppRouter()),
        ),
      );

      await tester.tap(find.text(AppStrings.homeTileLogCards));
      await pumpUntilSettled(tester);

      expect(find.text(AppStrings.scanHelpTitle), findsOneWidget);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ScanScreen)),
      );
      // Settings must be resolved before a setter can write through them.
      await container.read(settingsControllerProvider.future);
      await container
          .read(settingsControllerProvider.notifier)
          .setShowScanHelp(false);
      await pumpUntilSettled(tester);

      expect(find.text(AppStrings.scanHelpTitle), findsNothing);
    });
  });

  // The surface a card is lying on decides whether its own edges survive the
  // detector's Otsu/Canny pass, so this note is the highest-value thing on the
  // viewfinder — but it is still help text, and follows the same one switch.
  testWidgets('the surface hint sits above the status banner and follows the '
      'same Settings toggle', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWith((ref) async => testDb),
            artReadingsProvider
                .overrideWith((ref) => const Stream<ArtReading>.empty()),
            passcodeReadingsProvider
                .overrideWith((ref) => const Stream<PasscodeReading>.empty()),
          ],
          child: MaterialApp.router(routerConfig: buildAppRouter()),
        ),
      );

      await tester.tap(find.text(AppStrings.homeTileLogCards));
      await pumpUntilSettled(tester);

      final hint = find.text(AppStrings.scanSurfaceHint);
      expect(hint, findsOneWidget);

      // **The regression this pins.** The hint used to be `Positioned` against
      // the reticle's rect while the banner grew down from the app bar — two
      // unrelated coordinate systems both advancing toward the middle of the
      // screen, which overlapped by ~35pt on a 360x640 viewport and closed
      // entirely under text scaling or a taller status bar. They now share one
      // `Column`, so the order is structural and a collision is impossible.
      // Asserting the geometry rather than mere presence is the whole point.
      //
      // The hint is *above* the banner: it says how to make recognition work at
      // all, which is worth reading before the running commentary on whether it
      // is working.
      final banner = find.text(AppStrings.scanDetecting);
      expect(banner, findsOneWidget);
      expect(
        tester.getBottomLeft(hint).dy,
        lessThanOrEqualTo(tester.getTopLeft(banner).dy),
      );

      // …and the box is still exactly centred, which is the invariant that
      // would have broken silently had the hint been stacked above it in a
      // `Column` instead: `reticleRectInViewport` is a `Rect.fromCenter` on the
      // viewport centre and the detector's search region is derived from it, so
      // moving the drawn box would silently desync it from the region searched.
      final reticle = find
          .ancestor(
            of: find.text(AppStrings.scanHint),
            matching: find.byType(Container),
          )
          .first;
      final box = tester.getRect(reticle);
      final viewport = tester.getSize(find.byType(ScanScreen));
      expect(box.center.dy, moreOrLessEquals(viewport.height / 2, epsilon: 0.5));

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ScanScreen)),
      );
      await container.read(settingsControllerProvider.future);
      await container
          .read(settingsControllerProvider.notifier)
          .setShowScanHelp(false);
      await pumpUntilSettled(tester);

      expect(hint, findsNothing);
    });
  });

  // The diagnostics box is eleven lines and a button growing down from the app
  // bar, while the reticle is centred — so it used to paint straight over the
  // guide box the user has to aim through, which is the one region on this
  // screen that must stay clear. The whole top column is now capped to the band
  // above the reticle, with the box scrolling inside it.
  testWidgets('the diagnostics overlay never reaches the reticle', (
    tester,
  ) async {
    // A phone-shaped viewport, not the 800x600 default: the band between the app
    // bar and a centred reticle is a function of viewport height, and at 600pt
    // it falls under `minBandHeight` — where the floor deliberately wins.
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 851);
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWith((ref) async => testDb),
            cameraServiceProvider.overrideWith((ref) => _InertCamera()),
            artReadingsProvider
                .overrideWith((ref) => const Stream<ArtReading>.empty()),
            passcodeReadingsProvider
                .overrideWith((ref) => const Stream<PasscodeReading>.empty()),
          ],
          child: MaterialApp.router(routerConfig: buildAppRouter()),
        ),
      );

      await tester.tap(find.text(AppStrings.homeTileLogCards));
      await pumpUntilSettled(tester);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ScanScreen)),
      );
      await container.read(settingsControllerProvider.future);
      await container
          .read(settingsControllerProvider.notifier)
          .setShowScanDiagnostics(true);
      await pumpUntilSettled(tester);

      expect(find.text(AppStrings.scanDiagnosticsNoFrame), findsOneWidget);

      // The banner is the *last* child of the top column, so its bottom is the
      // bottom of everything up there — diagnostics included.
      final bannerBox = find
          .ancestor(
            of: find.text(AppStrings.scanDetecting),
            matching: find.byType(Container),
          )
          .first;
      final viewport = tester.getSize(find.byType(ScanScreen));
      expect(
        tester.getRect(bannerBox).bottom,
        lessThanOrEqualTo(reticleRectInViewport(viewport).top),
        reason: 'the top overlays must clear the guide box entirely',
      );
    });
  });

  // Regression: the preview layer used to read `previewController` as a plain
  // getter. It is a const widget under a provider that never republishes, so it
  // built exactly once — while the camera was still opening — and held the
  // scrim forever. On a real device that is a permanently black viewfinder with
  // a working reticle on top, and nothing in this suite saw it, because no test
  // ever reaches the point where a controller becomes available.
  testWidgets('the preview layer subscribes to the camera becoming ready', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final camera = _InertCamera();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWith((ref) async => testDb),
            cameraServiceProvider.overrideWith((ref) => camera),
            // Keep both reading streams inert so no real matcher/index loads.
            artReadingsProvider
                .overrideWith((ref) => const Stream<ArtReading>.empty()),
            passcodeReadingsProvider
                .overrideWith((ref) => const Stream<PasscodeReading>.empty()),
          ],
          child: MaterialApp.router(routerConfig: buildAppRouter()),
        ),
      );

      await tester.tap(find.text(AppStrings.homeTileLogCards));
      await pumpUntilSettled(tester);

      expect(
        camera.previewNotifier.isObserved,
        isTrue,
        reason:
            'The scan screen must listen to CameraService.preview. Sampling it '
            'as a plain getter leaves the viewfinder black forever, since the '
            'camera opens asynchronously and nothing else rebuilds the layer.',
      );
    });
  });
}

/// A [ValueNotifier] that reports whether anyone is listening.
class _ObservablePreview extends ValueNotifier<CameraController?> {
  _ObservablePreview() : super(null);

  bool get isObserved => hasListeners;
}

/// A [CameraService] that touches no hardware: enough for the scan screen to
/// build and reach the preview layer.
class _InertCamera implements CameraService {
  final _ObservablePreview previewNotifier = _ObservablePreview();

  @override
  ValueListenable<CameraController?> get preview => previewNotifier;

  @override
  Stream<InputImage> get frames => const Stream<InputImage>.empty();

  @override
  ArtFrame? get latestArtFrame => null;

  @override
  InputImage? get latestInputImage => null;

  @override
  int get frameSequence => 0;

  @override
  set artCaptureEnabled(bool enabled) {}

  @override
  Future<void> setExposureCompensation(double ev) async {}

  @override
  CameraHealth get health => const CameraHealth(
    initialized: false,
    streaming: false,
    framesSeen: 0,
    sinceLastFrame: null,
    restarts: 0,
  );

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
