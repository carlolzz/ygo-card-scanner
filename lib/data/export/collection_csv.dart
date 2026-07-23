import '../../models/collection_entry_with_card.dart';

/// Pure, offline-testable CSV serialization of collection rows.
///
/// Kept free of file I/O so the escaping can be unit-tested without a device.
/// Output is RFC 4180: a header row, `\r\n` line endings, and any field holding
/// a comma, double-quote, CR or LF wrapped in quotes with internal quotes
/// doubled. Enums serialize via their `toDb()` value (the same SCREAMING_SNAKE
/// stored in the database); timestamps as UTC ISO-8601.
const List<String> collectionCsvHeader = [
  'passcode',
  'name',
  'set_code',
  'set_name',
  'rarity',
  'condition',
  'edition',
  'language',
  'quantity',
  'notes',
  'created_at',
  'updated_at',
];

String collectionToCsv(List<CollectionEntryWithCard> rows) {
  final buffer = StringBuffer();
  buffer.write(_row(collectionCsvHeader));
  for (final row in rows) {
    final entry = row.entry;
    final printing = row.printing;
    buffer.write(
      _row([
        entry.passcode,
        row.card.name,
        printing?.setCode ?? '',
        printing?.setName ?? '',
        printing?.rarity ?? '',
        entry.condition.toDb(),
        entry.edition.toDb(),
        entry.language,
        '${entry.quantity}',
        entry.notes ?? '',
        _isoUtc(entry.createdAt),
        _isoUtc(entry.updatedAt),
      ]),
    );
  }
  return buffer.toString();
}

String _row(List<String> fields) => '${fields.map(_escape).join(',')}\r\n';

String _escape(String field) {
  final needsQuoting =
      field.contains(',') ||
      field.contains('"') ||
      field.contains('\n') ||
      field.contains('\r');
  if (!needsQuoting) return field;
  return '"${field.replaceAll('"', '""')}"';
}

String _isoUtc(int epochMs) =>
    DateTime.fromMillisecondsSinceEpoch(epochMs, isUtc: true).toIso8601String();
