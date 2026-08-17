import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/theme/tokens.dart';
import '../../data/repositories/card_repository.dart';
import '../../models/app_settings.dart';
import '../../models/app_theme_mode.dart';
import '../../models/card_condition.dart';
import '../../models/card_edition.dart';
import '../../models/card_language.dart';
import '../../shared/widgets/labeled_choice_chip.dart';
import '../sync/initial_sync_providers.dart';
import 'settings_providers.dart';

/// Defaults for newly logged cards, appearance, and card-database maintenance.
///
/// All writes go through [SettingsController]/[ResyncController]; this file
/// only renders and dispatches.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsControllerProvider);
    final palette = AppPalette.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.settingsTitle)),
      body: settingsAsync.when(
        data: (settings) => _SettingsBody(settings: settings),
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

class _SettingsBody extends ConsumerWidget {
  const _SettingsBody({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(settingsControllerProvider.notifier);
    final palette = AppPalette.of(context);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        const _SectionHeader(title: AppStrings.settingsDefaultsSection),
        Text(
          AppStrings.settingsDefaultsDescription,
          style: TextStyle(color: palette.onSurfaceMuted),
        ),
        const SizedBox(height: AppSpacing.md),
        const _FieldLabel(label: AppStrings.settingsConditionLabel),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final condition in CardCondition.values)
              LabeledChoiceChip(
                label: condition.shortCode,
                selected: settings.defaultCondition == condition,
                selectedColor:
                    ConditionChipColors.byShortCode[condition.shortCode]!,
                onSelected: () => controller.setDefaultCondition(condition),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        const _FieldLabel(label: AppStrings.settingsEditionLabel),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final edition in CardEdition.values)
              LabeledChoiceChip(
                label: edition.label,
                selected: settings.defaultEdition == edition,
                selectedColor: palette.accent,
                onSelected: () => controller.setDefaultEdition(edition),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        const _FieldLabel(label: AppStrings.settingsLanguageLabel),
        DropdownButton<String>(
          value: settings.language,
          dropdownColor: palette.surfaceRaised,
          style: TextStyle(color: palette.onSurface),
          items: [
            for (final language in kCardLanguages)
              DropdownMenuItem(value: language, child: Text(language)),
          ],
          onChanged: (language) {
            if (language != null) controller.setLanguage(language);
          },
        ),
        const Divider(height: AppSpacing.xl),
        const _SectionHeader(title: AppStrings.settingsAppearanceSection),
        const _FieldLabel(label: AppStrings.settingsThemeLabel),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final mode in AppThemeMode.values)
              LabeledChoiceChip(
                label: mode.label,
                selected: settings.themeMode == mode,
                selectedColor: palette.accent,
                onSelected: () => controller.setThemeMode(mode),
              ),
          ],
        ),
        const Divider(height: AppSpacing.xl),
        const _SectionHeader(title: AppStrings.settingsCollectionSection),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          activeThumbColor: palette.accent,
          title: Text(
            AppStrings.settingsConfirmDeleteLabel,
            style: TextStyle(color: palette.onSurface),
          ),
          subtitle: Text(
            AppStrings.settingsConfirmDeleteDescription,
            style: TextStyle(color: palette.onSurfaceMuted),
          ),
          value: settings.confirmBeforeDelete,
          onChanged: controller.setConfirmBeforeDelete,
        ),
        const Divider(height: AppSpacing.xl),
        const _SectionHeader(title: AppStrings.settingsScanningSection),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          activeThumbColor: palette.accent,
          title: Text(
            AppStrings.settingsDiagnosticsLabel,
            style: TextStyle(color: palette.onSurface),
          ),
          subtitle: Text(
            AppStrings.settingsDiagnosticsDescription,
            style: TextStyle(color: palette.onSurfaceMuted),
          ),
          value: settings.showScanDiagnostics,
          onChanged: controller.setShowScanDiagnostics,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          activeThumbColor: palette.accent,
          title: Text(
            AppStrings.settingsScanHelpLabel,
            style: TextStyle(color: palette.onSurface),
          ),
          subtitle: Text(
            AppStrings.settingsScanHelpDescription,
            style: TextStyle(color: palette.onSurfaceMuted),
          ),
          value: settings.showScanHelp,
          onChanged: controller.setShowScanHelp,
        ),
        const Divider(height: AppSpacing.xl),
        const _SectionHeader(title: AppStrings.settingsDatabaseSection),
        const _ResyncSection(),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        title,
        style: TextStyle(
          color: AppPalette.of(context).onSurface,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Text(
        label,
        style: TextStyle(color: AppPalette.of(context).onSurfaceMuted),
      ),
    );
  }
}

/// "Last synced" plus a re-sync behind a confirmation. Progress renders in
/// place — unlike the first-launch gate, nothing here blocks the user, who can
/// leave the screen while it runs.
class _ResyncSection extends ConsumerWidget {
  const _ResyncSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lastSyncedAsync = ref.watch(lastSyncedAtProvider);
    final resync = ref.watch(resyncControllerProvider);
    final palette = AppPalette.of(context);
    final running = resync?.status == InitialSyncStatus.running;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${AppStrings.settingsLastSyncedLabel}: '
          '${_lastSyncedLabel(lastSyncedAsync.value)}',
          style: TextStyle(color: palette.onSurfaceMuted),
        ),
        const SizedBox(height: AppSpacing.md),
        if (running) ...[
          LinearProgressIndicator(value: resync!.progress),
          const SizedBox(height: AppSpacing.sm),
          Text(
            resync.phase == SyncPhase.writing
                ? AppStrings.syncWritingMessage
                : AppStrings.syncFetchingMessage,
            style: TextStyle(color: palette.onSurfaceMuted),
          ),
        ] else ...[
          if (resync?.status == InitialSyncStatus.failure) ...[
            Text(
              AppStrings.syncErrorMessage,
              style: TextStyle(color: palette.onSurfaceMuted),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => _confirmResync(context, ref),
              child: const Text(AppStrings.settingsResyncButton),
            ),
          ),
        ],
      ],
    );
  }

  /// A full re-download is worth a deliberate tap: it costs several megabytes
  /// and is easy to hit by accident on a settings list.
  Future<void> _confirmResync(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppStrings.settingsResyncDialogTitle),
        content: const Text(AppStrings.settingsResyncDialogMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(AppStrings.settingsResyncDialogCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(AppStrings.settingsResyncDialogConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(resyncControllerProvider.notifier).start();
    if (!context.mounted) return;
    if (ref.read(resyncControllerProvider)?.status ==
        InitialSyncStatus.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.settingsResyncDoneMessage)),
      );
    }
  }

  String _lastSyncedLabel(DateTime? at) {
    if (at == null) return AppStrings.settingsNeverSynced;
    final local = at.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}
