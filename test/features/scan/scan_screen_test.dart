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
import 'package:ygo_scanner/features/scan/frame_quality.dart';
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
  testWidgets('the surface hint sits above the guide box and follows the '
      'same Settings toggle', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 851);
    addTearDown(tester.view.reset);

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
      // entirely under text scaling or a taller status bar. The hint now lives
      // in the top column and the banner inside the guide box, so a collision
      // is structurally impossible. Asserting the geometry rather than mere
      // presence is the whole point.
      final viewport = tester.getSize(find.byType(ScanScreen));
      final rect = reticleRectInViewport(viewport);
      expect(
        tester.getBottomLeft(hint).dy,
        lessThanOrEqualTo(rect.top),
        reason: 'the hint belongs in the band above the guide box',
      );

      // **The load-bearing assertion.** The drawn box must *be*
      // `reticleRectInViewport` — that function is also where the detector's
      // search region comes from, so a box drawn anywhere else silently asks
      // the user to fill a rectangle the app is not looking at. This replaces
      // the older `box.center.dy == viewport.height / 2`, which was a proxy for
      // the same thing back when the box was centred; it is now offset
      // deliberately, and the rect equality says what was always meant.
      final box = tester.getRect(find.byKey(scanReticleKey));
      expect(box.left, moreOrLessEquals(rect.left, epsilon: 0.5));
      expect(box.top, moreOrLessEquals(rect.top, epsilon: 0.5));
      expect(box.right, moreOrLessEquals(rect.right, epsilon: 0.5));
      expect(box.bottom, moreOrLessEquals(rect.bottom, epsilon: 0.5));

      // The status banner moved *inside* that box, which is what freed the band
      // above it for the diagnostics readout.
      final banner = find.text(AppStrings.scanDetecting);
      expect(banner, findsOneWidget);
      expect(box.contains(tester.getTopLeft(banner)), isTrue);
      expect(box.contains(tester.getBottomRight(banner)), isTrue);

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

  // The diagnostics box grows down from the app bar while the guide box is
  // fixed, so uncapped it painted straight over the box the user has to aim
  // through — the one region on this screen that must stay clear. The top
  // column is capped to the band above the reticle.
  testWidgets('the diagnostics overlay never reaches the reticle', (
    tester,
  ) async {
    // A phone-shaped viewport, not the 800x600 default: the band is a function
    // of viewport height, and at 600pt it falls under `minBandHeight` — where
    // the floor deliberately wins.
    //
    // The status-bar inset matters just as much and used to be missing. With
    // `extendBodyBehindAppBar`, `Scaffold` reports the body's `padding.top` as
    // `max(view padding, app bar height)`, so leaving it at zero measured a
    // 130pt band where a real phone has 91 — the test passed while the device
    // clipped, which is exactly how the reported bug survived this suite.
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 851);
    tester.view.padding = const FakeViewPadding(top: 39);
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

      // The diagnostics box is now the only thing in the top column (the banner
      // moved into the guide box), so its bottom is the bottom of everything up
      // there.
      final box = find
          .ancestor(
            of: find.text(AppStrings.scanDiagnosticsNoFrame),
            matching: find.byType(Container),
          )
          .first;
      final viewport = tester.getSize(find.byType(ScanScreen));
      expect(
        tester.getRect(box).bottom,
        lessThanOrEqualTo(reticleRectInViewport(viewport).top),
        reason: 'the top overlays must clear the guide box entirely',
      );
    });
  });

  // **The point of the layout change.** The readout is what the last several
  // passes have been waiting on for tuning evidence, and its most useful lines
  // — `qual:`, the art-box result, the candidate distances — are the ones at
  // the bottom, so a box a third too short hid exactly the wrong ones.
  //
  // Asserting the *scroll extent* rather than a pixel height is deliberate: it
  // measures the property complained about ("cannot be read in its entirety")
  // and survives font-metric drift and any later re-arithmetic of the band.
  testWidgets('the whole diagnostics readout fits without scrolling', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 851);
    tester.view.padding = const FakeViewPadding(top: 39);
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      final artReadings = StreamController<ArtReading>.broadcast();
      addTearDown(artReadings.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWith((ref) async => testDb),
            cameraServiceProvider.overrideWith((ref) => _InertCamera()),
            artReadingsProvider.overrideWith((ref) => artReadings.stream),
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

      // The worst case the readout can report: a detected card with an assessed
      // crop and a full set of nearest candidates. Everything the pipeline has
      // to say, all at once.
      artReadings.add(
        const ArtReading(
          1,
          HashMatch(_darkMagician, 40),
          status: ArtFrameStatus.detected,
          quality: FrameQuality(sharpness: 612, glare: 0.03),
          artBox: Rect.fromLTWH(0.1, 0.18, 0.76, 0.7),
          nearest: [
            HashMatch(_darkMagician, 40),
            HashMatch('89631139', 58),
            HashMatch('44095762', 66),
          ],
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await pumpUntilSettled(tester);

      // The merged frame-status line, so all eight lines are being rendered.
      expect(find.textContaining('art box:'), findsOneWidget);

      // The box is private, so anchor on one of its own lines to reach the
      // scroll view it lives in.
      final scrollable = tester.state<ScrollableState>(
        find
            .ancestor(
              of: find.textContaining('art box:'),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(
        scrollable.position.maxScrollExtent,
        0,
        reason: 'the whole readout has to be visible at once — the lines that '
            'matter most for tuning are the last ones, so a box that scrolls '
            'hides exactly the wrong half',
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

  // **The reported bug.** Decline a card, go back to the menu, open Log Cards
  // again — and nothing is ever recognised, for the rest of the app's life.
  //
  // `scanPaused` is `keepAlive` (deliberately — its only reader and writer both
  // use `ref.read`, so autoDispose left the whole pause inert) while
  // `ScanController` is autoDispose. Leaving the screen with a result on it
  // therefore pinned the flag `true` and `artReadings` `continue`d on every
  // subsequent frame forever: camera streaming, preview live, reticle drawn,
  // and no readings at all. Only relaunching the app cleared it.
  //
  // The screen clears it on entry rather than the previous screen clearing it
  // on exit: a fresh `ScanController` always starts in `detecting`, so unpaused
  // is the only correct state here however the last session ended — and
  // Riverpod asserts on provider writes from *any* widget life-cycle, `dispose`
  // included, so an exit-time reset is not available.
  testWidgets('opening the scan screen clears a stale scan pause', (
    tester,
  ) async {
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
          child: const MaterialApp(home: SizedBox.shrink()),
        ),
      );

      // A previous session that ended with a review panel on screen.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SizedBox)),
      );
      container.read(scanPausedProvider.notifier).set(paused: true);

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
          child: const MaterialApp(home: ScanScreen()),
        ),
      );
      await pumpUntilSettled(tester);

      expect(
        container.read(scanPausedProvider),
        isFalse,
        reason: 'a keepAlive pause left set by the autoDispose controller kills '
            'recognition for the whole process — the reported "declining a card '
            'stops the camera working" bug, which only relaunching cleared',
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
