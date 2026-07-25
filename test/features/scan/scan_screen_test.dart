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
import 'package:ygo_scanner/data/db/dao/collection_dao.dart';
import 'package:ygo_scanner/data/db/database.dart';
import 'package:ygo_scanner/data/seed/fake_collection_seed.dart';
import 'package:ygo_scanner/features/scan/art_frame.dart';
import 'package:ygo_scanner/features/scan/art_matcher.dart';
import 'package:ygo_scanner/features/scan/art_providers.dart';
import 'package:ygo_scanner/features/scan/camera_service.dart';
import 'package:ygo_scanner/features/scan/hash_index.dart';
import 'package:ygo_scanner/features/scan/scan_providers.dart';
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
  ArtFrameResult rankFrame({bool includeNearest = false, Size? viewportSize}) =>
      const ArtFrameResult(ArtFrameStatus.notDetected, []);
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
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
