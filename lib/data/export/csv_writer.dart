/// RFC 4180 field escaping, shared by every CSV this app writes.
///
/// One copy, deliberately: the collection export and the value export are
/// different formats, but they must quote, escape and guard identically or a
/// file that opens cleanly from one would not from the other — and the reader
/// in `collection_csv_parser.dart` is written against exactly these rules.
///
/// Output is `\r\n`-terminated rows; any field holding a comma, double-quote,
/// CR or LF is wrapped in quotes with internal quotes doubled.
library;

String csvRow(List<String> fields) => '${fields.map(csvEscape).join(',')}\r\n';

String csvEscape(String field) {
  final guarded = csvGuardFormula(field);
  final needsQuoting =
      guarded.contains(',') ||
      guarded.contains('"') ||
      guarded.contains('\n') ||
      guarded.contains('\r');
  if (!needsQuoting) return guarded;
  return '"${guarded.replaceAll('"', '""')}"';
}

/// Mitigates CSV formula (DDE) injection: Excel / Google Sheets / LibreOffice
/// interpret a field beginning with `=`, `+`, `-`, `@`, tab or CR as a formula.
/// Prefixing such a field with an apostrophe forces those apps to treat it as
/// literal text. In practice only `name`/`notes` can trigger this — numbers,
/// enum codes and ISO timestamps never start with these characters — and a
/// data consumer (pandas/DuckDB) will simply see a leading `'` on those rare
/// fields.
String csvGuardFormula(String field) {
  if (field.isEmpty) return field;
  const triggers = {'=', '+', '-', '@', '\t', '\r'};
  return triggers.contains(field[0]) ? "'$field" : field;
}

String csvIsoUtc(int epochMs) =>
    DateTime.fromMillisecondsSinceEpoch(epochMs, isUtc: true).toIso8601String();
