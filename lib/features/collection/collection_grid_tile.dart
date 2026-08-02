import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../models/collection_entry_with_card.dart';
import '../../shared/widgets/card_thumbnail.dart';

/// One cell in a minified collection grid: the artwork, optionally captioned
/// with the card's name, and a quantity badge when more than one copy is held.
///
/// **Deliberately carries no add/remove/delete controls.** Those live on the
/// standard row and the detail screen; putting them here would defeat the point
/// of minifying, and three 30pt buttons under an 84pt thumbnail would be a
/// larger cell than the row it replaced. Tapping opens the detail screen, where
/// everything is editable.
class CollectionGridTile extends StatelessWidget {
  const CollectionGridTile({
    super.key,
    required this.entryWithCard,
    required this.showName,
    required this.onTap,
  });

  final CollectionEntryWithCard entryWithCard;

  /// Whether to caption the artwork with the card's name.
  final bool showName;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final entry = entryWithCard.entry;
    final card = entryWithCard.card;

    return Material(
      color: palette.surfaceRaised,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CardThumbnail(
                    localImagePath: card.localImagePath,
                    // Null: the cell's width drives the size, which is the
                    // whole reason `CardThumbnail.size` became nullable.
                    size: null,
                    aspectRatio: ScanReticleTokens.cardAspectRatio,
                    fit: BoxFit.contain,
                  ),
                  // The one ownership fact a minified cell must not lose: with
                  // no quantity control visible, a stack of three would
                  // otherwise be indistinguishable from a single copy.
                  if (entry.quantity > 1)
                    Positioned(
                      right: 2,
                      bottom: 2,
                      child: _QuantityBadge(quantity: entry.quantity),
                    ),
                ],
              ),
            ),
            if (showName)
              SizedBox(
                height: CollectionGridTokens.nameCaptionHeight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: 2,
                  ),
                  child: Text(
                    card.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: palette.onSurface,
                      fontSize: CollectionGridTokens.nameFontSize,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The `xN` badge over a cell's artwork. Scrimmed rather than palette-coloured
/// because it sits on card art, which is any colour at all.
class _QuantityBadge extends StatelessWidget {
  const _QuantityBadge({required this.quantity});

  final int quantity;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ConditionChipTokens.horizontalPadding,
        vertical: ConditionChipTokens.verticalPadding,
      ),
      decoration: BoxDecoration(
        color: AppPalette.dark.background.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(ConditionChipTokens.radius),
      ),
      child: Text(
        'x$quantity',
        style: TextStyle(
          color: AppPalette.dark.onSurface,
          fontSize: ConditionChipTokens.fontSize,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
