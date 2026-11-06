import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/shared/widgets/justified_wrap_layout.dart';

void main() {
  /// The width a run actually occupies, gaps included.
  double occupied(List<double> run, double spacing) =>
      run.fold(0.0, (a, b) => a + b) + spacing * (run.length - 1);

  test('nothing in, nothing out', () {
    expect(justifyRuns(const [], maxWidth: 300, spacing: 4), isEmpty);
  });

  test('a run that fits is stretched to the full width, equally', () {
    final runs = justifyRuns(const [40, 60, 80], maxWidth: 300, spacing: 10);

    expect(runs, hasLength(1));
    // 300 - 180 - 20 = 100 leftover, split three ways.
    for (final (i, natural) in const [40.0, 60.0, 80.0].indexed) {
      expect(runs.single[i], closeTo(natural + 100 / 3, 1e-9));
    }
    expect(occupied(runs.single, 10), closeTo(300, 1e-9));
  });

  // The gap is counted per child already in the run, not once: with 100-wide
  // children, 10 spacing and 320 to fill, three fit exactly (100*3 + 2*10) and
  // a fourth does not.
  test('rows break exactly where Wrap would break them', () {
    final runs = justifyRuns(
      const [100, 100, 100, 100],
      maxWidth: 320,
      spacing: 10,
    );

    expect(runs.map((r) => r.length), [3, 1]);
  });

  // The reported case: a short last row used to stay at natural width.
  test('the last, partly filled row is stretched too', () {
    final runs = justifyRuns(
      const [100, 100, 100, 50],
      maxWidth: 320,
      spacing: 10,
    );

    expect(runs.last, [320]);
    for (final run in runs) {
      expect(occupied(run, 10), closeTo(320, 1e-9));
    }
  });

  test('a child too wide for the row gets a row of its own, clamped', () {
    final runs = justifyRuns(const [50, 500, 50], maxWidth: 200, spacing: 4);

    expect(runs.map((r) => r.length), [1, 1, 1]);
    expect(runs[1], [200]);
  });

  test('flattened, there is one width per child, in order', () {
    const naturals = [30.0, 90.0, 45.0, 120.0, 60.0, 75.0, 20.0];
    final runs = justifyRuns(naturals, maxWidth: 250, spacing: 6);
    final flat = runs.expand((r) => r).toList();

    expect(flat, hasLength(naturals.length));
    for (final (i, natural) in naturals.indexed) {
      expect(flat[i], greaterThanOrEqualTo(natural));
    }
  });

  test('an unbounded width leaves everything in one natural-width run', () {
    final runs = justifyRuns(
      const [30, 40],
      maxWidth: double.infinity,
      spacing: 4,
    );

    expect(runs, [
      [30, 40],
    ]);
  });
}
