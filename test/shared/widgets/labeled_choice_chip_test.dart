import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/core/theme/tokens.dart';
import 'package:ygo_scanner/models/card_language.dart';
import 'package:ygo_scanner/shared/widgets/labeled_choice_chip.dart';

/// A `ChoiceChip` inserts a checkmark when it is selected, which makes it
/// **wider than it was**. In a `Wrap` that reflows the entire run: the chips
/// after the selected one shift right and can jump a line, so tapping through
/// the language row made the block flicker and move under the finger.
///
/// The fix is one line (`showCheckmark: false`), and this is the guard against
/// a future tidy-up removing it — the symptom is cosmetic and intermittent, so
/// it would not be noticed until someone was mid-tap again.
void main() {
  Widget wrapOfLanguages(String selected) => MaterialApp(
    home: Scaffold(
      body: Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: [
          for (final language in kCardLanguages)
            LabeledChoiceChip(
              key: ValueKey(language),
              label: languageLabel(language),
              selected: language == selected,
              selectedColor: AppPalette.dark.accent,
              onSelected: () {},
            ),
        ],
      ),
    ),
  );

  testWidgets('a chip is the same size selected as unselected', (tester) async {
    await tester.pumpWidget(wrapOfLanguages('EN'));
    final unselected = tester.getSize(find.byKey(const ValueKey('IT')));

    await tester.pumpWidget(wrapOfLanguages('IT'));
    await tester.pumpAndSettle();
    final selected = tester.getSize(find.byKey(const ValueKey('IT')));

    expect(selected, unselected);
  });

  testWidgets('selecting one chip moves none of the others', (tester) async {
    Map<String, Offset> positions() => {
      for (final language in kCardLanguages)
        language: tester.getTopLeft(find.byKey(ValueKey(language))),
    };

    await tester.pumpWidget(wrapOfLanguages('EN'));
    final before = positions();

    await tester.pumpWidget(wrapOfLanguages('IT'));
    await tester.pumpAndSettle();

    // The layout, not just the one chip: the reported symptom was the *other*
    // chips jumping, which is what a `Wrap` does when one child grows.
    expect(positions(), before);
  });
}
