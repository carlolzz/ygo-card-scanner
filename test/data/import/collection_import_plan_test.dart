import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/data/import/collection_import_plan.dart';
import 'package:ygo_scanner/models/card_condition.dart';
import 'package:ygo_scanner/models/card_edition.dart';
import 'package:ygo_scanner/models/collection_entry.dart';

/// The rule that decides what "the same entry" means, tested exhaustively on the
/// host. It is worth this much attention because every way of getting it wrong
/// is silent: a duplicated row looks like a real second entry, and a wrongly
/// merged one looks like a card the user never owned.
void main() {
  const now = 1000;

  ResolvedImportRow row({
    String passcode = '46986414',
    int? printingId,
    CardCondition condition = CardCondition.nearMint,
    CardEdition edition = CardEdition.unlimited,
    String language = 'EN',
    int quantity = 1,
    bool setUnresolved = false,
  }) => ResolvedImportRow(
    passcode: passcode,
    printingId: printingId,
    condition: condition,
    edition: edition,
    language: language,
    quantity: quantity,
    setUnresolved: setUnresolved,
  );

  CollectionEntry entry({
    required int id,
    String passcode = '46986414',
    int? printingId,
    CardCondition condition = CardCondition.nearMint,
    CardEdition edition = CardEdition.unlimited,
    String language = 'EN',
    int quantity = 1,
  }) => CollectionEntry(
    id: id,
    passcode: passcode,
    printingId: printingId,
    condition: condition,
    edition: edition,
    language: language,
    quantity: quantity,
    createdAt: 1,
    updatedAt: 1,
  );

  CollectionImportPlan plan(
    List<ResolvedImportRow> rows,
    List<CollectionEntry> existing,
    ImportMergeStrategy strategy,
  ) => planCollectionImport(
    rows: rows,
    existing: existing,
    strategy: strategy,
    now: now,
  );

  group('a card the collection does not have', () {
    test('is inserted under either strategy', () {
      for (final strategy in ImportMergeStrategy.values) {
        final result = plan([row(quantity: 3)], const [], strategy);

        expect(result.inserts.single.passcode, '46986414');
        expect(result.inserts.single.quantity, 3);
        expect(result.quantities, isEmpty);
        expect(result.newEntries, 1);
        expect(result.matchedEntries, 0);
        expect(result.copiesAdded, 3);
      }
    });

    test('carries the import timestamp on both createdAt and updatedAt', () {
      final result = plan([row()], const [], ImportMergeStrategy.keepExisting);
      expect(result.inserts.single.createdAt, now);
      expect(result.inserts.single.updatedAt, now);
    });
  });

  // The user's example: two Toon Cannon Soldier at quantity 1 become one entry
  // at quantity 1 under keep, or one at quantity 2 under sum.
  group('a card the collection already has, in every matching respect', () {
    test('keepExisting writes nothing at all', () {
      final result = plan(
        [row()],
        [entry(id: 7)],
        ImportMergeStrategy.keepExisting,
      );

      expect(result.inserts, isEmpty);
      expect(result.quantities, isEmpty, reason: 'the existing row is untouched');
      expect(result.isEmpty, isTrue);
      expect(result.matchedEntries, 1);
      expect(result.copiesAdded, 0);
    });

    test('keepExisting keeps the existing quantity even when they differ', () {
      final result = plan(
        [row(quantity: 1)],
        [entry(id: 7, quantity: 3)],
        ImportMergeStrategy.keepExisting,
      );
      expect(result.quantities, isEmpty);

      final other = plan(
        [row(quantity: 3)],
        [entry(id: 7, quantity: 1)],
        ImportMergeStrategy.keepExisting,
      );
      expect(other.quantities, isEmpty);
    });

    test('sumQuantities sets an absolute total, not a delta', () {
      final result = plan(
        [row(quantity: 2)],
        [entry(id: 7, quantity: 3)],
        ImportMergeStrategy.sumQuantities,
      );

      expect(result.inserts, isEmpty);
      expect(result.quantities, {7: 5});
      expect(result.matchedEntries, 1);
      expect(result.copiesAdded, 2);
    });
  });

  group('a difference in any graded respect makes it a different entry', () {
    test('condition', () {
      final result = plan(
        [row(condition: CardCondition.played)],
        [entry(id: 7)],
        ImportMergeStrategy.sumQuantities,
      );
      expect(result.newEntries, 1);
      expect(result.matchedEntries, 0);
    });

    test('edition', () {
      final result = plan(
        [row(edition: CardEdition.first)],
        [entry(id: 7)],
        ImportMergeStrategy.sumQuantities,
      );
      expect(result.newEntries, 1);
    });

    test('language', () {
      final result = plan(
        [row(language: 'DE')],
        [entry(id: 7)],
        ImportMergeStrategy.sumQuantities,
      );
      expect(result.newEntries, 1);
    });

    test('printing', () {
      final result = plan(
        [row(printingId: 2)],
        [entry(id: 7, printingId: 3)],
        ImportMergeStrategy.sumQuantities,
      );
      expect(result.newEntries, 1);
    });

    test('passcode', () {
      final result = plan(
        [row(passcode: '89631139')],
        [entry(id: 7)],
        ImportMergeStrategy.sumQuantities,
      );
      expect(result.newEntries, 1);
    });
  });

  // SQLite treats every NULL as distinct under a UNIQUE constraint, so this is
  // the case every other write path in the DAO has to special-case by hand. In
  // Dart a null field in a record key compares equal to another null, which is
  // what we want — but only if the key really is built from the record.
  group('a null printing', () {
    test('matches another null printing', () {
      final result = plan(
        [row()],
        [entry(id: 7)],
        ImportMergeStrategy.sumQuantities,
      );
      expect(result.quantities, {7: 2});
    });

    test('does not match a real printing', () {
      final result = plan(
        [row()],
        [entry(id: 7, printingId: 4)],
        ImportMergeStrategy.sumQuantities,
      );
      expect(result.newEntries, 1);
      expect(result.quantities, isEmpty);
    });
  });

  // The case a snapshot-based planner gets wrong: it would plan two inserts,
  // and the second would violate the UNIQUE constraint — or, for a null
  // printing where the constraint cannot fire, quietly create a duplicate row.
  group('two identical rows inside the same file', () {
    test('collapse to one entry under keepExisting', () {
      final result = plan(
        [row(), row()],
        const [],
        ImportMergeStrategy.keepExisting,
      );

      expect(result.inserts, hasLength(1));
      expect(result.inserts.single.quantity, 1);
      expect(result.newEntries, 1);
      expect(result.matchedEntries, 1);
    });

    test('add up under sumQuantities', () {
      final result = plan(
        [row(quantity: 2), row(quantity: 3)],
        const [],
        ImportMergeStrategy.sumQuantities,
      );

      expect(result.inserts, hasLength(1));
      expect(result.inserts.single.quantity, 5);
      expect(result.copiesAdded, 5);
    });

    test('with a real printing too, not just the NULL case', () {
      final result = plan(
        [row(printingId: 9), row(printingId: 9)],
        const [],
        ImportMergeStrategy.sumQuantities,
      );
      expect(result.inserts, hasLength(1));
      expect(result.inserts.single.quantity, 2);
    });
  });

  test('untouched existing entries are never rewritten', () {
    final result = plan(
      [row(passcode: '89631139')],
      [entry(id: 7), entry(id: 8, passcode: '89631139', condition: CardCondition.poor)],
      ImportMergeStrategy.sumQuantities,
    );

    expect(result.quantities, isEmpty);
    expect(result.inserts, hasLength(1));
  });

  test('unresolved sets are counted', () {
    final result = plan(
      [row(setUnresolved: true), row(passcode: '89631139')],
      const [],
      ImportMergeStrategy.keepExisting,
    );
    expect(result.setsUnresolved, 1);
  });

  // The confirmation dialog is shown *before* the strategy is chosen, so its
  // numbers must not depend on one.
  test('the counts do not depend on the strategy', () {
    final rows = [row(), row(quantity: 2), row(passcode: '89631139')];
    final existing = [entry(id: 7)];

    final keep = plan(rows, existing, ImportMergeStrategy.keepExisting);
    final sum = plan(rows, existing, ImportMergeStrategy.sumQuantities);

    expect(keep.newEntries, sum.newEntries);
    expect(keep.matchedEntries, sum.matchedEntries);
    expect(keep.setsUnresolved, sum.setsUnresolved);
  });
}
