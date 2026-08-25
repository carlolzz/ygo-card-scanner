import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/theme/tokens.dart';
import '../../models/app_settings.dart';
import '../../models/fast_log_field.dart';
import 'settings_providers.dart';

/// Which per-card details Fast log still asks about.
///
/// Its own route rather than a dialog on the Settings screen: the one dialog
/// Settings owns is a *confirmation* (`_ResyncSection._confirmResync`), and an
/// `AlertDialog` full of switches inherits OK/Cancel semantics the user would
/// reasonably expect. Honouring those would need local draft state plus a save,
/// i.e. a second source of truth for a preference, where every other settings
/// control in this app writes through immediately. A screen carries no such
/// implication, so each switch keeps the one-line [SettingsController] write.
///
/// It also keeps the three field names off the Settings screen, where they would
/// collide with the Defaults section's identical Condition/Edition/Language
/// labels and make every finder in a widget test ambiguous.
class FastLogScreen extends ConsumerWidget {
  const FastLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsControllerProvider);
    final palette = AppPalette.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.fastLogTitle)),
      body: settingsAsync.when(
        data: (settings) => _FastLogBody(settings: settings),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Text(
              '$error',
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.onSurfaceMuted),
            ),
          ),
        ),
      ),
    );
  }
}

class _FastLogBody extends ConsumerWidget {
  const _FastLogBody({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(settingsControllerProvider.notifier);
    final palette = AppPalette.of(context);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Text(
          AppStrings.fastLogIntro,
          style: TextStyle(color: palette.onSurfaceMuted),
        ),
        const SizedBox(height: AppSpacing.md),
        // At most one of these. The first answers "why do these switches do
        // nothing?"; the second is the degenerate configuration, which is
        // decided by `AppSettings.fastLogActive` and nowhere else.
        if (!settings.fastLogEnabled)
          Text(
            AppStrings.fastLogDisabledNote,
            style: TextStyle(color: palette.onSurfaceMuted),
          )
        else if (!settings.fastLogActive)
          Text(
            AppStrings.fastLogAllTickedNote,
            style: TextStyle(color: palette.accent),
          ),
        const SizedBox(height: AppSpacing.md),
        for (final field in FastLogField.values)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: palette.accent,
            // No subtitle: the intro above carries the "ticked means still
            // asked" semantics once, rather than three times over.
            title: Text(
              field.label,
              style: TextStyle(color: palette.onSurface),
            ),
            value: settings.fastLogFields.contains(field),
            // A closure rather than the tear-off the other switches use, since
            // the setter is parameterised by field. One call, no logic: the
            // rule itself lives on `AppSettings`.
            onChanged: (asked) =>
                controller.setFastLogField(field, asked: asked),
          ),
        const Divider(height: AppSpacing.xl),
        Text(
          AppStrings.fastLogSetNote,
          style: TextStyle(color: palette.onSurfaceMuted),
        ),
      ],
    );
  }
}
