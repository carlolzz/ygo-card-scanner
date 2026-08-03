import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/core/search_terms.dart';

/// The rule behind every "type to narrow a list" box in the app. `filterPrintings`
/// has always been tested through its own cases (`test/models/printing_test.dart`);
/// these pin the rule itself, now that the collection filter sheet's set box
/// shares it and a change here would silently alter both.
void main() {
  const label = 'MRD-EN094 · Metal Raiders · Super Rare';

  test('a blank query matches everything', () {
    expect(matchesSearchTerms(label, ''), isTrue);
    expect(matchesSearchTerms(label, '   '), isTrue);
    // The boxes open as a plain list the user can scroll; typing only narrows.
    expect(matchesSearchTerms('', ''), isTrue);
  });

  test('matching is case-insensitive on both sides', () {
    expect(matchesSearchTerms(label, 'metal'), isTrue);
    expect(matchesSearchTerms(label, 'METAL'), isTrue);
    expect(matchesSearchTerms('metal raiders', 'Metal'), isTrue);
  });

  test('every term must appear, in any order', () {
    expect(matchesSearchTerms(label, 'raiders super'), isTrue);
    expect(matchesSearchTerms(label, 'super raiders'), isTrue);
    expect(matchesSearchTerms(label, 'raiders ultra'), isFalse);
  });

  test('runs of whitespace collapse rather than adding empty terms', () {
    expect(matchesSearchTerms(label, '  raiders   super  '), isTrue);
  });

  test('terms match mid-word, so a partial name still finds its set', () {
    expect(matchesSearchTerms('Legend of Blue Eyes White Dragon', 'blue ey'),
        isTrue);
  });

  test('nothing matches when a term is absent', () {
    expect(matchesSearchTerms(label, 'invasion'), isFalse);
  });
}
