import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/core/constants.dart';
import 'package:ygo_scanner/shared/widgets/search_field.dart';

void main() {
  Future<List<String>> pump(
    WidgetTester tester, {
    String initialValue = '',
  }) async {
    final reported = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchField(
            hintText: 'Search',
            initialValue: initialValue,
            onChanged: reported.add,
          ),
        ),
      ),
    );
    return reported;
  }

  Finder clearButton() => find.byTooltip(AppStrings.searchClearTooltip);

  testWidgets('there is no clear button while the field is empty', (
    tester,
  ) async {
    await pump(tester);
    expect(clearButton(), findsNothing);
  });

  testWidgets('typing shows the clear button and reports the text', (
    tester,
  ) async {
    final reported = await pump(tester);

    await tester.enterText(find.byType(TextField), 'Blue');
    await tester.pump();

    expect(reported, ['Blue']);
    expect(clearButton(), findsOneWidget);
  });

  // `TextEditingController.clear()` does not fire `onChanged`, so without the
  // explicit report the field would empty while the list stayed filtered.
  testWidgets('the clear button empties the field and reports it', (
    tester,
  ) async {
    final reported = await pump(tester);
    await tester.enterText(find.byType(TextField), 'Blue');
    await tester.pump();

    await tester.tap(clearButton());
    await tester.pump();

    expect(reported, ['Blue', '']);
    expect(find.text('Blue'), findsNothing);
    expect(clearButton(), findsNothing);
  });

  testWidgets('a seeded value is shown and can be cleared', (tester) async {
    final reported = await pump(tester, initialValue: 'Dark');

    expect(find.text('Dark'), findsOneWidget);
    expect(clearButton(), findsOneWidget);

    await tester.tap(clearButton());
    await tester.pump();

    expect(reported, ['']);
  });
}
