import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/core/constants.dart';
import 'package:ygo_scanner/models/printing.dart';
import 'package:ygo_scanner/shared/widgets/printing_picker.dart';

const _metalRaiders = Printing(
  id: 1,
  passcode: '44095762',
  setCode: 'MRD-EN094',
  setName: 'Metal Raiders',
  rarity: 'Super Rare',
);
const _darkSaviors = Printing(
  id: 2,
  passcode: '44095762',
  setCode: 'DASA-EN059',
  setName: 'Dark Saviors',
  rarity: 'Ultra Rare',
);

/// Pumps the picker with a mutable selection, returning a getter for whatever
/// the picker last reported.
Future<int? Function()> pumpPicker(
  WidgetTester tester, {
  int? initialSelection,
}) async {
  int? selected = initialSelection;
  await tester.pumpWidget(
    MaterialApp(
      home: StatefulBuilder(
        builder: (context, setState) => Scaffold(
          body: PrintingPicker(
            printings: const [_metalRaiders, _darkSaviors],
            selectedId: selected,
            noSetLabel: AppStrings.scanNoSetOption,
            onSelected: (id) => setState(() => selected = id),
          ),
        ),
      ),
    ),
  );
  return () => selected;
}

void main() {
  testWidgets('the options list stays closed until the box is tapped', (
    tester,
  ) async {
    await pumpPicker(tester);

    expect(find.text(_metalRaiders.displayLabel), findsNothing);

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    expect(find.text(_metalRaiders.displayLabel), findsOneWidget);
    expect(find.text(_darkSaviors.displayLabel), findsOneWidget);
    expect(find.text(AppStrings.scanNoSetOption), findsWidgets);
  });

  testWidgets('typing narrows the options to matching sets', (tester) async {
    await pumpPicker(tester);

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'metal');
    await tester.pumpAndSettle();

    expect(find.text(_metalRaiders.displayLabel), findsOneWidget);
    expect(find.text(_darkSaviors.displayLabel), findsNothing);
  });

  testWidgets('a query matching nothing says so', (tester) async {
    await pumpPicker(tester);

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'invasion of chaos');
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.setPickerNoMatches), findsOneWidget);
    expect(find.text(_metalRaiders.displayLabel), findsNothing);
  });

  testWidgets('tapping a result reports it and shows it in the box', (
    tester,
  ) async {
    final selection = await pumpPicker(tester);

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'dark');
    await tester.pumpAndSettle();
    await tester.tap(find.text(_darkSaviors.displayLabel));
    await tester.pumpAndSettle();

    expect(selection(), _darkSaviors.id);
    // The list closed and the field now reads as the chosen set.
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      _darkSaviors.displayLabel,
    );
  });

  testWidgets('"no specific set" clears an existing selection', (tester) async {
    final selection = await pumpPicker(tester, initialSelection: _metalRaiders.id);

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.scanNoSetOption).last);
    await tester.pumpAndSettle();

    expect(selection(), isNull);
  });

  testWidgets('an abandoned query does not read as a selection', (
    tester,
  ) async {
    final selection = await pumpPicker(tester, initialSelection: _metalRaiders.id);

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'dark');
    await tester.pumpAndSettle();

    // Blur without picking anything.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    expect(selection(), _metalRaiders.id);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      _metalRaiders.displayLabel,
    );
  });
}
