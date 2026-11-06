import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/shared/widgets/justified_wrap.dart';
import 'package:ygo_scanner/shared/widgets/labeled_choice_chip.dart';

void main() {
  const width = 360.0;
  const spacing = 4.0;

  Future<void> pumpChips(WidgetTester tester, List<String> labels) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: JustifiedWrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final label in labels)
                    LabeledChoiceChip(
                      label: label,
                      selected: false,
                      selectedColor: Colors.amber,
                      onSelected: () {},
                      expand: true,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The chip as drawn — its `Material`, not the `ChoiceChip` widget.
  ///
  /// The distinction is the whole test: `RawChip` wraps the drawn chip in
  /// tap-target padding that takes whatever width it is given and centres a
  /// natural-width chip inside it. So the widget's own box fills its slot even
  /// when the visible pill does not, and measuring it would pass with the
  /// label centring removed (verified).
  Rect chipRect(WidgetTester tester, String label) => tester.getRect(
    find
        .ancestor(of: find.text(label), matching: find.byType(Material))
        .first,
  );

  /// The chips grouped into rows by their top edge, each row left to right.
  List<List<Rect>> rows(WidgetTester tester, List<String> labels) {
    final byTop = <double, List<Rect>>{};
    for (final label in labels) {
      final rect = chipRect(tester, label);
      byTop.putIfAbsent(rect.top, () => []).add(rect);
    }
    return [
      for (final top in byTop.keys.toList()..sort())
        byTop[top]!..sort((a, b) => a.left.compareTo(b.left)),
    ];
  }

  testWidgets('every row, the last included, spans the full width', (
    tester,
  ) async {
    // Long enough to need several rows at 360pt, with a short final row.
    const labels = [
      'All',
      'Common',
      'Rare',
      'Super Rare',
      'Ultra Rare',
      'Secret Rare',
      'Gold Rare',
      'Ghost Rare',
      'Starlight Rare',
      'NM',
    ];
    await pumpChips(tester, labels);

    final grouped = rows(tester, labels);
    expect(grouped.length, greaterThan(1));
    for (final row in grouped) {
      expect(row.first.left, closeTo(0, 0.01));
      expect(row.last.right, closeTo(width, 0.01));
      for (var i = 1; i < row.length; i++) {
        expect(row[i].left - row[i - 1].right, closeTo(spacing, 0.01));
      }
    }
  });

  testWidgets('the label is centred in its stretched chip', (tester) async {
    await pumpChips(tester, const ['All', 'Common', 'Rare']);

    for (final label in const ['All', 'Common', 'Rare']) {
      final chip = chipRect(tester, label);
      final text = tester.getRect(find.text(label));
      expect(chip.width, greaterThan(text.width + 20));
      expect(text.center.dx, closeTo(chip.center.dx, 0.5));
    }
  });

  testWidgets('a chip is no taller than it would be unstretched', (
    tester,
  ) async {
    await pumpChips(tester, const ['Rare']);
    final stretched = chipRect(tester, 'Rare').height;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Wrap(
            children: [
              LabeledChoiceChip(
                label: 'Rare',
                selected: false,
                selectedColor: Colors.amber,
                onSelected: () {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(stretched, chipRect(tester, 'Rare').height);
  });

  testWidgets('a stretched chip is still tappable across its width', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: width,
            child: JustifiedWrap(
              children: [
                LabeledChoiceChip(
                  label: 'All',
                  selected: false,
                  selectedColor: Colors.amber,
                  onSelected: () => taps++,
                  expand: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Near the right edge: well clear of the text itself.
    final chip = chipRect(tester, 'All');
    await tester.tapAt(Offset(chip.right - 10, chip.center.dy));
    expect(taps, 1);
  });
}
