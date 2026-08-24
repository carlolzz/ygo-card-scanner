import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/data/export/collection_csv.dart';
import 'package:ygo_scanner/data/export/collection_csv_parser.dart';
import 'package:ygo_scanner/data/export/collection_value_csv.dart';
import 'package:ygo_scanner/data/repositories/price_repository.dart';
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

    group('timestamps', () {
      CsvCollectionRow parseWith(String created, String updated) =>
          parseCollectionCsv(
            _csv([
              _header,
              '46986414,Dark Magician,,,,NEAR_MINT,UNLIMITED,EN,1,,'
                  '$created,$updated',
            ]),
          ).rows.single;

      test('are read as epoch milliseconds', () {
        final row = parseWith(
          '2026-01-01T00:00:00.000Z',
          '2026-01-02T00:00:00.000Z',
        );

        expect(row.createdAt, DateTime.utc(2026).millisecondsSinceEpoch);
        expect(row.updatedAt, DateTime.utc(2026, 1, 2).millisecondsSinceEpoch);
      });

      test('a bare epoch integer is accepted too', () {
        // A spreadsheet is quite capable of turning a date column into a
        // number on the way through.
        expect(parseWith('1700000000000', '').createdAt, 1700000000000);
      });

      test('an unreadable date is null, and does NOT reject the row', () {
        // A date is metadata about a card, not what the card is. The importer
        // falls back to the time of the import, which is what every row used
        // to get unconditionally.
        final result = parseCollectionCsv(
          _csv([
            _header,
            '46986414,Dark Magician,,,,NEAR_MINT,UNLIMITED,EN,1,,'
                '24/08/2026 14:03,not a date',
          ]),
        );

        expect(result.errors, isEmpty);
        expect(result.rows.single.createdAt, isNull);
        expect(result.rows.single.updatedAt, isNull);
      });

      test('a file without the columns parses, with null dates', () {
        final result = parseCollectionCsv(
          _csv(['passcode,condition,quantity', '46986414,NEAR_MINT,1']),
        );

        expect(result.errors, isEmpty);
        expect(result.rows.single.createdAt, isNull);
      });
    });

    test('empty fields become nulls, not empty strings', () {
      final result = parseCollectionCsv(
        _csv([
          _header,
          '46986414,Dark Magician,,,,NEAR_MINT,UNLIMITED,EN,1,,,',
        ]),
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
        expect(
          result.rows.single.quantity,
          3,
          reason: 'ending ${ending.length}',
        );
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

    test(
      'survives commas, quotes, newlines and a leading formula character',
      () {
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
      },
    );

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

    // The reason the parser reads these columns at all: without it, every
    // imported entry was stamped with the instant of the import, so "Date
    // added" had nothing to order by and flipping its direction changed
    // nothing on screen.
    test('the dates survive, so the order the cards were logged in does', () {
      final first = DateTime.utc(2024, 3, 1, 9, 30);
      final second = DateTime.utc(2026, 8, 24, 14);
      final source = collectionToCsv([
        CollectionEntryWithCard(
          entry: CollectionEntry(
            passcode: '46986414',
            condition: CardCondition.nearMint,
            edition: CardEdition.unlimited,
            language: 'EN',
            quantity: 1,
            createdAt: first.millisecondsSinceEpoch,
            updatedAt: second.millisecondsSinceEpoch,
          ),
          card: const YgoCard(passcode: '46986414', name: 'Dark Magician'),
        ),
      ]);

      final parsed = parseCollectionCsv(source).rows.single;
      expect(parsed.createdAt, first.millisecondsSinceEpoch);
      expect(parsed.updatedAt, second.millisecondsSinceEpoch);
    });

    test('an empty collection exports a header the parser accepts', () {
      final result = parseCollectionCsv(collectionToCsv(const []));
      expect(result.rows, isEmpty);
      expect(result.errors, isEmpty);
    });

    // The other file this app writes. It shares a `passcode` column and nothing
    // else that matters, so it must be refused outright rather than read
    // half-way into rows with a defaulted grade — which is exactly what the
    // required-column check buys, and why `condition` is on that list.
    test('the value breakdown is rejected, not half-imported', () {
      final valueCsv = collectionValueToCsv(
        CollectionValue(
          cardmarketEur: 1.2,
          tcgplayerUsd: 2.5,
          pricedCards: 1,
          unpricedCards: 0,
          asOf: DateTime.utc(2026, 8, 17),
          lines: [
            CollectionValueLine(
              passcode: '46986414',
              name: 'Dark Magician',
              printingId: null,
              setCode: null,
              setName: null,
              rarity: null,
              quantity: 2,
              cardmarketEur: 1.2,
              tcgplayerUsd: 2.5,
              usdBasis: PriceBasis.cardFloor,
              pricedAt: DateTime.utc(2026, 8, 17),
            ),
          ],
        ),
      );

      expect(
        () => parseCollectionCsv(valueCsv),
        throwsA(
          isA<CsvFormatException>().having(
            (e) => e.message,
            'message',
            contains('condition'),
          ),
        ),
      );
    });
  });
}
