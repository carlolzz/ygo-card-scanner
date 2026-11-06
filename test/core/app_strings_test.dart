import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/core/constants.dart';
import 'package:ygo_scanner/core/money.dart';
import 'package:ygo_scanner/models/app_language.dart';
import 'package:ygo_scanner/models/app_theme_mode.dart';
import 'package:ygo_scanner/models/card_condition.dart';
import 'package:ygo_scanner/models/card_edition.dart';
import 'package:ygo_scanner/models/card_language.dart';
import 'package:ygo_scanner/models/collection_view_mode.dart';
import 'package:ygo_scanner/models/fast_log_field.dart';

void main() {
  // The language is process-wide state; nothing here may leak it into the
  // next test, which would expect English like the rest of the suite does.
  tearDown(() => AppStrings.select(AppLanguage.english));

  test('English is the language before anything selects one', () {
    expect(AppStrings.language, AppLanguage.english);
    expect(AppStrings.settingsTitle, 'Settings');
  });

  test('select switches every string at once', () {
    AppStrings.select(AppLanguage.italian);

    expect(AppStrings.language, AppLanguage.italian);
    expect(AppStrings.settingsTitle, 'Impostazioni');
    expect(AppStrings.homeTileLogCards, 'Registra carte');

    AppStrings.select(AppLanguage.english);
    expect(AppStrings.settingsTitle, 'Settings');
  });

  test('plurals follow the count in both languages', () {
    expect(AppStrings.statisticsValueUnpriced(1), '1 card has no price');
    expect(AppStrings.statisticsValueUnpriced(2), '2 cards have no price');

    AppStrings.select(AppLanguage.italian);
    expect(AppStrings.statisticsValueUnpriced(1), '1 carta non ha un prezzo');
    expect(AppStrings.statisticsValueUnpriced(2), '2 carte non hanno un prezzo');
    expect(
      AppStrings.statisticsValuePrintingPriced(1, 1),
      '1 di 1 riga valutata alla propria stampa',
    );
    expect(
      AppStrings.statisticsValuePrintingPriced(1, 3),
      '1 di 3 righe valutate alla propria stampa',
    );
  });

  test('the import summary owns its word order in each language', () {
    expect(AppStrings.statisticsImportAddedCount(3), '3 added');

    AppStrings.select(AppLanguage.italian);
    expect(AppStrings.statisticsImportAddedCount(3), '3 aggiunte');
    expect(AppStrings.statisticsImportMissingColumn('passcode', 'a, b'),
        contains('"passcode"'));
  });

  // The enums used to carry English literals on each member, which would not
  // have followed the setting at all.
  test('enum labels follow the interface language', () {
    AppStrings.select(AppLanguage.italian);

    expect(CardEdition.first.label, '1a Edizione');
    expect(AppThemeMode.dark.label, 'Scuro');
    expect(CollectionViewMode.minifyFull.label, 'Solo illustrazione');
    expect(FastLogField.language.label, 'Lingua');
    expect(languageLabel('DE'), 'Tedesco');
    // An unlisted code is echoed back unchanged, as before.
    expect(languageLabel('XX'), 'XX');
  });

  // Cardmarket's grade names are used as-is in every language, Italy included.
  test('grade names do not change with the language', () {
    final english = [for (final c in CardCondition.values) c.label];
    AppStrings.select(AppLanguage.italian);
    expect([for (final c in CardCondition.values) c.label], english);
  });

  test('the month names follow the language and keep twelve entries', () {
    expect(AppStrings.monthAbbreviations.first, 'Jan');
    AppStrings.select(AppLanguage.italian);
    expect(AppStrings.monthAbbreviations, hasLength(12));
    expect(AppStrings.monthAbbreviations[4], 'mag');
  });

  // Display only: the CSV writers format their own numbers, so an export
  // stays machine-readable whatever the interface says.
  test('Italian prices use a decimal comma', () {
    expect(formatEur(0.29), '€0.29');

    AppStrings.select(AppLanguage.italian);
    expect(formatEur(0.29), '€0,29');
    expect(formatUsd(74.49), r'$74,49');
    expect(formatEur(null), kNoPrice);
  });

  // Developer readout: kept in English so a screenshot from either language
  // can be read against the code that wrote it.
  test('the scan diagnostics lines stay in English', () {
    AppStrings.select(AppLanguage.italian);
    expect(AppStrings.scanDiagnosticsDetected, 'card detected');
  });
}
