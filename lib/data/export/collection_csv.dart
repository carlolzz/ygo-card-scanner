import '../../models/collection_entry_with_card.dart';
import 'csv_writer.dart';

/// Pure, offline-testable CSV serialization of collection rows.
///
/// Kept free of file I/O so the escaping can be unit-tested without a device.
/// Output is RFC 4180 — see `csv_writer.dart` for the quoting and formula-guard
/// rules, which this format shares with the value export. Enums serialize via
/// their `toDb()` value (the same SCREAMING_SNAKE stored in the database);
/// timestamps as UTC ISO-8601.
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
  buffer.write(csvRow(collectionCsvHeader));
  for (final row in rows) {
    final entry = row.entry;
    final printing = row.printing;
    buffer.write(
      csvRow([
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
        csvIsoUtc(entry.createdAt),
        csvIsoUtc(entry.updatedAt),
      ]),
    );
  }
  return buffer.toString();
}
