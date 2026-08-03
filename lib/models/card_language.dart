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

/// Human-readable names for the language codes in [kCardLanguages]. Only the
/// UI reads these — the persisted value stays the two-letter code, so an
/// unlisted language remains storable (and [languageLabel] echoes it back).
const Map<String, String> kCardLanguageNames = {
  'EN': 'English',
  'DE': 'German',
  'FR': 'French',
  'IT': 'Italian',
  'SP': 'Spanish',
  'PT': 'Portuguese',
  'JP': 'Japanese',
  'KR': 'Korean',
  'AE': 'Asian-English',
};

/// The display name for a language [code], falling back to the raw code for
/// anything [kCardLanguageNames] doesn't cover.
String languageLabel(String code) => kCardLanguageNames[code] ?? code;

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
