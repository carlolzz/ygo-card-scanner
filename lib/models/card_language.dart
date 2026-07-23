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
