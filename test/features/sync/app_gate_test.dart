import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ygo_scanner/app.dart';
import 'package:ygo_scanner/core/constants.dart';
import 'package:ygo_scanner/data/db/dao/card_dao.dart';
import 'package:ygo_scanner/data/db/dao/meta_dao.dart';
import 'package:ygo_scanner/data/db/dao/printing_dao.dart';
import 'package:ygo_scanner/data/db/database.dart';
import 'package:ygo_scanner/data/repositories/card_repository.dart';
import 'package:ygo_scanner/features/sync/initial_sync_providers.dart';
import 'package:ygo_scanner/features/sync/initial_sync_screen.dart';
import 'package:ygo_scanner/models/ygo_card.dart';

import '../../data/db/test_db.dart';
import '../../support/widget_test_harness.dart';

/// A fake that starts out needing a sync and flips to synced once [sync]
/// completes — mirrors the real `needsSync`/`sync` relationship without
/// touching the network. Its own DAO calls still go through the real
/// (in-memory) sqflite isolate, same as production.
///
/// [sync] blocks on [_gate] between its two phases so the test can assert the
/// mid-sync state deterministically instead of racing the stream's microtask
/// draining: pump, assert `InitialSyncScreen` is up, then call [release] to
/// let the sync finish and swap to Home.
class _FakeCardRepository extends CardRepository {
  _FakeCardRepository(Database db)
    : super(
        cardDao: CardDao(db),
        printingDao: PrintingDao(db),
        metaDao: MetaDao(db),
        database: db,
      );

  final Completer<void> _gate = Completer<void>();
  bool _synced = false;

  @override
  Future<bool> needsSync() async => !_synced;

  @override
  Stream<SyncProgress> sync() async* {
    yield const SyncProgress(0.5, SyncPhase.fetching);
    await _gate.future;
    _synced = true;
    yield const SyncProgress(1, SyncPhase.writing);
  }

  void release() => _gate.complete();
}

void main() {
  // The db MUST be opened here (in setUp, a real-async zone), never inside a
  // testWidgets body — that body runs in the fake-async zone, and opening the
  // sqflite_common_ffi isolate connection there leaves it in a state that
  // hangs the test at teardown. See
  // `.claude/skills/flutter-test-troubleshooting.md`.
  late Database db;

  setUp(() async {
    db = await openInMemoryTestDb();
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets(
    'shows the sync screen first on a fresh db, then swaps to Home once sync completes',
    (tester) async {
      final repository = _FakeCardRepository(db);

      // runAsync is required: `MaterialApp.router`'s GoRouter mount and the
      // sqflite isolate both need real event-loop time that the fake clock
      // alone never provides. See pumpUntilSettled.
      await tester.runAsync(() async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWith((ref) async => db),
              debugSyncBypassProvider.overrideWith((ref) => false),
              cardRepositoryProvider.overrideWith((ref) async => repository),
            ],
            child: const App(),
          ),
        );
        await pumpUntilSettled(tester);

        // Sync is gated mid-stream: still on the sync screen, not Home.
        expect(find.byType(InitialSyncScreen), findsOneWidget);
        expect(find.text(AppStrings.homeTileLogCards), findsNothing);

        repository.release();
        await pumpUntilSettled(tester);

        expect(find.byType(InitialSyncScreen), findsNothing);
        expect(find.text(AppStrings.homeTileLogCards), findsOneWidget);
      });
    },
  );

  testWidgets(
    'renders Home immediately when a sync has already completed',
    (tester) async {
      await tester.runAsync(() async {
        // Seed inside runAsync (a real-async zone) so the ffi isolate writes
        // complete cleanly, then let the real CardRepository see an
        // already-synced db (cards present + last_sync stamped).
        await CardDao(db).insertAll(const [
          YgoCard(passcode: '89631139', name: 'Blue-Eyes White Dragon'),
        ]);
        await MetaDao(db).set('last_sync', '123456');

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWith((ref) async => db),
              debugSyncBypassProvider.overrideWith((ref) => false),
            ],
            child: const App(),
          ),
        );
        await pumpUntilSettled(tester);

        expect(find.byType(InitialSyncScreen), findsNothing);
        expect(find.text(AppStrings.homeTileLogCards), findsOneWidget);
      });
    },
  );
}
