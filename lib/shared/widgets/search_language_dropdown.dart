import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/theme/tokens.dart';
import '../../features/settings/settings_providers.dart';
import '../../models/card_language.dart';

/// Which language the card search matches names in.
///
/// Sits beside the search field on both search screens, and writes straight to
/// the persisted [AppSettings.searchLanguage] — the same arrangement as the
/// collection's view menu: a preference with no Settings row, whose control
/// lives where its effect is visible.
///
/// **It changes what is matched, not what is shown.** Card names, artwork and
/// every downstream screen stay English; a non-English result carries its
/// matched name as a second line so the row visibly contains what was typed.
class SearchLanguageDropdown extends ConsumerWidget {
  const SearchLanguageDropdown({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final language = ref.watch(searchLanguageProvider);

    return Container(
      // Matches the search field it sits next to: same fill, same radius.
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: language,
          // The field beside this one is `filled`, which paints its own
          // background; without this the menu would open over a transparent
          // surface on some platforms.
          dropdownColor: palette.surfaceRaised,
          iconEnabledColor: palette.onSurfaceMuted,
          style: TextStyle(color: palette.onSurface),
          borderRadius: BorderRadius.circular(AppRadius.md),
          items: [
            for (final code in kSearchLanguages)
              DropdownMenuItem(
                value: code,
                child: Text(
                  languageLabel(code),
                  semanticsLabel:
                      '${AppStrings.searchLanguageLabel}: '
                      '${languageLabel(code)}',
                ),
              ),
          ],
          onChanged: (value) {
            if (value == null) return;
            ref
                .read(settingsControllerProvider.notifier)
                .setSearchLanguage(value);
          },
        ),
      ),
    );
  }
}
