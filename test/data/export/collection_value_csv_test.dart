import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/data/export/collection_value_csv.dart';
import 'package:ygo_scanner/data/repositories/price_repository.dart';

CollectionValueLine _line({
  String passcode = '89631139',
  String name = 'Blue-Eyes White Dragon',
  int quantity = 1,
  double? cardmarketEur,
  double? tcgplayerUsd,
  DateTime? pricedAt,
}) => CollectionValueLine(
  passcode: passcode,
  name: name,
  quantity: quantity,
  cardmarketEur: cardmarketEur,
  tcgplayerUsd: tcgplayerUsd,
  pricedAt: pricedAt,
);

CollectionValue _value(List<CollectionValueLine> lines) => CollectionValue(
  cardmarketEur: 0,
  tcgplayerUsd: 0,
  pricedCards: 0,
  unpricedCards: 0,
  asOf: null,
  lines: lines,
);

/// The data rows, without the header.
List<String> _rows(String csv) =>
    csv.split('\r\n').skip(1).where((l) => l.isNotEmpty).toList();

void main() {
  test('an empty breakdown still emits the header row', () {
    expect(
      collectionValueToCsv(_value(const [])),
      '${collectionValueCsvHeader.join(',')}\r\n',
    );
  });

  test('writes unit prices, line totals and the price date', () {
    final csv = collectionValueToCsv(
      _value([
        _line(
          quantity: 3,
          cardmarketEur: 1.2,
          tcgplayerUsd: 2.5,
          pricedAt: DateTime.utc(2026, 8, 17, 9),
        ),
      ]),
    );

    expect(_rows(csv).single, [
      '89631139',
      'Blue-Eyes White Dragon',
      '3',
      '1.20',
      '2.50',
      '3.60',
      '7.50',
      '2026-08-17T09:00:00.000Z',
    ].join(','));
  });

  // A local timestamp still lands in the file as UTC, like every other
  // timestamp this app exports.
  test('the price date is written in UTC', () {
    final at = DateTime.utc(2026, 8, 17, 9).toLocal();
    final csv = collectionValueToCsv(
      _value([_line(cardmarketEur: 1, pricedAt: at)]),
    );

    expect(_rows(csv).single, endsWith(',2026-08-17T09:00:00.000Z'));
  });

  // The point of keeping unpriced cards in the breakdown: they are the detail
  // behind the "N cards have no price" line, and a zero would read as a card
  // that is genuinely worthless rather than one nobody quoted.
  test('an unknown price is an empty cell, never a zero', () {
    final csv = collectionValueToCsv(_value([_line(quantity: 4)]));

    expect(_rows(csv).single, '89631139,Blue-Eyes White Dragon,4,,,,,');
  });

  test('one currency can be missing while the other is priced', () {
    final csv = collectionValueToCsv(
      _value([
        _line(
          quantity: 2,
          tcgplayerUsd: 5,
          pricedAt: DateTime.utc(2026, 8, 17),
        ),
      ]),
    );

    final fields = _rows(csv).single.split(',');
    expect(fields[3], '', reason: 'no Cardmarket figure');
    expect(fields[4], '5.00');
    expect(fields[5], '', reason: 'and so no Cardmarket line total');
    expect(fields[6], '10.00');
  });

  test('lines are written in the order they arrive', () {
    final csv = collectionValueToCsv(
      _value([
        _line(passcode: '89631139', name: 'Blue-Eyes White Dragon'),
        _line(passcode: '46986414', name: 'Dark Magician'),
      ]),
    );

    expect(_rows(csv).map((l) => l.split(',').first), [
      '89631139',
      '46986414',
    ]);
  });

  // Both exports go through `csv_writer.dart`, and these two cases are what
  // prove it: a name that needs quoting and one that needs the formula guard
  // are handled here without this file knowing the rules.
  group('escaping is the shared writer\'s', () {
    test('a name containing a comma is quoted', () {
      final csv = collectionValueToCsv(
        _value([_line(name: 'Dark Magician, the Dragon Knight')]),
      );

      expect(_rows(csv).single, contains('"Dark Magician, the Dragon Knight"'));
    });

    test('a name starting with a formula trigger is guarded', () {
      final csv = collectionValueToCsv(_value([_line(name: '=cmd()')]));

      expect(_rows(csv).single, contains("'=cmd()"));
    });
  });
}
