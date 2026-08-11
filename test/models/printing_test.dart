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
    const otherCommon = Printing(
      id: 4,
      passcode: '89631139',
      setCode: 'SDK-001',
      rarity: 'Common',
    );

    test('a card with no printings gets nothing', () {
      expect(preferredPrinting(const [], defaultRarity: 'Common'), isNull);
    });

    // Step 22's behaviour, unchanged: the card came from somewhere, and making
    // the user tap a decision with one option risks them leaving it untapped.
    test('a lone printing wins whatever the preference says', () {
      expect(preferredPrinting(const [ultra]), ultra);
      expect(preferredPrinting(const [ultra], defaultRarity: 'Common'), ultra);
    });

    test('several printings and no preference is the user\'s call', () {
      expect(preferredPrinting(const [common, ultra]), isNull);
      expect(preferredPrinting(const [common, ultra], defaultRarity: ''), isNull);
      expect(
        preferredPrinting(const [common, ultra], defaultRarity: '   '),
        isNull,
      );
    });

    test('exactly one printing of the preferred rarity is picked', () {
      expect(
        preferredPrinting(const [common, ultra, secret], defaultRarity: 'Ultra Rare'),
        ultra,
      );
    });

    // The user's own example: a card printed only in Ultra and Secret Rare with
    // a Common preference gets nothing. The preference selects among what a card
    // actually has; it never invents a printing.
    test('a preference the card has no printing of does not apply', () {
      expect(
        preferredPrinting(const [ultra, secret], defaultRarity: 'Common'),
        isNull,
      );
    });

    // Two Commons in different sets: the camera cannot tell which reprint is in
    // hand, and picking one would silently log the wrong set half the time.
    test('two printings of the preferred rarity is still the user\'s call', () {
      expect(
        preferredPrinting(
          const [common, otherCommon, ultra],
          defaultRarity: 'Common',
        ),
        isNull,
      );
    });

    test('matching ignores case and surrounding space', () {
      // The preference is persisted free-form text, not an enum.
      expect(
        preferredPrinting(const [common, ultra], defaultRarity: '  ultra rare '),
        ultra,
      );
    });

    test('printings with no rarity never match a preference', () {
      const noRarity = Printing(id: 5, passcode: '89631139', setCode: 'X-001');
      expect(
        preferredPrinting(const [noRarity, ultra], defaultRarity: 'Common'),
        isNull,
      );
    });
  });
}
