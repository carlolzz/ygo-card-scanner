import 'dart:io';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sqflite/sqflite.dart';

import '../../models/printing.dart';
import '../db/dao/card_dao.dart';
import '../db/dao/collection_dao.dart';
import '../db/dao/printing_dao.dart';
import '../db/database.dart';
import '../export/collection_csv_parser.dart';
import 'collection_import_plan.dart';

part 'collection_importer.g.dart';

/// What an import *would* do, computed before anything is written.
///
/// Carries the resolved rows as well as the counts, so confirming does not have
/// to re-read and re-parse the file — the user has already been shown numbers
/// derived from these exact rows, and re-reading could quietly produce
/// different ones.
class CollectionImportPreview {
  const CollectionImportPreview({
    required this.rows,
    required this.plan,
    required this.errors,
    required this.unknownCards,
    required this.totalRows,
  });

  final List<ResolvedImportRow> rows;

  /// Planned under [ImportMergeStrategy.keepExisting]; only the *quantities* it
  /// carries depend on the strategy, never the counts, so this is a valid
  /// source for everything the dialog shows.
  final CollectionImportPlan plan;

  /// Rows that could not be parsed at all, with their line numbers.
  final List<CsvRowError> errors;

  /// Rows naming a passcode this database has no card for. They cannot be
  /// imported: `collection_entries.passcode` is a foreign key, so inserting one
  /// would be rejected — and the row would be unusable anyway, with no name,
  /// artwork or type to show. Usually means the card database needs a re-sync.
  final int unknownCards;

  /// Data rows found in the file, before any of them were rejected.
  final int totalRows;

  int get skipped => errors.length + unknownCards;

  bool get hasAnythingToImport => !plan.isEmpty || plan.matchedEntries > 0;
}

/// What an import actually did.
class CollectionImportResult {
  const CollectionImportResult({
    required this.entriesAdded,
    required this.entriesMerged,
    required this.copiesAdded,
    required this.skipped,
  });

  final int entriesAdded;
  final int entriesMerged;
  final int copiesAdded;
  final int skipped;
}

/// Reads a collection CSV and folds it into the collection already on the
/// device.
///
/// Two-phase by design: [preview] reads and resolves without writing anything,
/// and [apply] writes only what the user confirmed. The merge question cannot be
/// answered sensibly without knowing how many entries it is about, and a
/// collection is not something to overwrite on a guess.
class CollectionImporter {
  CollectionImporter(this._db);

  final Database _db;

  /// Reads a file the user picked. Split from [preview] so the parsing and
  /// planning stay testable without a filesystem.
  Future<CollectionImportPreview> previewFile(String path) async =>
      preview(await File(path).readAsString());

  /// Parses [csv], resolves every row against the local card and printing
  /// tables, and plans the result. Throws [CsvFormatException] if the file is
  /// not a collection CSV at all.
  Future<CollectionImportPreview> preview(String csv) async {
    final parsed = parseCollectionCsv(csv);

    // Two bulk reads rather than two per row: a real collection CSV is
    // hundreds of rows, and each round trip crosses the sqflite isolate.
    final passcodes = {for (final row in parsed.rows) row.passcode}.toList();
    final known = {
      for (final card in await CardDao(_db).getByPasscodes(passcodes))
        card.passcode,
    };
    final printings = <String, List<Printing>>{};
    for (final printing in await PrintingDao(_db).getForPasscodes(passcodes)) {
      (printings[printing.passcode] ??= []).add(printing);
    }

    final resolved = <ResolvedImportRow>[];
    var unknownCards = 0;
    for (final row in parsed.rows) {
      if (!known.contains(row.passcode)) {
        unknownCards++;
        continue;
      }
      resolved.add(
        resolveImportRow(row, printings[row.passcode] ?? const []),
      );
    }

    return CollectionImportPreview(
      rows: resolved,
      plan: await _plan(resolved, ImportMergeStrategy.keepExisting),
      errors: parsed.errors,
      unknownCards: unknownCards,
      totalRows: parsed.rows.length + parsed.errors.length,
    );
  }

  /// Writes the previewed rows under the chosen [strategy].
  ///
  /// Re-plans against a fresh read rather than reusing the preview's plan: the
  /// counts shown to the user are strategy-independent, but the quantities are
  /// not, and re-planning is both the cheaper and the more honest way to get
  /// them than keeping two plans around.
  Future<CollectionImportResult> apply(
    CollectionImportPreview preview,
    ImportMergeStrategy strategy, {
    DateTime? now,
  }) async {
    final at = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final plan = await _plan(preview.rows, strategy, now: at);
    await CollectionDao(_db).applyImport(
      inserts: plan.inserts,
      quantities: plan.quantities,
      updatedAt: at,
    );
    return CollectionImportResult(
      entriesAdded: plan.newEntries,
      entriesMerged: plan.matchedEntries,
      copiesAdded: plan.copiesAdded,
      skipped: preview.skipped,
    );
  }

  Future<CollectionImportPlan> _plan(
    List<ResolvedImportRow> rows,
    ImportMergeStrategy strategy, {
    int? now,
  }) async {
    final existing = await CollectionDao(_db).getEntriesForPasscodes(
      {for (final row in rows) row.passcode}.toList(),
    );
    return planCollectionImport(
      rows: rows,
      existing: existing,
      strategy: strategy,
      now: now ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}

/// Resolves one parsed row's set columns to a `printings.id`.
///
/// A CSV names a set the way a human does — a code, a name, a rarity — while
/// the collection stores a row id, and the two have to be reconciled against
/// whatever printings this database happens to know for that card.
///
/// Tried in order of how strongly each identifies a printing: the
/// `(set_code, rarity)` pair is the `printings` UNIQUE key, so it is exact;
/// `(set_name, rarity)` is the same thing for a file that carries names but not
/// codes; then either alone. Comparison is case- and space-insensitive, because
/// the file may well have been through a spreadsheet.
///
/// No match means the row is imported **without** a set rather than dropped —
/// losing the set is bad, losing the card is worse — and is flagged so the
/// import summary can say how often it happened.
ResolvedImportRow resolveImportRow(
  CsvCollectionRow row,
  List<Printing> printings,
) {
  final hasSet =
      row.setCode != null || row.setName != null || row.rarity != null;
  final match = hasSet ? _matchPrinting(row, printings) : null;

  return ResolvedImportRow(
    passcode: row.passcode,
    printingId: match?.id,
    condition: row.condition,
    edition: row.edition,
    language: row.language,
    quantity: row.quantity,
    notes: row.notes,
    setUnresolved: hasSet && match == null,
  );
}

Printing? _matchPrinting(CsvCollectionRow row, List<Printing> printings) {
  final code = _norm(row.setCode);
  final name = _norm(row.setName);
  final rarity = _norm(row.rarity);

  Printing? first(bool Function(Printing) test) {
    for (final printing in printings) {
      if (test(printing)) return printing;
    }
    return null;
  }

  if (code != null && rarity != null) {
    final hit = first(
      (p) => _norm(p.setCode) == code && _norm(p.rarity) == rarity,
    );
    if (hit != null) return hit;
  }
  if (name != null && rarity != null) {
    final hit = first(
      (p) => _norm(p.setName) == name && _norm(p.rarity) == rarity,
    );
    if (hit != null) return hit;
  }
  if (code != null) {
    final hit = first((p) => _norm(p.setCode) == code);
    if (hit != null) return hit;
  }
  if (name != null) {
    final hit = first((p) => _norm(p.setName) == name);
    if (hit != null) return hit;
  }
  return null;
}

String? _norm(String? value) {
  final trimmed = value?.trim().toLowerCase();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

@riverpod
Future<CollectionImporter> collectionImporter(Ref ref) async =>
    CollectionImporter(await ref.watch(appDatabaseProvider.future));
