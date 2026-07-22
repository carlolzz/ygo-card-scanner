import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ygo_scanner/core/constants.dart';
import 'package:ygo_scanner/data/db/dao/card_dao.dart';
import 'package:ygo_scanner/data/db/dao/meta_dao.dart';
import 'package:ygo_scanner/data/db/dao/printing_dao.dart';
import 'package:ygo_scanner/data/repositories/card_repository.dart';
import 'package:ygo_scanner/features/sync/initial_sync_screen.dart';

import '../../data/db/test_db.dart';

class _FakeCardRepository extends CardRepository {
  _FakeCardRepository(Database db, this.syncImpl)
    : super(
        cardDao: CardDao(db),
        printingDao: PrintingDao(db),
        metaDao: MetaDao(db),
        database: db,
      );

  final Stream<SyncProgress> Function() syncImpl;

  @override
  Stream<SyncProgress> sync() => syncImpl();
}

void main() {
  late Database db;

  setUp(() async {
    db = await openInMemoryTestDb();
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpScreen(
    WidgetTester tester,
    Stream<SyncProgress> Function() syncImpl,
  ) async {
    final repository = _FakeCardRepository(db, syncImpl);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cardRepositoryProvider.overrideWith((ref) async => repository),
        ],
        child: const MaterialApp(home: InitialSyncScreen()),
      ),
    );
  }

  // Deliberately not pumpAndSettle(): the running state's
  // LinearProgressIndicator is determinate, but nothing here should ever
  // render an indeterminate (infinitely-animating) widget — a handful of
  // bounded pumps is both sufficient and safe against that trap.
  Future<void> pumpSteps(WidgetTester tester, {int times = 6}) async {
    for (var i = 0; i < times; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  testWidgets('shows progress while running, then success', (tester) async {
    // A real gap between events matters: with no delay at all, the whole
    // stream drains within the microtasks between two pumps and the
    // intermediate "running" frame is never actually rendered.
    await pumpScreen(tester, () async* {
      yield const SyncProgress(0.3, SyncPhase.fetching);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      yield const SyncProgress(0.9, SyncPhase.writing);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });

    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text(AppStrings.syncFetchingMessage), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(find.text(AppStrings.syncWritingMessage), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 250));
    await pumpSteps(tester);
    // Success is a transitional, deliberately empty state — its absence of
    // progress UI and error UI is what confirms it was reached.
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text(AppStrings.syncErrorMessage), findsNothing);
  });

  testWidgets(
    'shows an error and retry button on failure, and retry re-invokes sync',
    (tester) async {
      var callCount = 0;
      await pumpScreen(tester, () {
        callCount++;
        if (callCount == 1) {
          return Stream<SyncProgress>.error(Exception('offline'));
        }
        return Stream.value(const SyncProgress(1, SyncPhase.writing));
      });

      await pumpSteps(tester);
      expect(find.text(AppStrings.syncErrorMessage), findsOneWidget);
      expect(find.text(AppStrings.syncRetryButton), findsOneWidget);

      await tester.tap(find.text(AppStrings.syncRetryButton));
      await pumpSteps(tester);

      expect(callCount, 2);
      expect(find.text(AppStrings.syncErrorMessage), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    },
  );
}
