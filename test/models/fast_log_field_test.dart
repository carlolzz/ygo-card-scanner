import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/models/fast_log_field.dart';

void main() {
  test('toDb produces the exact persisted values', () {
    expect(FastLogField.condition.toDb(), 'CONDITION');
    expect(FastLogField.edition.toDb(), 'EDITION');
    expect(FastLogField.language.toDb(), 'LANGUAGE');
  });

  test('fromDb(toDb(v)) round-trips for every value', () {
    for (final field in FastLogField.values) {
      expect(FastLogField.fromDb(field.toDb()), field);
    }
  });

  test('fromDb rejects an unknown value', () {
    expect(() => FastLogField.fromDb('RARITY'), throwsArgumentError);
  });

  test('every member carries a label', () {
    for (final field in FastLogField.values) {
      expect(field.label, isNotEmpty);
    }
  });
}
