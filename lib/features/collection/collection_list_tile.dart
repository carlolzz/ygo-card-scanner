import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../models/collection_entry_with_card.dart';
import '../../shared/widgets/card_thumbnail.dart';

/// One row in the collection list. Pure presentation — mutations flow up via
/// callbacks, mirroring `HomeMenuTile`.
class CollectionListTile extends StatelessWidget {
  const CollectionListTile({
    super.key,
    required this.entryWithCard,
    required this.onTap,
    required this.onIncrement,
    required this.onDecrement,
    required this.onDelete,
  });

  final CollectionEntryWithCard entryWithCard;
  final VoidCallback onTap;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onDelete;

  String _subtitle(CollectionEntryWithCard entryWithCard) {
    final printing = entryWithCard.printing;
    final setLabel = printing?.setCode ?? printing?.setName;
    if (setLabel == null) return entryWithCard.entry.edition.label;
    return '$setLabel · ${entryWithCard.entry.edition.label}';
  }

  @override
  Widget build(BuildContext context) {
    final entry = entryWithCard.entry;
    final card = entryWithCard.card;
    final conditionColor =
        ConditionChipColors.byShortCode[entry.condition.shortCode]!;

    final palette = AppPalette.of(context);
    return Material(
      color: palette.surfaceRaised,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppTapTarget.minSize),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              // Centre the leading condition chip + art against the (taller)
              // name/quantity column, so they sit in the middle of the row
              // rather than hugging the top.
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Grade first, then the art: the chip is what the eye scans a
                // list of duplicates for, so it leads the row.
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: conditionColor,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(
                    entry.condition.shortCode,
                    style: const TextStyle(
                      color: ConditionChipColors.onSelected,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                // The whole card, uncropped (a portrait card box + contain),
                // rather than the default square centre-crop.
                CardThumbnail(
                  localImagePath: card.localImagePath,
                  aspectRatio: ScanReticleTokens.cardAspectRatio,
                  fit: BoxFit.contain,
                ),
                const SizedBox(width: AppSpacing.md),
                // Name (up to 2 lines) + edition (1 line), centred over the
                // quantity/delete controls; the name gets the row's full
                // remaining width instead of being squeezed against the buttons.
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        card.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: palette.onSurface),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        _subtitle(entryWithCard),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: palette.onSurfaceMuted),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            color: palette.onSurfaceMuted,
                            onPressed: onDecrement,
                          ),
                          Text(
                            '${entry.quantity}',
                            style: TextStyle(color: palette.onSurface),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            color: palette.accent,
                            onPressed: onIncrement,
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            color: palette.onSurfaceMuted,
                            onPressed: onDelete,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
