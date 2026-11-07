import '../core/constants.dart';

// Display names for the card data YGOPRODeck supplies, in the interface
// language. The tables live in `AppStrings`; these are the one way to read them.
//
// **Labels only, and that is the rule that keeps the rest of the app simple.**
// `CollectionFilter`, every `WHERE` clause and both CSV writers go on holding the
// API's raw English values, so a filter chip reading "Mostro con Effetto" still
// selects `Effect Monster`, and an export means the same thing whichever language
// the phone is in.
//
// Each falls back to the raw value, like `languageLabel`: the API's lists are
// open-ended, and a value added upstream should read in English rather than break.

/// A card's `type`: "Effect Monster" -> "Mostro con Effetto".
String cardTypeLabel(String type) => AppStrings.cardTypeNames[type] ?? type;

/// A card's `frameType`: "effect_pendulum" -> "Effect Pendulum".
String cardFrameLabel(String frame) =>
    AppStrings.cardFrameNames[frame] ?? frame;

/// A card's `race`: a monster type, a Spell/Trap icon, or on a Skill card a
/// character's name, which passes through.
String cardRaceLabel(String race) => AppStrings.cardRaceNames[race] ?? race;

/// A card's `attribute`: "DARK" -> "OSCURITÀ".
String cardAttributeLabel(String attribute) =>
    AppStrings.cardAttributeNames[attribute] ?? attribute;

/// A printing's `rarity`. Trade names and junk values pass through; see
/// `AppStrings.cardRarityNames`.
String rarityLabel(String rarity) =>
    AppStrings.cardRarityNames[rarity] ?? rarity;

/// [values] in the order their labels read, for a list a person scans by eye.
///
/// The DAO sorts on the raw English, which puts "Incantatore" (`Spellcaster`)
/// under S once it is on screen in Italian. A copy, so the caller's list is left
/// alone.
List<String> sortedByLabel(
  List<String> values,
  String Function(String) labelOf,
) => [...values]..sort((a, b) => labelOf(a).compareTo(labelOf(b)));
