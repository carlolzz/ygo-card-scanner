import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/data/export/collection_csv.dart';
import 'package:ygo_scanner/data/export/collection_csv_parser.dart';
import 'package:ygo_scanner/models/card_condition.dart';
import 'package:ygo_scanner/models/card_edition.dart';
import 'package:ygo_scanner/models/collection_entry.dart';
import 'package:ygo_scanner/models/collection_entry_with_card.dart';
import 'package:ygo_scanner/models/printing.dart';
import 'package:ygo_scanner/models/ygo_card.dart';

String _csv(List<String> lines) => '${lines.join('\r\n')}\r\n';

const _header =
    'passcode,name,set_code,set_name,rarity,condition,edition,language,'
    'quantity,notes,created_at,updated_at';

void main() {
  group('parseCollectionCsv', () {
    test('reads a well-formed export', () {
      final result = parseCollectionCsv(
        _csv([
          _header,
          '46986414,Dark Magician,LOB-005,Legend of Blue Eyes,Ultra Rare,'
              'NEAR_MINT,FIRST,EN,2,a note,'
              '2026-01-01T00:00:00.000Z,2026-01-02T00:00:00.000Z',
        ]),
      );

      expect(result.errors, isEmpty);
      final row = result.rows.single;
      expect(row.passcode, '46986414');
      expect(row.name, 'Dark Magician');
      expect(row.setCode, 'LOB-005');
      expect(row.setName, 'Legend of Blue Eyes');
      expect(row.rarity, 'Ultra Rare');
      expect(row.condition, CardCondition.nearMint);
      expect(row.edition, CardEdition.first);
      expect(row.language, 'EN');
      expect(row.quantity, 2);
      expect(row.notes, 'a note');
      expect(row.lineNumber, 2);
    });

    test('empty fields become nulls, not empty strings', () {
      final result = parseCollectionCsv(
        _csv([_header, '46986414,Dark Magician,,,,NEAR_MINT,UNLIMITED,EN,1,,,']),
      );

      final row = result.rows.single;
      expect(row.setCode, isNull);
      expect(row.setName, isNull);
      expect(row.rarity, isNull);
      expect(row.notes, isNull);
    });

    // The whole reason the parser is hand-written rather than a split on commas
    // and newlines: `notes` is free text and can hold both, quoted.
    test('quoted fields may contain commas, quotes and newlines', () {
      final result = parseCollectionCsv(
        _csv([
          _header,
          '46986414,"Magician, Dark",,,,NEAR_MINT,UNLIMITED,EN,1,'
              '"he said ""hi""',
          'on two lines",,',
        ]),
      );

      expect(result.errors, isEmpty);
      final row = result.rows.single;
      expect(row.name, 'Magician, Dark');
      expect(row.notes, 'he said "hi"\non two lines');
    });

    test('accepts bare \\n and bare \\r line endings', () {
      for (final ending in ['\n', '\r', '\r\n']) {
        final result = parseCollectionCsv(
          '$_header${ending}46986414,Dark Magician,,,,NEAR_MINT,UNLIMITED,EN,'
          '3,,,$ending',
        );
        expect(result.rows.single.quantity, 3, reason: 'ending ${ending.length}');
      }
    });

    test('a file with no trailing newline still yields its last row', () {
      final result = parseCollectionCsv(
        '$_header\r\n46986414,Dark Magician,,,,NEAR_MINT,UNLIMITED,EN,1,,,',
      );
      expect(result.rows, hasLength(1));
    });

    test('blank lines are skipped, not reported as errors', () {
      final result = parseCollectionCsv(
        _csv([
          _header,
          '46986414,Dark Magician,,,,NEAR_MINT,UNLIMITED,EN,1,,,',
          '',
          '89631139,Blue-Eyes,,,,MINT,UNLIMITED,EN,1,,,',
        ]),
      );
      expect(result.rows, hasLength(2));
      expect(result.errors, isEmpty);
    });

    // Binding to position would read a rarity as a condition after a
    // spreadsheet round trip.
    test('columns are matched by header name, in any order', () {
      final result = parseCollectionCsv(
        _csv(['quantity,condition,passcode', '4,GOOD,46986414']),
      );

      final row = result.rows.single;
      expect(row.passcode, '46986414');
      expect(row.condition, CardCondition.good);
      expect(row.quantity, 4);
      // Absent columns fall back to the model's own defaults.
      expect(row.edition, CardEdition.unlimited);
      expect(row.language, 'EN');
    });

    test('header matching ignores case and surrounding space', () {
      final result = parseCollectionCsv(
        _csv([' Passcode , CONDITION , Quantity ', '46986414,GOOD,1']),
      );
      expect(result.rows.single.passcode, '46986414');
    });

    group('rejects a file that is not a collection CSV', () {
      test('empty', () {
        expect(
          () => parseCollectionCsv(''),
          throwsA(isA<CsvFormatException>()),
        );
      });

      test('missing a required column', () {
        expect(
          () => parseCollectionCsv(_csv(['passcode,name', '46986414,Dark'])),
          throwsA(isA<CsvFormatException>()),
        );
      });
    });

    // One bad row must not cost the other nine hundred: a collection CSV that
    // has been through a spreadsheet is quite likely to have one stray value.
    group('bad rows are reported, not fatal', () {
      test('an unknown condition', () {
        final result = parseCollectionCsv(
          _csv([
            _header,
            '46986414,Dark Magician,,,,PRISTINE,UNLIMITED,EN,1,,,',
            '89631139,Blue-Eyes,,,,MINT,UNLIMITED,EN,1,,,',
          ]),
        );

        expect(result.rows.single.passcode, '89631139');
        expect(result.errors.single.lineNumber, 2);
      });

      test('a non-numeric or non-positive quantity', () {
        final result = parseCollectionCsv(
          _csv([
            _header,
            '46986414,Dark Magician,,,,MINT,UNLIMITED,EN,lots,,,',
            '89631139,Blue-Eyes,,,,MINT,UNLIMITED,EN,0,,,',
          ]),
        );

        expect(result.rows, isEmpty);
        expect(result.errors, hasLength(2));
      });

      test('a missing passcode', () {
        final result = parseCollectionCsv(
          _csv([_header, ',Dark Magician,,,,MINT,UNLIMITED,EN,1,,,']),
        );
        expect(result.errors, hasLength(1));
      });
    });
  });

  // The cheapest possible proof that the reader and the writer describe one
  // format — including the formula guard, which would otherwise accumulate an
  // apostrophe on every export/import cycle.
  group('round trip through collectionToCsv', () {
    CollectionEntryWithCard row({
      required String passcode,
      required String name,
      Printing? printing,
      String? notes,
    }) => CollectionEntryWithCard(
      entry: CollectionEntry(
        passcode: passcode,
        printingId: printing?.id,
        condition: CardCondition.lightPlayed,
        edition: CardEdition.first,
        language: 'DE',
        quantity: 7,
        notes: notes,
        createdAt: 1,
        updatedAt: 2,
      ),
      card: YgoCard(passcode: passcode, name: name),
      printing: printing,
    );

    test('survives commas, quotes, newlines and a leading formula character', () {
      final source = collectionToCsv([
        row(
          passcode: '46986414',
          name: '=Dark, "Magician"',
          notes: 'line one\nline two',
          printing: const Printing(
            id: 3,
            passcode: '46986414',
            setCode: 'LOB-005',
            setName: 'Legend of Blue Eyes',
            rarity: 'Ultra Rare',
          ),
        ),
      ]);

      final parsed = parseCollectionCsv(source).rows.single;
      expect(parsed.name, '=Dark, "Magician"');
      expect(parsed.notes, 'line one\nline two');
      expect(parsed.setCode, 'LOB-005');
      expect(parsed.rarity, 'Ultra Rare');
      expect(parsed.condition, CardCondition.lightPlayed);
      expect(parsed.edition, CardEdition.first);
      expect(parsed.language, 'DE');
      expect(parsed.quantity, 7);
    });

    test('an entry with no printing round-trips to nulls', () {
      final source = collectionToCsv([
        row(passcode: '89631139', name: 'Blue-Eyes White Dragon'),
      ]);

      final parsed = parseCollectionCsv(source).rows.single;
      expect(parsed.setCode, isNull);
      expect(parsed.setName, isNull);
      expect(parsed.rarity, isNull);
      expect(parsed.notes, isNull);
    });

    test('an empty collection exports a header the parser accepts', () {
      final result = parseCollectionCsv(collectionToCsv(const []));
      expect(result.rows, isEmpty);
      expect(result.errors, isEmpty);
    });
  });
}
