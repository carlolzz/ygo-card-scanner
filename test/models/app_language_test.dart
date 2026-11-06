import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/models/app_language.dart';

void main() {
  test('toDb produces the exact persisted values', () {
    expect(AppLanguage.english.toDb(), 'ENGLISH');
    expect(AppLanguage.italian.toDb(), 'ITALIAN');
  });

  test('fromDb(toDb(v)) round-trips for every value', () {
    for (final language in AppLanguage.values) {
      expect(AppLanguage.fromDb(language.toDb()), language);
    }
  });

  test('fromDb rejects an unknown value', () {
    expect(() => AppLanguage.fromDb('KLINGON'), throwsArgumentError);
  });

  // Endonyms, so the chip back to a language is readable from inside it.
  test('each language is labelled in itself', () {
    expect(AppLanguage.english.label, 'English');
    expect(AppLanguage.italian.label, 'Italiano');
  });

  test('toLocale gives the language code Material looks up', () {
    expect(AppLanguage.english.toLocale().languageCode, 'en');
    expect(AppLanguage.italian.toLocale().languageCode, 'it');
  });
}
