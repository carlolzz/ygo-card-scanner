import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/core/money.dart';

void main() {
  test('formats each currency with its own symbol', () {
    expect(formatEur(0.29), '€0.29');
    expect(formatUsd(1.15), r'$1.15');
  });

  test('always two decimal places', () {
    expect(formatUsd(5), r'$5.00');
    expect(formatEur(1234.5), '€1234.50');
  });

  // An em dash, not "0.00" — a card with no known price is not a card worth
  // nothing, and the difference matters beside a total that says how many cards
  // were skipped.
  test('an unknown figure is a dash, never a zero', () {
    expect(formatEur(null), kNoPrice);
    expect(formatUsd(null), kNoPrice);
    expect(formatUsd(0), kNoPrice);
    expect(formatEur(-1), kNoPrice);
    expect(formatUsd(double.nan), kNoPrice);
    expect(formatEur(double.infinity), kNoPrice);
  });
}
