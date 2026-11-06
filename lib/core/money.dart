/// Money formatting for the pricing screens.
///
/// Hand-written rather than `intl`, which is not in the approved stack: there
/// are exactly two currencies here, both shown to two decimal places with a
/// leading symbol, and nothing about that needs locale machinery.
///
/// The two are deliberately never combined. YGOPRODeck reports Cardmarket in
/// euros and everything else in US dollars, the app carries no exchange rate,
/// and inventing one would turn a stated estimate into a wrong number.
///
/// The decimal mark follows the interface language: a comma in Italian
/// (`€0,29`), a point in English. The symbol stays in front in both, so a
/// figure reads the same shape either way. The CSV writers do not use this
/// file, so exported numbers are always `0.29`, whatever the interface says.
library;

import '../models/app_language.dart';
import 'constants.dart';

/// Shown in place of a figure the API did not supply. A dash, deliberately not
/// `0.00`: a card with no known price is not a card worth nothing, and the
/// difference matters when the total below it says how many cards were skipped.
const String kNoPrice = '-';

/// Cardmarket, in euros.
String formatEur(double? value) => _format(value, '€');

/// TCGplayer and every `set_price`, in US dollars.
String formatUsd(double? value) => _format(value, r'$');

/// Null and non-positive both render as [kNoPrice], matching `parsePrice`,
/// which folds the API's very common `"0.00"` into null in the first place —
/// so a zero reaching here is a summed total of nothing, and reads the same.
String _format(double? value, String symbol) {
  if (value == null || !value.isFinite || value <= 0) return kNoPrice;
  final digits = value.toStringAsFixed(2);
  return switch (AppStrings.language) {
    AppLanguage.english => '$symbol$digits',
    AppLanguage.italian => '$symbol${digits.replaceFirst('.', ',')}',
  };
}
