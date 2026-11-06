import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ygo_scanner/core/constants.dart';
import 'package:ygo_scanner/core/theme/tokens.dart';
import 'package:ygo_scanner/data/db/dao/collection_dao.dart';
import 'package:ygo_scanner/data/db/database.dart';
import 'package:ygo_scanner/data/export/file_share.dart';
import 'package:ygo_scanner/data/import/csv_file_source.dart';
import 'package:ygo_scanner/data/seed/fake_collection_seed.dart';
import 'package:ygo_scanner/features/statistics/statistics_providers.dart';
import 'package:ygo_scanner/features/statistics/statistics_screen.dart';
import 'package:ygo_scanner/models/card_condition.dart';

import '../../data/db/test_db.dart';
import '../../support/widget_test_harness.dart';

/// Stands in for the system file picker — the one part of the import that
/// cannot run in a widget test. Everything behind it (parse, resolve, merge,
/// write) is real.
class _FakeCsvSource implements CsvFileSource {
  _FakeCsvSource(this.contents);

  /// Null models the user backing out of the picker.
  final String? contents;
  var pickCount = 0;

  @override
  Future<PickedCsv?> pick() async {
    pickCount++;
    if (contents == null) return null;
    return PickedCsv(name: 'collection.csv', contents: contents!);
  }
}

/// Stands in for the OS share sheet — the export's equivalent of
/// [_FakeCsvSource], and the reason that seam exists at all: the message shown
/// afterwards used to be chosen before the sheet even opened, so there was no
/// way to reach the cancelled branch from a test, and no way to notice it was
/// missing.
class _FakeFileShare implements FileShare {
  _FakeFileShare(this.outcome);

  final ShareOutcome outcome;
  var shareCount = 0;
  List<String> lastPaths = const [];

  @override
  Future<ShareOutcome> shareFiles(List<String> paths, {String? subject}) async {
    shareCount++;
    lastPaths = paths;
    return outcome;
  }
}

/// Redirects `getApplicationDocumentsDirectory()` to a real temp dir so the
/// exporter can write its file in the test environment.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.docsPath);
  final String docsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => docsPath;
}

const _csvHeader =
    'passcode,name,set_code,set_name,rarity,condition,edition,language,'
    'quantity,notes,created_at,updated_at';

String _csv(List<String> rows) => '${[_csvHeader, ...rows].join('\r\n')}\r\n';

void main() {
  late Database testDb;

  setUp(() async {
    testDb = await openInMemoryTestDb();
    await seedFakeCollectionIfEmpty(testDb);
  });

  tearDown(() async {
    await testDb.close();
  });

  /// The screen is a `ListView` and the actions sit at its end; at the default
  /// 600pt height they are past the fold and a lazy list has not built them, so
  /// `ensureVisible` cannot find them at all.
  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> openStatistics(
    WidgetTester tester, {
    CsvFileSource? source,
    FileShare? share,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((ref) async => testDb),
          if (source != null) csvFileSourceProvider.overrideWithValue(source),
          if (share != null) fileShareProvider.overrideWithValue(share),
        ],
        child: const MaterialApp(home: StatisticsScreen()),
      ),
    );
    await pumpUntilSettled(tester);
  }

  testWidgets('renders totals, breakdown sections and the export button', (
    tester,
  ) async {
    useTallViewport(tester);

    await tester.runAsync(() async {
      await openStatistics(tester);

      // Exact counts are covered by the DAO aggregate tests; here we assert the
      // screen structure. (Seed: 9 copies across 5 distinct passcodes.)
      expect(find.text(AppStrings.statisticsTotalCopiesLabel), findsOneWidget);
      expect(
        find.text(AppStrings.statisticsDistinctCardsLabel),
        findsOneWidget,
      );

      expect(
        find.text(AppStrings.statisticsByConditionSection),
        findsOneWidget,
      );
      expect(find.text(AppStrings.statisticsByLanguageSection), findsOneWidget);
      expect(find.text(AppStrings.statisticsByTypeSection), findsOneWidget);
      // The seed is all-English, so the language breakdown has one row.
      expect(find.text('English'), findsOneWidget);

      expect(find.text(AppStrings.statisticsExportButton), findsOneWidget);
      expect(find.text(AppStrings.statisticsImportButton), findsOneWidget);
    });
  });

  Future<int> quantityOf(String passcode, CardCondition condition) async {
    final entries = await CollectionDao(testDb).getEntriesForPasscode(passcode);
    return entries
        .where((e) => e.condition == condition)
        .fold<int>(0, (sum, e) => sum + e.quantity);
  }

  /// Taps Import and waits for the confirmation dialog.
  Future<void> tapImport(WidgetTester tester) async {
    await tester.ensureVisible(find.text(AppStrings.statisticsImportButton));
    await pumpUntilSettled(tester);
    await tester.tap(find.text(AppStrings.statisticsImportButton));
    await pumpUntilSettled(tester);
  }

  // The reported bug: the SnackBar text was chosen the moment the file was
  // written, then the sheet was opened and its result discarded — so swiping
  // the sheet away still reported "Exported — choose where to save it." about a
  // file the user had just declined to save, sitting in a directory Android
  // does not let them browse to.
  group('CSV export', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('ygo_export_screen_test');
      PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    Future<void> tapExport(WidgetTester tester) async {
      await tester.ensureVisible(find.text(AppStrings.statisticsExportButton));
      await pumpUntilSettled(tester);
      await tester.tap(find.text(AppStrings.statisticsExportButton));
      await pumpUntilSettled(tester);
    }

    testWidgets('a completed share reports success', (tester) async {
      useTallViewport(tester);

      await tester.runAsync(() async {
        final share = _FakeFileShare(ShareOutcome.shared);
        await openStatistics(tester, share: share);
        await tapExport(tester);

        expect(share.shareCount, 1);
        expect(share.lastPaths.single, endsWith('.csv'));
        expect(
          find.text(AppStrings.statisticsExportDoneMessage),
          findsOneWidget,
        );
      });
    });

    testWidgets('backing out of the share sheet says so instead', (
      tester,
    ) async {
      useTallViewport(tester);

      await tester.runAsync(() async {
        await openStatistics(
          tester,
          share: _FakeFileShare(ShareOutcome.cancelled),
        );
        await tapExport(tester);

        expect(
          find.text(AppStrings.statisticsExportCancelledMessage),
          findsOneWidget,
        );
        expect(find.text(AppStrings.statisticsExportDoneMessage), findsNothing);
        // Reported as lingering: the user dismissed the sheet themselves, so
        // the notice only has to confirm it, not be read at length.
        expect(
          tester.widget<SnackBar>(find.byType(SnackBar)).duration,
          SnackBarTokens.briefDuration,
        );
      });
    });

    testWidgets('a completed share keeps the default duration', (
      tester,
    ) async {
      useTallViewport(tester);

      await tester.runAsync(() async {
        await openStatistics(
          tester,
          share: _FakeFileShare(ShareOutcome.shared),
        );
        await tapExport(tester);

        expect(
          tester.widget<SnackBar>(find.byType(SnackBar)).duration,
          isNot(SnackBarTokens.briefDuration),
        );
      });
    });

    // Some platforms genuinely cannot report which target was chosen. Claiming
    // a cancellation that may not have happened is the worse of the two errors:
    // the file was written and the sheet was offered.
    testWidgets('an unreportable share is treated as success', (tester) async {
      useTallViewport(tester);

      await tester.runAsync(() async {
        await openStatistics(
          tester,
          share: _FakeFileShare(ShareOutcome.unknown),
        );
        await tapExport(tester);

        expect(
          find.text(AppStrings.statisticsExportDoneMessage),
          findsOneWidget,
        );
      });
    });
  });

  group('CSV import', () {
    testWidgets('a new card is added after confirming', (tester) async {
      useTallViewport(tester);

      await tester.runAsync(() async {
        await openStatistics(
          tester,
          source: _FakeCsvSource(
            _csv(['55144522,Pot of Greed,,,,GOOD,UNLIMITED,EN,4,,,']),
          ),
        );
        await tapImport(tester);

        expect(find.text(AppStrings.statisticsImportTitle), findsOneWidget);
        // The counts are `RichText`, which the default finder skips.
        expect(
          find.textContaining(
            AppStrings.statisticsImportNewLabel,
            findRichText: true,
          ),
          findsOneWidget,
        );
        // Nothing matched, so there is no merge question to ask...
        expect(find.text(AppStrings.statisticsImportKeepOption), findsNothing);
        // ...and no line claiming zero of anything.
        expect(
          find.textContaining(
            AppStrings.statisticsImportSkippedLabel,
            findRichText: true,
          ),
          findsNothing,
        );

        await tester.tap(find.text(AppStrings.statisticsImportConfirmButton));
        await pumpUntilSettled(tester);

        expect(await quantityOf('55144522', CardCondition.good), 4);
      });
    });

    // The user's example: two of the same card, one entry, quantity unchanged.
    testWidgets('keeping merges duplicates without changing the count', (
      tester,
    ) async {
      useTallViewport(tester);

      await tester.runAsync(() async {
        await openStatistics(
          tester,
          source: _FakeCsvSource(
            _csv(['46986414,Dark Magician,,,,MINT,UNLIMITED,EN,1,,,']),
          ),
        );
        await tapImport(tester);

        // Something matched, so the question is asked — and "keep" is the
        // preselected default.
        expect(
          find.text(AppStrings.statisticsImportKeepOption),
          findsOneWidget,
        );
        await tester.tap(find.text(AppStrings.statisticsImportConfirmButton));
        await pumpUntilSettled(tester);

        expect(await quantityOf('46986414', CardCondition.mint), 1);
        expect(
          await CollectionDao(testDb).getEntriesForPasscode('46986414'),
          hasLength(1),
        );
      });
    });

    testWidgets('choosing to sum adds the quantities', (tester) async {
      useTallViewport(tester);

      await tester.runAsync(() async {
        await openStatistics(
          tester,
          source: _FakeCsvSource(
            _csv(['46986414,Dark Magician,,,,MINT,UNLIMITED,EN,2,,,']),
          ),
        );
        await tapImport(tester);

        await tester.tap(find.text(AppStrings.statisticsImportSumOption));
        await pumpUntilSettled(tester);
        await tester.tap(find.text(AppStrings.statisticsImportConfirmButton));
        await pumpUntilSettled(tester);

        expect(await quantityOf('46986414', CardCondition.mint), 3);
      });
    });

    testWidgets('cancelling the dialog writes nothing', (tester) async {
      useTallViewport(tester);

      await tester.runAsync(() async {
        await openStatistics(
          tester,
          source: _FakeCsvSource(
            _csv(['46986414,Dark Magician,,,,MINT,UNLIMITED,EN,5,,,']),
          ),
        );
        await tapImport(tester);

        await tester.tap(find.text(AppStrings.statisticsImportCancelButton));
        await pumpUntilSettled(tester);

        expect(await quantityOf('46986414', CardCondition.mint), 1);
      });
    });

    testWidgets('backing out of the picker is silent', (tester) async {
      useTallViewport(tester);

      await tester.runAsync(() async {
        final source = _FakeCsvSource(null);
        await openStatistics(tester, source: source);
        await tapImport(tester);

        expect(source.pickCount, 1);
        expect(find.text(AppStrings.statisticsImportTitle), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
      });
    });

    testWidgets('a file that is not a collection CSV is refused', (
      tester,
    ) async {
      useTallViewport(tester);

      await tester.runAsync(() async {
        await openStatistics(
          tester,
          source: _FakeCsvSource('some,other,file\r\n1,2,3\r\n'),
        );
        await tapImport(tester);

        expect(find.text(AppStrings.statisticsImportTitle), findsNothing);
        expect(
          find.textContaining(AppStrings.statisticsImportFailedMessage),
          findsOneWidget,
        );
      });
    });
  });

  // Importing into an empty collection is the main case for that button, and it
  // used to be unreachable: the whole body was replaced by the empty message.
  testWidgets('the import button is reachable with an empty collection', (
    tester,
  ) async {
    useTallViewport(tester);

    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWith((ref) async => testDb),
            // Stubbed rather than pointed at an empty database: `flutter test`
            // runs with `kDebugMode == true`, so the debug fixture seed would
            // fill any empty db before this screen ever read it.
            collectionStatsProvider.overrideWith(
              (ref) async => const CollectionStats(
                totalCopies: 0,
                distinctCards: 0,
                byCondition: {},
                byLanguage: {},
                byCardType: {},
              ),
            ),
          ],
          child: const MaterialApp(home: StatisticsScreen()),
        ),
      );
      await pumpUntilSettled(tester);

      expect(find.text(AppStrings.statisticsEmptyMessage), findsOneWidget);
      expect(find.text(AppStrings.statisticsImportButton), findsOneWidget);
    });
  });
}
