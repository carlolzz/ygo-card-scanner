import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ygo_scanner/data/db/dao/collection_dao.dart';
import 'package:ygo_scanner/data/db/database.dart';
import 'package:ygo_scanner/data/seed/fake_collection_seed.dart';
import 'package:ygo_scanner/features/scan/scan_controller.dart';
import 'package:ygo_scanner/features/scan/scan_providers.dart';
import 'package:ygo_scanner/features/scan/scan_state.dart';
import 'package:ygo_scanner/models/card_condition.dart';

import '../../data/db/test_db.dart';

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
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((ref) async => db),
        passcodeReadingsProvider.overrideWith((ref) => readings.stream),
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
}
