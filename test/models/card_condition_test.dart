import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/models/card_condition.dart';

void main() {
  test('toDb produces the exact SCREAMING_SNAKE persisted values', () {
    expect(CardCondition.mint.toDb(), 'MINT');
    expect(CardCondition.nearMint.toDb(), 'NEAR_MINT');
    expect(CardCondition.excellent.toDb(), 'EXCELLENT');
    expect(CardCondition.good.toDb(), 'GOOD');
    expect(CardCondition.lightPlayed.toDb(), 'LIGHT_PLAYED');
    expect(CardCondition.played.toDb(), 'PLAYED');
    expect(CardCondition.poor.toDb(), 'POOR');
  });

  test('fromDb(toDb(v)) round-trips for every value', () {
    for (final condition in CardCondition.values) {
      expect(CardCondition.fromDb(condition.toDb()), condition);
    }
  });

  test('fromDb rejects an unknown value', () {
    expect(() => CardCondition.fromDb('BROKEN'), throwsArgumentError);
  });

  test('sortOrder reflects Cardmarket best -> worst order', () {
    final byBestToWorst = [...CardCondition.values]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    expect(byBestToWorst, [
      CardCondition.mint,
      CardCondition.nearMint,
      CardCondition.excellent,
      CardCondition.good,
      CardCondition.lightPlayed,
      CardCondition.played,
      CardCondition.poor,
    ]);
  });
}
