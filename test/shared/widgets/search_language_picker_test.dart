import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/core/theme/tokens.dart';
import 'package:ygo_scanner/features/settings/settings_providers.dart';
import 'package:ygo_scanner/models/card_language.dart';
import 'package:ygo_scanner/shared/widgets/search_language_picker.dart';

/// Only [searchLanguageProvider] is overridden: the picker reads that to render
/// and only touches the settings notifier when something is *picked*, which the
/// end-to-end persistence case in `add_card_screen_test` already covers.
Future<void> pumpPicker(
  WidgetTester tester, {
  String language = kDefaultSearchLanguage,
  bool bare = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [searchLanguageProvider.overrideWithValue(language)],
      child: MaterialApp(
        home: Scaffold(
          body: Center(child: SearchLanguagePicker(bare: bare)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // The complaint this widget was rebuilt for: the closed control used to carry
  // "English" / "Italian", which made it wider than the field beside it and
  // dragged the menu (sized to the button by `DropdownButton`) out with it.
  testWidgets('the closed control carries the code, not the language name', (
    tester,
  ) async {
    await pumpPicker(tester);

    expect(find.text('EN'), findsOneWidget);
    expect(find.text(languageLabel('EN')), findsNothing);
  });

  testWidgets('the menu spells the languages out', (tester) async {
    await pumpPicker(tester);

    await tester.tap(find.byType(SearchLanguagePicker));
    await tester.pumpAndSettle();

    // The one place with room for the full name. Every searchable language is
    // offered, so the menu can never hide one the build ships an asset for.
    for (final code in kSearchLanguages) {
      expect(find.text(languageLabel(code)), findsOneWidget);
    }
  });

  testWidgets('it renders the selected language, not always the default', (
    tester,
  ) async {
    await pumpPicker(tester, language: 'IT');

    expect(find.text('IT'), findsOneWidget);
    expect(find.text('EN'), findsNothing);
  });

  // Pinned because it is the whole point of the token: the boxed form sits in a
  // Row beside a filled TextField, and a mismatch here reads as a misaligned
  // control rather than as a wrong number.
  testWidgets('the boxed form matches the search field height', (tester) async {
    await pumpPicker(tester);

    expect(
      tester.getSize(find.byType(SearchLanguagePicker)).height,
      SearchLanguagePickerTokens.height,
    );
  });

  testWidgets('the bare form is the flag alone', (tester) async {
    await pumpPicker(tester, bare: true);

    // No code and no box: in an app bar it is one small symbol among the sort
    // icons, and the tooltip is what names it.
    expect(find.text('EN'), findsNothing);
    expect(find.byType(SearchLanguagePicker), findsOneWidget);
  });
}
