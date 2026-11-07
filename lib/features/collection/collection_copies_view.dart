import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/theme/tokens.dart';
import '../../models/card_language.dart';
import '../../models/card_terms.dart';
import '../../shared/widgets/card_details_view.dart';
import '../../shared/widgets/language_flag.dart';
import '../pricing/card_prices_view.dart' show formatFetchedAt;
import 'collection_providers.dart';

/// The Copies tab: every copy held of one card, whatever the set, grade or
/// language.
///
/// The screen around it is opened on a single `collection_entries` row, and one
/// card is often several of those. This tab is where they are seen together.
/// It is read-only, and the screen's app-bar edit and delete act on
/// [currentEntryId] alone, so that row is marked.
class CollectionCopiesView extends ConsumerWidget {
  const CollectionCopiesView({
    super.key,
    required this.passcode,
    required this.currentEntryId,
  });

  final String passcode;

  /// The entry the screen was opened on.
  final int? currentEntryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copies = ref.watch(ownedCopiesProvider(passcode)).value;
    if (copies == null) return const SizedBox.shrink();

    final palette = AppPalette.of(context);
    final total = copies.fold<int>(0, (sum, c) => sum + c.entry.quantity);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Text(
          AppStrings.collectionCopiesTotal(total),
          style: TextStyle(
            color: palette.onSurface,
            fontWeight: FontWeight.bold,
            fontSize: CardDetailTokens.sectionFontSize,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _LanguageBreakdown(copies: copies),
        for (final copy in copies)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: _CopyBlock(
              copy: copy,
              isCurrent: copy.entry.id == currentEntryId,
            ),
          ),
      ],
    );
  }
}

/// Per-language totals, shown only when the card is held in more than one.
/// Passcodes are language-independent, so the same card in English and German
/// lives as two rows under one passcode, and this is where they are reunited.
class _LanguageBreakdown extends StatelessWidget {
  const _LanguageBreakdown({required this.copies});

  final List<OwnedCopy> copies;

  @override
  Widget build(BuildContext context) {
    final byLanguage = <String, int>{};
    for (final copy in copies) {
      byLanguage[copy.entry.language] =
          (byLanguage[copy.entry.language] ?? 0) + copy.entry.quantity;
    }
    if (byLanguage.length < 2) return const SizedBox.shrink();

    final languages = byLanguage.keys.toList()..sort();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppStrings.collectionByLanguageLabel,
            style: TextStyle(
              color: AppPalette.of(context).onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final language in languages)
            CardDetailRow(
              label: languageLabel(language),
              valueLeading: LanguageFlag(language: language),
              value: '×${byLanguage[language]}',
            ),
        ],
      ),
    );
  }
}

/// One entry: its grade and count, then everything else recorded about it.
class _CopyBlock extends StatelessWidget {
  const _CopyBlock({required this.copy, required this.isCurrent});

  final OwnedCopy copy;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final entry = copy.entry;
    final printing = copy.printing;
    final setLabel = printing?.setLabel ?? '';
    final rarity = printing?.rarity;
    final notes = entry.notes;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: isCurrent ? Border.all(color: palette.accent) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: ConditionChipColors
                      .byShortCode[entry.condition.shortCode]!,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  entry.condition.label,
                  style: const TextStyle(
                    color: ConditionChipColors.onSelected,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (isCurrent) ...[
                const SizedBox(width: AppSpacing.sm),
                Text(
                  AppStrings.collectionCopiesThisEntry,
                  style: TextStyle(color: palette.accent),
                ),
              ],
              const Spacer(),
              Text(
                '×${entry.quantity}',
                style: TextStyle(
                  color: palette.onSurface,
                  fontWeight: FontWeight.bold,
                  fontSize: CardDetailTokens.sectionFontSize,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          CardDetailRow(
            label: AppStrings.collectionSetLabel,
            value: setLabel.isEmpty
                ? AppStrings.collectionCopiesNoSet
                : setLabel,
          ),
          if (rarity != null)
            CardDetailRow(
              label: AppStrings.collectionRarityLabel,
              value: rarityLabel(rarity),
            ),
          CardDetailRow(
            label: AppStrings.collectionEditionLabel,
            value: entry.edition.label,
          ),
          CardDetailRow(
            label: AppStrings.collectionLanguageLabel,
            valueLeading: LanguageFlag(language: entry.language),
            value: languageLabel(entry.language),
          ),
          CardDetailRow(
            label: AppStrings.collectionCopiesAddedLabel,
            value: formatFetchedAt(
              DateTime.fromMillisecondsSinceEpoch(entry.createdAt),
            ),
          ),
          if (notes != null && notes.isNotEmpty)
            CardDetailRow(
              label: AppStrings.collectionCopiesNotesLabel,
              value: notes,
            ),
        ],
      ),
    );
  }
}
