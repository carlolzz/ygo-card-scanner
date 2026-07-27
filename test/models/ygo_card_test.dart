import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/models/ygo_card.dart';

/// The frame-type predicates the collection detail screen labels rows from.
/// They key off `frameType`, not `type`, because that is the field that is
/// exactly `spell`/`trap` — `type` is "Spell Card"/"Quick-Play Spell"/etc.
void main() {
  group('isSpell / isTrap', () {
    test('a spell is a spell, and a spell-or-trap', () {
      const card = YgoCard(
        passcode: '55144522',
        name: 'Pot of Greed',
        type: 'Spell Card',
        frameType: 'spell',
        race: 'Normal',
      );
      expect(card.isSpell, isTrue);
      expect(card.isTrap, isFalse);
      expect(card.isSpellOrTrap, isTrue);
    });

    test('a trap is a trap, and a spell-or-trap', () {
      const card = YgoCard(
        passcode: '44095762',
        name: 'Mirror Force',
        type: 'Trap Card',
        frameType: 'trap',
        race: 'Normal',
      );
      expect(card.isTrap, isTrue);
      expect(card.isSpell, isFalse);
      expect(card.isSpellOrTrap, isTrue);
    });

    test('a monster is neither', () {
      const card = YgoCard(
        passcode: '46986414',
        name: 'Dark Magician',
        type: 'Normal Monster',
        frameType: 'normal',
        race: 'Spellcaster',
      );
      expect(card.isSpell, isFalse);
      expect(card.isTrap, isFalse);
      expect(card.isSpellOrTrap, isFalse);
    });

    test('a card with no frame type is neither', () {
      const card = YgoCard(passcode: '1', name: 'Unknown');
      expect(card.isSpell, isFalse);
      expect(card.isTrap, isFalse);
      expect(card.isSpellOrTrap, isFalse);
    });
  });
}
