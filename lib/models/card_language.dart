import '../core/constants.dart';

/// The two-letter language blocks that appear in a set code (`LOB-EN001`),
/// per `.claude/skills/ygo-domain.md`.
///
/// Deliberately plain constants rather than an enum: `collection_entries
/// .language` is free-form TEXT, and a card printed in a language this list
/// doesn't know about must still be storable without a migration.
const List<String> kCardLanguages = [
  'EN',
  'DE',
  'FR',
  'IT',
  'SP',
  'PT',
  'JP',
  'KR',
  'AE',
];

/// Matches the `collection_entries.language` column default.
const String kDefaultCardLanguage = 'EN';

/// The languages a card can be *searched* in — a different question from
/// [kCardLanguages], which is what language a card in the collection is printed
/// in.
///
/// Searching needs card names in that language, and the sync only ever fetches
/// English. Every entry past [kDefaultSearchLanguage] therefore has to ship its
/// own `assets/card_names_<lang>.json` (built by
/// `tools/build_localized_names.py`, registered in `pubspec.yaml`), so adding a
/// code here without adding its asset makes the search throw. YGOPRODeck
/// publishes translations for `it`, `fr`, `de` and `pt`; only Italian is
/// shipped.
const List<String> kSearchLanguages = [kDefaultSearchLanguage, 'IT'];

/// The language searched unless the user picks otherwise: the one already in
/// `cards.name`, which needs no asset and no import.
const String kDefaultSearchLanguage = 'EN';

/// The display name for a language [code] in the current interface language,
/// falling back to the raw code for anything `AppStrings.cardLanguageNames`
/// doesn't cover.
///
/// Only the UI reads these — the persisted value stays the two-letter code, so
/// an unlisted language remains storable and is echoed back as-is.
String languageLabel(String code) => AppStrings.cardLanguageNames[code] ?? code;

/// Flag glyphs (Unicode regional-indicator pairs) for the language codes that
/// name a country. Deliberately explicit rather than derived from the code:
/// Spanish prints as `SP` but its country is `ES`, so no transformation of the
/// two letters produces the right flag.
///
/// `AE` (Asian-English) is absent on purpose — it is a distribution region, not
/// a country, and picking one of its countries would put a claim on the card
/// that the card itself doesn't make. It takes the same fallback an unlisted
/// code from a CSV import takes: the raw two letters.
const Map<String, String> kCardLanguageFlags = {
  'EN': '🇬🇧',
  'DE': '🇩🇪',
  'FR': '🇫🇷',
  'IT': '🇮🇹',
  'SP': '🇪🇸',
  'PT': '🇵🇹',
  'JP': '🇯🇵',
  'KR': '🇰🇷',
};

/// The flag for a language [code], or null when the code names no country —
/// callers render the code itself in that case.
String? languageFlag(String code) => kCardLanguageFlags[code];
