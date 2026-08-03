import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/models/card_language.dart';

void main() {
  group('languageLabel', () {
    test('names every listed language', () {
      for (final code in kCardLanguages) {
        expect(languageLabel(code), isNot(code), reason: 'unnamed: $code');
      }
    });

    test('echoes an unlisted code back', () {
      expect(languageLabel('NL'), 'NL');
    });
  });

  group('languageFlag', () {
    test('every listed language has a flag, except Asian-English', () {
      for (final code in kCardLanguages) {
        if (code == 'AE') continue;
        expect(languageFlag(code), isNotNull, reason: 'no flag: $code');
      }
    });

    test('Asian-English has none — it is a region, not a country', () {
      expect(languageFlag('AE'), isNull);
    });

    test('an unlisted code has none', () {
      expect(languageFlag('NL'), isNull);
      expect(languageFlag(''), isNull);
    });

    test('Spanish uses ES, not the SP of its language block', () {
      // The one mapping that cannot be derived from the two letters: the card
      // prints `SP`, but `SP` is not a country and has no flag.
      expect(languageFlag('SP'), '\u{1F1EA}\u{1F1F8}');
    });

    test('each flag is a regional-indicator pair', () {
      for (final flag in kCardLanguageFlags.values) {
        final runes = flag.runes.toList();
        expect(runes, hasLength(2), reason: flag);
        for (final rune in runes) {
          expect(
            rune,
            inInclusiveRange(0x1F1E6, 0x1F1FF),
            reason: 'not a regional indicator in $flag',
          );
        }
      }
    });

    test('no two languages share a flag', () {
      expect(
        kCardLanguageFlags.values.toSet(),
        hasLength(kCardLanguageFlags.length),
      );
    });
  });
}
