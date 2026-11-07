import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/core/constants.dart';
import 'package:ygo_scanner/models/app_language.dart';
import 'package:ygo_scanner/models/card_terms.dart';

// Every value YGOPRODeck sent when this was measured (14,655 cards). A gap in one
// of these tables does not crash: the chip just reads in English, which is the
// bug this file exists to stop coming back.
const _types = [
  'Effect Monster',
  'Flip Effect Monster',
  'Flip Tuner Effect Monster',
  'Fusion Monster',
  'Gemini Monster',
  'Link Monster',
  'Normal Monster',
  'Normal Tuner Monster',
  'Pendulum Effect Fusion Monster',
  'Pendulum Effect Monster',
  'Pendulum Effect Ritual Monster',
  'Pendulum Flip Effect Monster',
  'Pendulum Normal Monster',
  'Pendulum Tuner Effect Monster',
  'Ritual Effect Monster',
  'Ritual Monster',
  'Skill Card',
  'Spell Card',
  'Spirit Monster',
  'Synchro Monster',
  'Synchro Pendulum Effect Monster',
  'Synchro Tuner Monster',
  'Token',
  'Toon Monster',
  'Trap Card',
  'Tuner Monster',
  'Union Effect Monster',
  'XYZ Monster',
  'XYZ Pendulum Effect Monster',
];

const _frames = [
  'effect',
  'effect_pendulum',
  'fusion',
  'fusion_pendulum',
  'link',
  'normal',
  'normal_pendulum',
  'ritual',
  'ritual_pendulum',
  'skill',
  'spell',
  'synchro',
  'synchro_pendulum',
  'token',
  'trap',
  'xyz',
  'xyz_pendulum',
];

const _races = [
  'Aqua',
  'Beast',
  'Beast-Warrior',
  'Creator God',
  'Cyberse',
  'Dinosaur',
  'Divine-Beast',
  'Dragon',
  'Fairy',
  'Fiend',
  'Fish',
  'Illusion',
  'Insect',
  'Machine',
  'Plant',
  'Psychic',
  'Pyro',
  'Reptile',
  'Rock',
  'Sea Serpent',
  'Spellcaster',
  'Thunder',
  'Warrior',
  'Winged Beast',
  'Wyrm',
  'Zombie',
  'Continuous',
  'Counter',
  'Equip',
  'Field',
  'Normal',
  'Quick-Play',
  'Ritual',
];

const _attributes = [
  'DARK',
  'DIVINE',
  'EARTH',
  'FIRE',
  'LIGHT',
  'WATER',
  'WIND',
];

void main() {
  // The language is process-wide state, so nothing here may leak it.
  tearDown(() => AppStrings.select(AppLanguage.english));

  group('in Italian', () {
    setUp(() => AppStrings.select(AppLanguage.italian));

    test('every measured value has a row of its own', () {
      for (final value in _types) {
        expect(AppStrings.cardTypeNames, contains(value));
      }
      for (final value in _frames) {
        expect(AppStrings.cardFrameNames, contains(value));
      }
      for (final value in _races) {
        expect(AppStrings.cardRaceNames, contains(value));
      }
      for (final value in _attributes) {
        expect(AppStrings.cardAttributeNames, contains(value));
      }
    });

    // Konami's own wording, which is not always the obvious translation.
    test('uses the official terms', () {
      expect(cardRaceLabel('Spellcaster'), 'Incantatore');
      expect(cardRaceLabel('Fiend'), 'Demone');
      expect(cardRaceLabel('Cyberse'), 'Cyberso');
      expect(cardRaceLabel('Aqua'), 'Acqua');
      expect(cardRaceLabel('Quick-Play'), 'Rapida');
      expect(cardRaceLabel('Field'), 'Terreno');
      expect(cardAttributeLabel('DARK'), 'OSCURITÀ');
      expect(cardTypeLabel('Effect Monster'), 'Mostro con Effetto');
      expect(
        cardTypeLabel('Flip Effect Monster'),
        'Mostro Scoperta con Effetto',
      );
      expect(cardTypeLabel('Gemini Monster'), 'Mostro Gemello');
      // Konami's search form says "Spirit", its card pages "Spirito".
      expect(cardTypeLabel('Spirit Monster'), 'Mostro Spirito');
      expect(cardTypeLabel('Token'), 'Segna-Mostro');
      expect(cardFrameLabel('effect_pendulum'), 'Effetto Pendulum');
    });

    test('a value the tables do not know echoes back', () {
      expect(cardTypeLabel('Brand New Monster'), 'Brand New Monster');
      expect(cardFrameLabel('brand_new'), 'brand_new');
      expect(cardAttributeLabel('AETHER'), 'AETHER');
      // YGOPRODeck puts the character's name in `race` on a Skill card.
      expect(cardRaceLabel('Joey'), 'Joey');
    });

    test('translates the common rarities', () {
      expect(rarityLabel('Common'), 'Comune');
      expect(rarityLabel('Rare'), 'Rara');
      expect(rarityLabel('Super Rare'), 'Super Rara');
      expect(rarityLabel('Ultra Rare'), 'Ultra Rara');
      expect(rarityLabel('Secret Rare'), 'Rara Segreta');
      expect(rarityLabel('Ultimate Rare'), 'Ultimate Rara');
      expect(rarityLabel('Ghost Rare'), 'Ghost Rara');
      expect(rarityLabel('Gold Rare'), 'Gold Rara');
    });

    // Decided with the user: no invented names, and the API's junk stays visible
    // as what it is.
    test('leaves trade-name and junk rarities alone', () {
      expect(rarityLabel('Starlight Rare'), 'Starlight Rare');
      expect(
        rarityLabel('Quarter Century Secret Rare'),
        'Quarter Century Secret Rare',
      );
      expect(rarityLabel('2'), '2');
      expect(rarityLabel('force-SMW'), 'force-SMW');
    });

    test('sortedByLabel orders by what the labels read', () {
      expect(sortedByLabel(['Spellcaster', 'Dragon', 'Fiend'], cardRaceLabel), [
        'Fiend', // Demone
        'Dragon', // Drago
        'Spellcaster', // Incantatore
      ]);
    });

    test('sortedByLabel leaves the list it was given alone', () {
      final values = ['Spellcaster', 'Dragon'];
      sortedByLabel(values, cardRaceLabel);
      expect(values, ['Spellcaster', 'Dragon']);
    });
  });

  group('in English', () {
    test('API values are shown as they arrive', () {
      expect(cardTypeLabel('Effect Monster'), 'Effect Monster');
      expect(cardRaceLabel('Spellcaster'), 'Spellcaster');
      expect(cardAttributeLabel('DARK'), 'DARK');
      expect(rarityLabel('Super Rare'), 'Super Rare');
    });

    // These read "Effect_pendulum" in English too until the table replaced
    // title-casing the raw identifier.
    test('every frame reads as words, with no identifiers left over', () {
      for (final frame in _frames) {
        final label = cardFrameLabel(frame);
        expect(label, isNot(contains('_')));
        expect(label[0], label[0].toUpperCase());
      }
      expect(cardFrameLabel('effect_pendulum'), 'Effect Pendulum');
      expect(cardFrameLabel('xyz'), 'Xyz');
    });
  });
}
