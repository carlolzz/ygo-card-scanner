import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/data/export/collection_csv.dart';
import 'package:ygo_scanner/models/card_condition.dart';
import 'package:ygo_scanner/models/card_edition.dart';
import 'package:ygo_scanner/models/collection_entry.dart';
import 'package:ygo_scanner/models/collection_entry_with_card.dart';
import 'package:ygo_scanner/models/printing.dart';
import 'package:ygo_scanner/models/ygo_card.dart';

CollectionEntryWithCard _row({
  required String passcode,
  required String name,
  Printing? printing,
  CardCondition condition = CardCondition.nearMint,
  CardEdition edition = CardEdition.unlimited,
  String language = 'EN',
  int quantity = 1,
  String? notes,
  int createdAt = 0,
  int updatedAt = 0,
}) {
  return CollectionEntryWithCard(
    entry: CollectionEntry(
      passcode: passcode,
      printingId: printing?.id,
      condition: condition,
      edition: edition,
      language: language,
      quantity: quantity,
      notes: notes,
      createdAt: createdAt,
      updatedAt: updatedAt,
    ),
    card: YgoCard(passcode: passcode, name: name, type: 'Normal Monster'),
    printing: printing,
  );
}

void main() {
  test('empty collection still emits the header row', () {
    expect(collectionToCsv([]), '${collectionCsvHeader.join(',')}\r\n');
  });

  test('serializes columns with enum db values and UTC ISO timestamps', () {
    final csv = collectionToCsv([
      _row(
        passcode: '89631139',
        name: 'Blue-Eyes White Dragon',
        printing: const Printing(
          id: 1,
          passcode: '89631139',
          setCode: 'LOB-EN001',
          setName: 'Legend of Blue Eyes White Dragon',
          rarity: 'Ultra Rare',
        ),
        condition: CardCondition.nearMint,
        edition: CardEdition.unlimited,
        language: 'DE',
        quantity: 2,
        notes: 'nice',
        createdAt: 0,
        updatedAt: 0,
      ),
    ]);
    final lines = csv.split('\r\n');
    expect(
      lines[1],
      '89631139,Blue-Eyes White Dragon,LOB-EN001,'
      'Legend of Blue Eyes White Dragon,Ultra Rare,NEAR_MINT,UNLIMITED,DE,2,'
      'nice,1970-01-01T00:00:00.000Z,1970-01-01T00:00:00.000Z',
    );
  });

  test('a null printing leaves the set columns empty', () {
    final line = collectionToCsv([
      _row(passcode: '46986414', name: 'Dark Magician'),
    ]).split('\r\n')[1];
    // passcode,name,set_code,set_name,rarity,...
    expect(line.startsWith('46986414,Dark Magician,,,,'), isTrue);
  });

  test('quotes and escapes commas, quotes and newlines (RFC 4180)', () {
    final csv = collectionToCsv([
      _row(
        passcode: '00000001',
        name: 'A, "quoted" name',
        notes: 'line1\nline2',
      ),
    ]);
    // A comma and internal quotes force quoting; the quotes double.
    expect(csv, contains('"A, ""quoted"" name"'));
    // A field with a newline is quoted (and its newline is preserved verbatim).
    expect(csv, contains('"line1\nline2"'));
  });
}
