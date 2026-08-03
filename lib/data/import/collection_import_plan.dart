import '../../models/card_condition.dart';
import '../../models/card_edition.dart';
import '../../models/collection_entry.dart';

/// What to do when an imported entry already exists in the collection.
///
/// Both rules keep a *single* row — they differ only in the number on it. The
/// distinction matters because a CSV can be either of two things and the app
/// cannot tell them apart: a backup of this same collection (re-importing it
/// must not double every count) or a second collection being folded in (where
/// the copies really do add up).
enum ImportMergeStrategy {
  /// Leave the existing entry exactly as it is; the imported row is not
  /// written. Re-importing this app's own export is then a no-op.
  keepExisting,

  /// Add the imported quantity to the existing one.
  sumQuantities,
}

/// A parsed CSV row after its passcode and set have been resolved against the
/// local database — the form the planner works in.
class ResolvedImportRow {
  const ResolvedImportRow({
    required this.passcode,
    required this.printingId,
    required this.condition,
    required this.edition,
    required this.language,
    required this.quantity,
    this.notes,
    this.setUnresolved = false,
  });

  final String passcode;

  /// The matched `printings.id`, or null for "no specific set" — either the row
  /// carried no set at all, or it named one this database does not have.
  final int? printingId;

  final CardCondition condition;
  final CardEdition edition;
  final String language;
  final int quantity;
  final String? notes;

  /// The row named a set that could not be matched, so it will be logged
  /// without one. Reported to the user rather than silently dropped, because a
  /// set is exactly the sort of detail someone imports a CSV to preserve.
  final bool setUnresolved;

  /// The `collection_entries` UNIQUE key. Dart records compare structurally, so
  /// this works directly as a map key — including the null `printingId` case,
  /// which SQLite itself treats as distinct-from-everything and which every
  /// other write path in this DAO has to special-case by hand.
  (String, int?, String, String, String) get key =>
      (passcode, printingId, condition.toDb(), edition.toDb(), language);
}

/// The outcome of planning an import: exactly what to write, plus the counts
/// the confirmation dialog reports.
class CollectionImportPlan {
  const CollectionImportPlan({
    required this.inserts,
    required this.quantities,
    required this.newEntries,
    required this.matchedEntries,
    required this.copiesAdded,
    required this.setsUnresolved,
  });

  /// Rows that exist nowhere yet.
  final List<CollectionEntry> inserts;

  /// Existing entry id -> its new **absolute** quantity.
  final Map<int, int> quantities;

  /// How many entries the import will create.
  final int newEntries;

  /// How many imported rows landed on an entry that already existed — the
  /// number the merge question is actually about.
  final int matchedEntries;

  /// Total copies the collection will gain. Zero-for-matches under
  /// [ImportMergeStrategy.keepExisting] is the whole point of that rule.
  final int copiesAdded;

  /// Rows naming a set this database could not match; imported without it.
  final int setsUnresolved;

  bool get isEmpty => inserts.isEmpty && quantities.isEmpty;
}

/// Decides what an import will do, without touching the database.
///
/// Pure so the rule that defines "the same entry" can be tested exhaustively on
/// the host — including the cases that are easy to get wrong and silent when
/// wrong: a null printing (SQLite treats every NULL as distinct under the
/// UNIQUE constraint), and **two identical rows inside the same file**.
///
/// That second case is why this folds rows into a working set as it goes rather
/// than matching each row against an unchanging snapshot. A file holding two
/// separate "Toon Cannon Soldier, no set, NM, EN, 1" rows describes one entry,
/// not two; matching against a snapshot would plan two inserts, and the second
/// would either violate the UNIQUE constraint or (for a null printing, where
/// the constraint cannot fire) quietly create a duplicate row the collection
/// screen would then show twice.
///
/// [existing] is the collection's current entries for the passcodes involved.
/// The counts it returns do not depend on [strategy] — only the quantities do.
CollectionImportPlan planCollectionImport({
  required List<ResolvedImportRow> rows,
  required List<CollectionEntry> existing,
  required ImportMergeStrategy strategy,
  required int now,
}) {
  // The working set: every entry that exists or will exist, by UNIQUE key.
  final byKey = <(String, int?, String, String, String), _Pending>{
    for (final entry in existing)
      (
        entry.passcode,
        entry.printingId,
        entry.condition.toDb(),
        entry.edition.toDb(),
        entry.language,
      ): _Pending.existing(entry),
  };

  var newEntries = 0;
  var matchedEntries = 0;
  var copiesAdded = 0;
  var setsUnresolved = 0;

  for (final row in rows) {
    if (row.setUnresolved) setsUnresolved++;
    final pending = byKey[row.key];
    if (pending == null) {
      byKey[row.key] = _Pending.inserted(
        CollectionEntry(
          passcode: row.passcode,
          printingId: row.printingId,
          condition: row.condition,
          edition: row.edition,
          language: row.language,
          quantity: row.quantity,
          notes: row.notes,
          createdAt: now,
          updatedAt: now,
        ),
      );
      newEntries++;
      copiesAdded += row.quantity;
      continue;
    }
    matchedEntries++;
    if (strategy == ImportMergeStrategy.sumQuantities) {
      pending.quantity += row.quantity;
      copiesAdded += row.quantity;
    }
    // keepExisting: the row is deliberately dropped. Note this applies to a
    // match against a *pending insert* too — two identical new rows collapse
    // into one entry, which is what "merged as one entry, quantity unchanged"
    // means when both sides are new.
  }

  final inserts = <CollectionEntry>[];
  final quantities = <int, int>{};
  for (final pending in byKey.values) {
    if (pending.entry.id == null) {
      inserts.add(pending.entry.copyWith(quantity: pending.quantity));
    } else if (pending.quantity != pending.entry.quantity) {
      quantities[pending.entry.id!] = pending.quantity;
    }
  }

  return CollectionImportPlan(
    inserts: inserts,
    quantities: quantities,
    newEntries: newEntries,
    matchedEntries: matchedEntries,
    copiesAdded: copiesAdded,
    setsUnresolved: setsUnresolved,
  );
}

/// One entry in the working set, with a quantity that accumulates as rows are
/// folded in.
class _Pending {
  _Pending.existing(this.entry) : quantity = entry.quantity;
  _Pending.inserted(this.entry) : quantity = entry.quantity;

  final CollectionEntry entry;
  int quantity;
}
