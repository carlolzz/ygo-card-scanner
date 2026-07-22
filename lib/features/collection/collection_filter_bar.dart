import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/theme/tokens.dart';
import '../../data/db/dao/collection_dao.dart';
import '../../models/card_condition.dart';
import '../../models/card_edition.dart';
import '../../shared/widgets/labeled_choice_chip.dart';
import 'collection_providers.dart';

/// Search field + condition/edition filter chips + sort control, all backed
/// by [CollectionFilterController]. `cardType` isn't exposed here — there's
/// no DAO method to enumerate distinct types, and it isn't essential for a
/// first pass.
class CollectionFilterBar extends ConsumerWidget {
  const CollectionFilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(collectionFilterControllerProvider);
    final controller = ref.read(collectionFilterControllerProvider.notifier);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            style: const TextStyle(color: AppColors.onSurface),
            decoration: InputDecoration(
              hintText: AppStrings.collectionSearchHint,
              hintStyle: const TextStyle(color: AppColors.onSurfaceMuted),
              prefixIcon: const Icon(
                Icons.search,
                color: AppColors.onSurfaceMuted,
              ),
              filled: true,
              fillColor: AppColors.surfaceRaised,
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
                  selectedColor: AppColors.accent,
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
                  selected: filter.edition == null,
                  selectedColor: AppColors.accent,
                  onSelected: () => controller.setEdition(null),
                ),
                for (final edition in CardEdition.values) ...[
                  const SizedBox(width: AppSpacing.xs),
                  LabeledChoiceChip(
                    label: edition.label,
                    selected: filter.edition == edition,
                    selectedColor: AppColors.accent,
                    onSelected: () => controller.setEdition(edition),
                  ),
                ],
                const SizedBox(width: AppSpacing.md),
                DropdownButton<CollectionSortBy>(
                  value: filter.sortBy,
                  dropdownColor: AppColors.surfaceRaised,
                  underline: const SizedBox.shrink(),
                  style: const TextStyle(color: AppColors.onSurface),
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
