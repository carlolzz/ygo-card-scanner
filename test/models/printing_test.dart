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
const _sparse = Printing(
  id: 3,
  passcode: '44095762',
  setName: 'Legendary Duelists',
);

const _all = [_mirrorForceMetalRaiders, _mirrorForceDarkSaviors, _sparse];

void main() {
  group('displayLabel', () {
    test('joins the fields the row carries', () {
      expect(
        _mirrorForceMetalRaiders.displayLabel,
        'MRD-EN094 (Super Rare) Metal Raiders',
      );
    });

    // Set names run long enough to be ellipsised in a picker row, and a list of
    // reprints showing a truncated name and no rarity cannot be picked from —
    // so the two fields that form the `printings` UNIQUE key lead the label and
    // the human-readable gloss is what gets lost to the edge.
    test('puts the rarity ahead of the set name', () {
      final label = _mirrorForceMetalRaiders.displayLabel;
      expect(label.indexOf('Super Rare'), lessThan(label.indexOf('Metal')));
    });

    test('omits missing fields', () {
      expect(_sparse.displayLabel, 'Legendary Duelists');
    });

    test('omits the parentheses along with a missing rarity', () {
      expect(
        const Printing(
          passcode: '1',
          setCode: 'LOB-001',
          setName: 'Legend of Blue Eyes',
        ).displayLabel,
        'LOB-001 Legend of Blue Eyes',
      );
    });

    test('is empty when the row carries none of the three', () {
      expect(const Printing(passcode: '1').displayLabel, '');
    });
  });

  group('setLabel', () {
    // The collection detail screen gives rarity a row of its own, so the Set
    // row must not trail it — while the pickers keep searching displayLabel.
    test('omits the rarity', () {
      expect(_mirrorForceMetalRaiders.setLabel, 'MRD-EN094 · Metal Raiders');
    });

    test('omits missing fields', () {
      expect(_sparse.setLabel, 'Legendary Duelists');
    });

    test('is empty when the row carries no set at all', () {
      expect(const Printing(passcode: '1', rarity: 'Rare').setLabel, '');
    });
  });

  group('filterPrintings', () {
    test('an empty query keeps every printing', () {
      expect(filterPrintings(_all, ''), _all);
      expect(filterPrintings(_all, '   '), _all);
    });

    test('matches on set name, case-insensitively', () {
      expect(filterPrintings(_all, 'metal'), [_mirrorForceMetalRaiders]);
      expect(filterPrintings(_all, 'METAL RAIDERS'), [
        _mirrorForceMetalRaiders,
      ]);
    });

    test('matches on set code', () {
      expect(filterPrintings(_all, 'dasa'), [_mirrorForceDarkSaviors]);
    });

    test('matches on rarity', () {
      expect(filterPrintings(_all, 'ultra'), [_mirrorForceDarkSaviors]);
    });

    test('every term must match, in any order', () {
      expect(filterPrintings(_all, 'raiders super'), [
        _mirrorForceMetalRaiders,
      ]);
      expect(filterPrintings(_all, 'super raiders'), [
        _mirrorForceMetalRaiders,
      ]);
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

  // The rule both logging flows use to preselect a set. Every way of getting it
  // wrong is silent — a wrong preselection logs a real card against the wrong
  // set, in a field the user has no reason to re-check.
  group('preferredPrinting', () {
    const common = Printing(
      id: 1,
      passcode: '89631139',
      setCode: 'SKE-001',
      rarity: 'Common',
    );
    const ultra = Printing(
      id: 2,
      passcode: '89631139',
      setCode: 'LOB-EN001',
      rarity: 'Ultra Rare',
    );
    const secret = Printing(
      id: 3,
      passcode: '89631139',
      setCode: 'DPBC-EN001',
      rarity: 'Secret Rare',
    );

    test('a card with no printings gets nothing', () {
      expect(preferredPrinting(const []), isNull);
    });

    // Step 22's behaviour, unchanged: the card came from somewhere, and making
    // the user tap a decision with one option risks them leaving it untapped.
    test('a lone printing is picked', () {
      expect(preferredPrinting(const [ultra]), ultra);
    });

    // The camera cannot tell which reprint is in hand, and picking one would
    // silently log the wrong set. Step 24 removed the default-rarity preference
    // that used to narrow this case, so several printings is always the user's
    // call now.
    test('several printings is the user\'s call', () {
      expect(preferredPrinting(const [common, ultra]), isNull);
      expect(preferredPrinting(const [common, ultra, secret]), isNull);
    });
  });
}
