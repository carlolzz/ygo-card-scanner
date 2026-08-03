import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../models/card_language.dart';

/// The small flag marking a collection entry's language.
///
/// A Unicode regional-indicator pair rendered as plain [Text] — no package, no
/// asset, no font bundled. On Android and iOS the system emoji font draws it as
/// a flag; anywhere without that coverage (Windows desktop, the test
/// environment) it falls back to the two letters of the country code, which is
/// still readable. That is a font property rather than a layout one, and the
/// shipped target is Android.
///
/// A language code that names no country at all — `AE` (Asian-English), or
/// anything a CSV import brought in — has no flag to draw, so it renders the
/// code itself in an outlined badge shaped like the grade chip beside it. See
/// [kCardLanguageFlags].
class LanguageFlag extends StatelessWidget {
  const LanguageFlag({super.key, required this.language, this.color});

  /// The raw `collection_entries.language` value: free-form TEXT, so this must
  /// tolerate any string.
  final String language;

  /// Ink for the fallback badge. Defaults to the palette's body colour; the
  /// grid cells pass a fixed light colour because their badge sits on a dark
  /// scrim over card art rather than on app chrome.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ink = color ?? AppPalette.of(context).onSurface;
    final flag = languageFlag(language);

    // The name, not the glyph: a flag is silent to a screen reader, and the raw
    // code isn't much better.
    return Semantics(
      label: languageLabel(language),
      excludeSemantics: true,
      child: flag != null
          ? Text(
              flag,
              style: const TextStyle(fontSize: LanguageFlagTokens.fontSize),
            )
          : Container(
              padding: const EdgeInsets.symmetric(
                horizontal: ConditionChipTokens.horizontalPadding,
                vertical: ConditionChipTokens.verticalPadding,
              ),
              decoration: BoxDecoration(
                border: Border.all(
                  color: ink,
                  width: LanguageFlagTokens.fallbackBorderWidth,
                ),
                borderRadius: BorderRadius.circular(ConditionChipTokens.radius),
              ),
              child: Text(
                language.toUpperCase(),
                style: TextStyle(
                  color: ink,
                  fontSize: LanguageFlagTokens.fallbackFontSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
    );
  }
}
