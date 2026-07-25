import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/models/printing.dart';

const _mirrorForceMetalRaiders = Printing(
  id: 1,
  passcode: '44095762',
  setCode: 'MRD-EN094',
  setName: 'Metal Raiders',
  rarity: 'Super Rare',
);
const _mirrorForceDarkSaviors = Printing(
  id: 2,
  passcode: '44095762',
  setCode: 'DASA-EN059',
  setName: 'Dark Saviors',
  rarity: 'Ultra Rare',
);
const _sparse = Printing(id: 3, passcode: '44095762', setName: 'Legendary Duelists');

const _all = [
  _mirrorForceMetalRaiders,
  _mirrorForceDarkSaviors,
  _sparse,
];

void main() {
  group('displayLabel', () {
    test('joins the fields the row carries', () {
      expect(
        _mirrorForceMetalRaiders.displayLabel,
        'MRD-EN094 · Metal Raiders · Super Rare',
      );
    });

    test('omits missing fields', () {
      expect(_sparse.displayLabel, 'Legendary Duelists');
    });

    test('is empty when the row carries none of the three', () {
      expect(const Printing(passcode: '1').displayLabel, '');
    });
  });

  group('filterPrintings', () {
    test('an empty query keeps every printing', () {
      expect(filterPrintings(_all, ''), _all);
      expect(filterPrintings(_all, '   '), _all);
    });

    test('matches on set name, case-insensitively', () {
      expect(filterPrintings(_all, 'metal'), [_mirrorForceMetalRaiders]);
      expect(filterPrintings(_all, 'METAL RAIDERS'), [_mirrorForceMetalRaiders]);
    });

    test('matches on set code', () {
      expect(filterPrintings(_all, 'dasa'), [_mirrorForceDarkSaviors]);
    });

    test('matches on rarity', () {
      expect(filterPrintings(_all, 'ultra'), [_mirrorForceDarkSaviors]);
    });

    test('every term must match, in any order', () {
      expect(
        filterPrintings(_all, 'raiders super'),
        [_mirrorForceMetalRaiders],
      );
      expect(
        filterPrintings(_all, 'super raiders'),
        [_mirrorForceMetalRaiders],
      );
      // "Super Rare" is Metal Raiders, "Dark Saviors" is Ultra — no row has both.
      expect(filterPrintings(_all, 'saviors super'), isEmpty);
    });

    test('returns nothing when no printing matches', () {
      expect(filterPrintings(_all, 'invasion of chaos'), isEmpty);
    });

    test('a row with only a set name is still searchable', () {
      expect(filterPrintings(_all, 'legendary'), [_sparse]);
    });
  });
}
