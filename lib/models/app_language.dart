import 'dart:ui';

/// The language the app's own interface is written in. Persisted to SQLite by
/// name (in the `meta` table), never by ordinal, like every other enum here.
///
/// Interface text only: card names, effect text and the API's type/race/
/// attribute values are YGOPRODeck data and stay as synced. That is a different
/// question from the *search* language (`kSearchLanguages`, which needs a
/// shipped name asset) and from a card's printed language (`kCardLanguages`).
enum AppLanguage {
  // Each label is the language's name *in itself* and never translated: someone
  // who switched by mistake has to be able to find their way back without
  // reading the language they landed in.
  english('English', 'en'),
  italian('Italiano', 'it');

  const AppLanguage(this.label, this.languageCode);

  final String label;
  final String languageCode;

  Locale toLocale() => Locale(languageCode);

  String toDb() => switch (this) {
    AppLanguage.english => 'ENGLISH',
    AppLanguage.italian => 'ITALIAN',
  };

  static AppLanguage fromDb(String value) => switch (value) {
    'ENGLISH' => AppLanguage.english,
    'ITALIAN' => AppLanguage.italian,
    _ => throw ArgumentError('Unknown AppLanguage db value: $value'),
  };
}
