import '../../models/card_condition.dart';
import '../../models/card_edition.dart';
import 'collection_csv.dart';

/// One parsed CSV row, still in the file's own vocabulary: a set is a
/// code/name/rarity triple, not a `printings.id`, because a file written on
/// another device (or by hand, or by a spreadsheet) knows nothing about this
/// database's row ids. Resolving that triple to a real printing is the
/// importer's job, not the parser's.
class CsvCollectionRow {
  const CsvCollectionRow({
    required this.lineNumber,
    required this.passcode,
    required this.name,
    required this.setCode,
    required this.setName,
    required this.rarity,
    required this.condition,
    required this.edition,
    required this.language,
    required this.quantity,
    required this.notes,
  });

  /// 1-based line in the source file, so a rejected row can be pointed at.
  final int lineNumber;

  final String passcode;
  final String name;
  final String? setCode;
  final String? setName;
  final String? rarity;
  final CardCondition condition;
  final CardEdition edition;
  final String language;
  final int quantity;
  final String? notes;
}

/// A row that could not be turned into a [CsvCollectionRow].
class CsvRowError {
  const CsvRowError(this.lineNumber, this.message);

  final int lineNumber;
  final String message;

  @override
  String toString() => 'line $lineNumber: $message';
}

/// The outcome of parsing a whole file: what could be read, and what could not.
///
/// Deliberately not an exception per bad row. A collection CSV that has been
/// through a spreadsheet is quite likely to have one row with a stray value in
/// it, and refusing the entire import over that is worse than importing the
/// other nine hundred and saying which one was dropped.
class CsvParseResult {
  const CsvParseResult({required this.rows, required this.errors});

  final List<CsvCollectionRow> rows;
  final List<CsvRowError> errors;
}

/// Thrown when the file is not a collection CSV at all — as opposed to a
/// collection CSV with some bad rows, which [CsvParseResult] reports instead.
class CsvFormatException implements Exception {
  const CsvFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Parses the export format written by [collectionToCsv].
///
/// The reader lives beside the writer on purpose: they are one format, and the
/// escaping rules (quoted fields, doubled quotes, embedded newlines, the
/// formula guard) have to agree exactly. A round trip through both is the
/// cheapest possible proof that they do.
///
/// **Columns are matched by header name, not position.** A file that has been
/// opened in a spreadsheet and saved again may reorder or add columns, and
/// binding to position would then silently read the rarity as a condition.
/// Only `passcode`, `condition` and `quantity` are actually required; the rest
/// default, so a hand-written three-column file still imports.
CsvParseResult parseCollectionCsv(String source) {
  final records = _splitRecords(source);
  if (records.isEmpty) {
    throw const CsvFormatException('The file is empty.');
  }

  final header = [
    for (final field in records.first.fields) field.trim().toLowerCase(),
  ];
  final index = <String, int>{
    for (var i = 0; i < header.length; i++) header[i]: i,
  };
  for (final required in const ['passcode', 'condition', 'quantity']) {
    if (!index.containsKey(required)) {
      throw CsvFormatException(
        'Missing the "$required" column. Expected a collection CSV with the '
        'columns: ${collectionCsvHeader.join(', ')}.',
      );
    }
  }

  final rows = <CsvCollectionRow>[];
  final errors = <CsvRowError>[];
  for (final record in records.skip(1)) {
    // A trailing newline yields one empty record; so does a blank separator
    // line left by an editor. Neither is an error.
    if (record.fields.every((field) => field.trim().isEmpty)) continue;

    String? field(String column) {
      final at = index[column];
      if (at == null || at >= record.fields.length) return null;
      final value = _unguardFormula(record.fields[at].trim());
      return value.isEmpty ? null : value;
    }

    try {
      final passcode = field('passcode');
      if (passcode == null) {
        throw const FormatException('no passcode');
      }
      final quantity = int.tryParse(field('quantity') ?? '1');
      if (quantity == null || quantity <= 0) {
        throw FormatException('quantity "${field('quantity')}" is not a '
            'positive whole number');
      }
      rows.add(
        CsvCollectionRow(
          lineNumber: record.lineNumber,
          passcode: passcode,
          name: field('name') ?? '',
          setCode: field('set_code'),
          setName: field('set_name'),
          rarity: field('rarity'),
          // `fromDb` throws on an unknown value; that is the point — an
          // unrecognised grade must not be silently coerced to Near Mint, since
          // condition is the single most consequential field on a row.
          condition: CardCondition.fromDb(field('condition') ?? ''),
          edition: CardEdition.fromDb(field('edition') ?? 'UNLIMITED'),
          language: field('language') ?? 'EN',
          quantity: quantity,
          notes: field('notes'),
        ),
      );
    } catch (error) {
      errors.add(CsvRowError(record.lineNumber, _describe(error)));
    }
  }
  return CsvParseResult(rows: rows, errors: errors);
}

String _describe(Object error) => switch (error) {
  FormatException(:final message) when message.isNotEmpty => message,
  ArgumentError(:final message) => '$message',
  _ => '$error',
};

class _Record {
  const _Record(this.lineNumber, this.fields);

  final int lineNumber;
  final List<String> fields;
}

/// Splits RFC 4180 text into records of fields.
///
/// Written by hand rather than with a split on `,` and `\n`, because a `notes`
/// field is free text: it can legitimately contain both, quoted. Accepts `\r\n`
/// (what [collectionToCsv] writes), bare `\n` (what most other tools write) and
/// bare `\r`, since a file that has been through a spreadsheet on another
/// platform may carry any of the three.
List<_Record> _splitRecords(String source) {
  final records = <_Record>[];
  var fields = <String>[];
  final field = StringBuffer();
  var quoted = false;
  var line = 1;
  var recordLine = 1;
  var pending = false;

  void endField() {
    fields.add(field.toString());
    field.clear();
    pending = true;
  }

  void endRecord() {
    endField();
    records.add(_Record(recordLine, fields));
    fields = <String>[];
    pending = false;
    recordLine = line;
  }

  for (var i = 0; i < source.length; i++) {
    final char = source[i];
    if (quoted) {
      if (char == '"') {
        // A doubled quote inside a quoted field is one literal quote.
        if (i + 1 < source.length && source[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else if (char == '\r') {
        // Normalise a line ending *inside* a quoted field to `\n`. Strictly,
        // RFC 4180 says a quoted field's bytes are its content — but the only
        // multi-line field here is `notes`, which ends up in a Flutter `Text`,
        // and a `\r` from a Windows editor is that editor's line ending rather
        // than something the user typed. The writer emits `\n`, so a round trip
        // through both is unaffected either way.
        if (i + 1 < source.length && source[i + 1] == '\n') i++;
        line++;
        field.write('\n');
      } else {
        if (char == '\n') line++;
        field.write(char);
      }
      continue;
    }
    switch (char) {
      case '"':
        quoted = true;
      case ',':
        endField();
      case '\r':
        // Swallow the \n of a \r\n pair rather than ending a second record.
        if (i + 1 < source.length && source[i + 1] == '\n') i++;
        line++;
        endRecord();
        recordLine = line;
      case '\n':
        line++;
        endRecord();
        recordLine = line;
      default:
        field.write(char);
        pending = true;
    }
  }
  // A file not ending in a newline still has a final record.
  if (pending || fields.isNotEmpty || field.isNotEmpty) endRecord();
  return records;
}

/// Undoes [collectionToCsv]'s formula guard, so a round trip is lossless.
///
/// The writer prefixes a field starting with `=`, `+`, `-`, `@`, tab or CR with
/// an apostrophe so spreadsheets treat it as text. Without this the name of a
/// re-imported card would slowly accumulate apostrophes across export/import
/// cycles.
String _unguardFormula(String field) {
  if (field.length < 2 || field[0] != "'") return field;
  const triggers = {'=', '+', '-', '@', '\t', '\r'};
  return triggers.contains(field[1]) ? field.substring(1) : field;
}
