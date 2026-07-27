import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/theme/tokens.dart';
import '../../data/db/dao/collection_dao.dart';
import '../../models/card_condition.dart';
import '../../shared/widgets/labeled_choice_chip.dart';
import 'collection_providers.dart';

/// Search field + condition/rarity filter chips + sort control, all backed
/// by [CollectionFilterController]. `cardType` isn't exposed here — there's
/// no DAO method to enumerate distinct types, and it isn't essential for a
/// first pass.
class CollectionFilterBar extends ConsumerWidget {
  const CollectionFilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(collectionFilterControllerProvider);
    final controller = ref.read(collectionFilterControllerProvider.notifier);
    final palette = AppPalette.of(context);

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
              prefixIcon: Icon(
                Icons.search,
                color: palette.onSurfaceMuted,
              ),
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
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                LabeledChoiceChip(
                  label: AppStrings.collectionFilterAll,
                  selected: filter.condition == null,
                  selectedColor: palette.accent,
                  onSelected: () => controller.setCondition(null),
                ),
                for (final condition in CardCondition.values) ...[
                  const SizedBox(width: AppSpacing.xs),
                  LabeledChoiceChip(
                    label: condition.shortCode,
                    selected: filter.condition == condition,
                    selectedColor:
                        ConditionChipColors.byShortCode[condition
                            .shortCode]!,
                    onSelected: () => controller.setCondition(condition),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                LabeledChoiceChip(
                  label: AppStrings.collectionFilterAll,
                  selected: filter.rarity == null,
                  selectedColor: palette.accent,
                  onSelected: () => controller.setRarity(null),
                ),
                // Only the rarities actually held, so no chip is ever dead.
                // `.value`, not `when`: an unresolved (or refetching) load
                // leaves the bar's height alone instead of flashing a spinner,
                // the same reading the scan review gate's set picker uses.
                for (final rarity
                    in ref.watch(collectionRarityOptionsProvider).value ??
                        const <String?>[]) ...[
                  const SizedBox(width: AppSpacing.xs),
                  _RarityChip(rarity: rarity, selected: filter.rarity),
                ],
                const SizedBox(width: AppSpacing.md),
                DropdownButton<CollectionSortBy>(
                  value: filter.sortBy,
                  dropdownColor: palette.surfaceRaised,
                  underline: const SizedBox.shrink(),
                  style: TextStyle(color: palette.onSurface),
                  items: const [
                    DropdownMenuItem(
                      value: CollectionSortBy.name,
                      child: Text(AppStrings.collectionSortByName),
                    ),
                    DropdownMenuItem(
                      value: CollectionSortBy.dateAdded,
                      child: Text(AppStrings.collectionSortByDateAdded),
                    ),
                    DropdownMenuItem(
                      value: CollectionSortBy.quantity,
                      child: Text(AppStrings.collectionSortByQuantity),
                    ),
                  ],
                  onChanged: (sortBy) {
                    if (sortBy != null) controller.setSortBy(sortBy);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One chip in the rarity filter row. Its own widget so the [RarityFilter] it
/// stands for is built once and used for both the selected test and the tap —
/// [rarity] being nullable (null = "no rarity") makes that easy to get subtly
/// wrong inline.
class _RarityChip extends ConsumerWidget {
  const _RarityChip({required this.rarity, required this.selected});

  /// The rarity this chip filters on, or null for "no rarity".
  final String? rarity;

  /// The filter row's current selection, or null when it is on "All".
  final RarityFilter? selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = rarity == null
        ? const RarityFilter.noRarity()
        : RarityFilter.value(rarity!);
    return LabeledChoiceChip(
      label: rarity ?? AppStrings.collectionFilterNoRarity,
      selected: selected == value,
      selectedColor: AppPalette.of(context).accent,
      onSelected: () => ref
          .read(collectionFilterControllerProvider.notifier)
          .setRarity(value),
    );
  }
}
