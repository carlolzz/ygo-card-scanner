import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ygo_scanner/data/db/dao/collection_dao.dart';
import 'package:ygo_scanner/data/db/database.dart';
import 'package:ygo_scanner/data/seed/fake_collection_seed.dart';
import 'package:ygo_scanner/features/scan/art_matcher.dart';
import 'package:ygo_scanner/features/scan/art_providers.dart';
import 'package:ygo_scanner/features/scan/scan_controller.dart';
import 'package:ygo_scanner/features/scan/scan_providers.dart';
import 'package:ygo_scanner/features/scan/scan_state.dart';
import 'package:ygo_scanner/models/card_condition.dart';
import 'package:ygo_scanner/models/ygo_card.dart';

import '../../data/db/test_db.dart';

/// Fake matcher so the controller's artwork-match branch runs without a camera,
/// image asset, or pHash math — mirroring how [passcodeReadingsProvider] is
/// faked for the OCR branch.
class _FakeArtMatcher implements ArtMatcher {
  _FakeArtMatcher(this.result);
  final List<ArtCandidate> result;
  @override
  Future<List<ArtCandidate>> match() async => result;
}

// Seeded fixture passcodes (see fake_collection_seed.dart).
const darkMagician = '46986414';
const blueEyes = '89631139';
const unknownPasscode = '00000000';

// The scan pipeline resolves through the sqflite_common_ffi background
// isolate; a real delay (not a fake clock) lets stream events and db round
// trips actually complete.
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 30));

void main() {
  late Database db;
  late StreamController<PasscodeReading> readings;
  late ProviderContainer container;
  var seq = 0;
  // Mutated by the artwork-match tests before triggering matchByArtwork().
  var fakeCandidates = <ArtCandidate>[];

  Future<void> feed(String? passcode) async {
    readings.add(PasscodeReading(seq++, passcode));
    await settle();
  }

  ScanState state() => container.read(scanControllerProvider);

  setUp(() async {
    db = await openInMemoryTestDb();
    await seedFakeCollectionIfEmpty(db);
    readings = StreamController<PasscodeReading>.broadcast();
    seq = 0;
    fakeCandidates = <ArtCandidate>[];
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((ref) async => db),
        passcodeReadingsProvider.overrideWith((ref) => readings.stream),
        artMatcherProvider
            .overrideWith((ref) async => _FakeArtMatcher(fakeCandidates)),
      ],
    );
    // Keep the controller alive so its stream subscription stays registered.
    container.listen(scanControllerProvider, (previous, next) {});
    await settle();
  });

  tearDown(() async {
    container.dispose();
    await readings.close();
    await db.close();
  });

  test('starts in the detecting state', () {
    expect(state().status, ScanStatus.detecting);
  });

  test('fewer than N agreeing reads does not match', () async {
    await feed(darkMagician);
    await feed(darkMagician);
    expect(state().status, ScanStatus.reading);
    expect(state().matchedCard, isNull);
  });

  test('N agreeing reads that hit the db resolve to a match', () async {
    await feed(darkMagician);
    await feed(darkMagician);
    await feed(darkMagician);
    await settle();

    expect(state().status, ScanStatus.matched);
    expect(state().matchedCard?.name, 'Dark Magician');
    // Defaults offered for review.
    expect(state().condition, CardCondition.nearMint);
  });

  test('disagreeing reads are discarded and never reach N', () async {
    await feed(darkMagician);
    await feed(blueEyes); // disagreement clears the run
    await feed(darkMagician);
    await settle();

    expect(state().status, ScanStatus.reading);
    expect(state().matchedCard, isNull);
  });

  test('N agreeing reads with no db hit resolve to unknown', () async {
    await feed(unknownPasscode);
    await feed(unknownPasscode);
    await feed(unknownPasscode);
    await settle();

    expect(state().status, ScanStatus.unknown);
    expect(state().unknownPasscode, unknownPasscode);
  });

  test('confirm writes the reviewed entry and resumes', () async {
    await feed(darkMagician);
    await feed(darkMagician);
    await feed(darkMagician);
    await settle();

    await container.read(scanControllerProvider.notifier).confirm();
    await settle();

    final entries = await CollectionDao(db).getEntriesForPasscode(darkMagician);
    // The seed already logged Dark Magician as Mint; a Near Mint scan is a
    // distinct stack, so it adds a row rather than incrementing.
    final scanned = entries.where(
      (e) => e.condition == CardCondition.nearMint && e.printingId == null,
    );
    expect(scanned, hasLength(1));
    expect(scanned.first.quantity, 1);
    expect(state().status, ScanStatus.confirmed);
  });

  test('the same passcode is debounced until the frame goes empty', () async {
    // Confirm once.
    await feed(darkMagician);
    await feed(darkMagician);
    await feed(darkMagician);
    await settle();
    await container.read(scanControllerProvider.notifier).confirm();
    await settle();

    // The card is still in view: re-reads must NOT re-match.
    await feed(darkMagician);
    await feed(darkMagician);
    await feed(darkMagician);
    expect(state().status, isNot(ScanStatus.matched));

    // The card leaves the frame for M empty frames, then returns.
    for (var i = 0; i < 5; i++) {
      await feed(null);
    }
    await feed(darkMagician);
    await feed(darkMagician);
    await feed(darkMagician);
    await settle();

    expect(state().status, ScanStatus.matched);
  });

  group('artwork-match fallback', () {
    const dmCard = YgoCard(
      passcode: darkMagician,
      name: 'Dark Magician',
      type: 'Normal Monster',
    );

    Future<void> matchByArtwork() async {
      await container.read(scanControllerProvider.notifier).matchByArtwork();
      await settle();
    }

    test('surfaces ranked candidates for the user to pick', () async {
      fakeCandidates = [const ArtCandidate(dmCard, 3)];
      await matchByArtwork();

      expect(state().status, ScanStatus.candidates);
      expect(state().candidates, hasLength(1));
      expect(state().candidates.first.card.name, 'Dark Magician');
    });

    test('no candidates falls back to unknown (search by name)', () async {
      fakeCandidates = [];
      await matchByArtwork();

      expect(state().status, ScanStatus.unknown);
      expect(state().candidates, isEmpty);
    });

    test('selecting a candidate enters the review gate with defaults', () async {
      fakeCandidates = [const ArtCandidate(dmCard, 3)];
      await matchByArtwork();

      container.read(scanControllerProvider.notifier).selectCandidate(dmCard);
      expect(state().status, ScanStatus.matched);
      expect(state().matchedCard?.passcode, darkMagician);
      expect(state().condition, CardCondition.nearMint);
      expect(state().candidates, isEmpty);
    });

    test('full flow: unknown → artwork match → pick → confirm writes one row',
        () async {
      // OCR agreed on a passcode not in the db.
      await feed(unknownPasscode);
      await feed(unknownPasscode);
      await feed(unknownPasscode);
      await settle();
      expect(state().status, ScanStatus.unknown);

      // Fall back to artwork, which finds the real card.
      fakeCandidates = [const ArtCandidate(dmCard, 5)];
      await matchByArtwork();
      expect(state().status, ScanStatus.candidates);

      container.read(scanControllerProvider.notifier).selectCandidate(dmCard);
      await container.read(scanControllerProvider.notifier).confirm();
      await settle();

      final scanned = (await CollectionDao(db)
              .getEntriesForPasscode(darkMagician))
          .where(
        (e) => e.condition == CardCondition.nearMint && e.printingId == null,
      );
      expect(scanned, hasLength(1));
      expect(state().status, ScanStatus.confirmed);
    });

    test('dismiss from candidates returns to detecting', () async {
      fakeCandidates = [const ArtCandidate(dmCard, 3)];
      await matchByArtwork();
      expect(state().status, ScanStatus.candidates);

      container.read(scanControllerProvider.notifier).dismiss();
      expect(state().status, ScanStatus.detecting);
      expect(state().candidates, isEmpty);
    });
  });
}
