import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/theme/tokens.dart';
import '../../models/collection_view_mode.dart';
import '../settings/settings_providers.dart';
import 'collection_filter_sheet.dart';
import 'collection_providers.dart';

/// Search box, then one row: the filter button on the left and the minify menu
/// on the right.
///
/// It used to be the search box plus two horizontally-scrolling chip rows
/// (condition, then rarity with the sort dropdown tacked on the end). Those
/// could only ever expose the two filters that fitted, and every new filter
/// would have cost another scrolling row of screen the list needs. The sheet
/// holds all of them without taking any height at all when closed.
class CollectionFilterBar extends ConsumerWidget {
  const CollectionFilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(collectionFilterControllerProvider);
    final controller = ref.read(collectionFilterControllerProvider.notifier);
    final palette = AppPalette.of(context);
    final activeCount = filter.activeCount;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            style: TextStyle(color: palette.onSurface),
            decoration: InputDecoration(
              hintText: AppStrings.collectionSearchHint,
              hintStyle: TextStyle(color: palette.onSurfaceMuted),
              prefixIcon: Icon(Icons.search, color: palette.onSurfaceMuted),
              filled: true,
              fillColor: palette.surfaceRaised,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: controller.setNameQuery,
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => showCollectionFilterSheet(context, ref),
                  icon: const Icon(Icons.tune, size: 18),
                  label: Text(
                    activeCount == 0
                        ? AppStrings.collectionFiltersButton
                        // The count is the whole reason the button can replace
                        // the chip rows: with the controls hidden, nothing else
                        // would show that the list is narrowed.
                        : '${AppStrings.collectionFiltersButton} ($activeCount)',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: activeCount == 0
                        ? palette.onSurface
                        : palette.accent,
                    side: BorderSide(
                      color: activeCount == 0 ? palette.divider : palette.accent,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              const Expanded(child: _MinifyMenu()),
            ],
          ),
        ],
      ),
    );
  }
}

/// The view-density menu. Its own widget so the selected mode is read once and
/// used for both the label and the checkmark.
class _MinifyMenu extends ConsumerWidget {
  const _MinifyMenu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final mode =
        ref.watch(settingsControllerProvider).value?.collectionViewMode ??
        CollectionViewMode.standard;

    return PopupMenuButton<CollectionViewMode>(
      tooltip: AppStrings.collectionMinifyTooltip,
      initialValue: mode,
      onSelected: ref
          .read(settingsControllerProvider.notifier)
          .setCollectionViewMode,
      itemBuilder: (context) => [
        for (final option in CollectionViewMode.values)
          PopupMenuItem(value: option, child: Text(option.label)),
      ],
      child: Container(
        height: AppTapTarget.minSize - AppSpacing.md,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        decoration: BoxDecoration(
          border: Border.all(
            color: mode == CollectionViewMode.standard
                ? palette.divider
                : palette.accent,
          ),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              mode == CollectionViewMode.standard
                  ? Icons.view_list
                  : Icons.grid_view,
              size: 18,
              color: mode == CollectionViewMode.standard
                  ? palette.onSurface
                  : palette.accent,
            ),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                AppStrings.collectionMinifyButton,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: mode == CollectionViewMode.standard
                      ? palette.onSurface
                      : palette.accent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
