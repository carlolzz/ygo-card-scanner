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
      // Vertical padding as well as horizontal, which is what keeps the
      // button's own ink inside this container's rounded border. With the
      // underline hidden the button is wrapped in an `InkWell` that paints its
      // focus highlight across the whole box, and the button's own padding is
      // zero, so with a horizontal-only inset that highlight ran edge to edge
      // the moment the menu was opened.
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: language,
          // The selected value renders in an `IndexedStack` sized to the widest
          // item, so without this the shorter label sits left of centre in a
          // box shaped by the longer one.
          alignment: AlignmentDirectional.center,
          // Otherwise `itemHeight` pins the button at kMinInteractiveDimension
          // (48) and the added vertical padding makes this taller than the
          // search field it sits beside.
          isDense: true,
          // The container already reads as one control; a second highlight
          // inside it just looks like the box growing.
          focusColor: Colors.transparent,
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
