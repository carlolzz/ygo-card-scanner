import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/models/card_edition.dart';

void main() {
  test('toDb produces the exact persisted values', () {
    expect(CardEdition.first.toDb(), 'FIRST');
    expect(CardEdition.unlimited.toDb(), 'UNLIMITED');
    expect(CardEdition.limited.toDb(), 'LIMITED');
  });

  test('fromDb(toDb(v)) round-trips for every value', () {
    for (final edition in CardEdition.values) {
      expect(CardEdition.fromDb(edition.toDb()), edition);
    }
  });

  test('fromDb rejects an unknown value', () {
    expect(() => CardEdition.fromDb('BROKEN'), throwsArgumentError);
  });
}
