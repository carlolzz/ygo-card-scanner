import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/theme/tokens.dart';
import '../../features/settings/settings_providers.dart';
import '../../models/card_language.dart';
import 'language_flag.dart';

/// Which language a card *name* is matched in.
///
/// Sits beside the search field on both search screens and in the collection's
/// app bar, and writes straight to the persisted [AppSettings.searchLanguage] —
/// the same arrangement as the collection's view menu: a preference with no
/// Settings row, whose control lives where its effect is visible. One
/// preference, one control per surface, so picking Italian here is picking it
/// everywhere.
///
/// **It changes what is matched, not what is shown.** Card names, artwork and
/// every downstream screen stay English; on the search screens a non-English
/// result carries its matched name as a second line so the row visibly contains
/// what was typed.
///
/// A [PopupMenuButton] rather than a `DropdownButton`, matching the sort and
/// View menus it sits among: a dropdown sizes its menu to the *button*, so a
/// compact control could only ever open a compact menu, and the full language
/// name had to live in the closed box to be readable at all. A popup menu is
/// sized to its own content, which is what lets the closed control shrink to a
/// flag and two letters while the menu still spells the languages out.
class SearchLanguagePicker extends ConsumerWidget {
  const SearchLanguagePicker({super.key, this.bare = false});

  /// The app-bar form: the flag glyph alone, with no box and no code. The
  /// boxed form is for sitting beside a search field, where it is styled to
  /// match it.
  final bool bare;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final language = ref.watch(searchLanguageProvider);

    return PopupMenuButton<String>(
      tooltip: AppStrings.searchLanguageLabel,
      initialValue: language,
      onSelected: ref
          .read(settingsControllerProvider.notifier)
          .setSearchLanguage,
      itemBuilder: (context) => [
        for (final code in kSearchLanguages)
          PopupMenuItem(
            value: code,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                LanguageFlag(language: code),
                const SizedBox(width: AppSpacing.sm),
                // The menu is the one place with room for the full name, and
                // "IT" alone is not obvious to everyone the flag is.
                Text(languageLabel(code)),
              ],
            ),
          ),
      ],
      child: bare
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: LanguageFlag(language: language),
            )
          : Container(
              // Matches the search field it sits next to: same fill, same
              // radius, same height.
              height: SearchLanguagePickerTokens.height,
              decoration: BoxDecoration(
                color: palette.surfaceRaised,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LanguageFlag(language: language),
                  const SizedBox(width: AppSpacing.xs),
                  // The code, not [languageLabel]: "English"/"Italian" is what
                  // made this control wider than the field beside it.
                  Text(language, style: TextStyle(color: palette.onSurface)),
                  Icon(
                    Icons.arrow_drop_down,
                    color: palette.onSurfaceMuted,
                    size: SearchLanguagePickerTokens.caretSize,
                  ),
                ],
              ),
            ),
    );
  }
}
