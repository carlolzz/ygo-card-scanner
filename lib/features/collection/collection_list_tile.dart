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

  /// The set/expansion line: the set code, or its name when the printing
  /// carries no code. Null when this entry has no printing at all, in which
  /// case the line is simply omitted.
  String? get _setLine {
    final printing = entryWithCard.printing;
    return printing?.setCode ?? printing?.setName;
  }

  /// The rarity, on its own line below the set. Rarity — not edition — is what
  /// the eye looks for when scanning a list of reprints; the edition lives on
  /// the detail screen.
  String? get _rarityLine => entryWithCard.printing?.rarity;

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
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: CollectionTileTokens.verticalPadding,
            ),
            child: Row(
              // Everything is centred against the (tallest) action column, so
              // the chip, the art, the name block and the quantity all sit on
              // the row's midline — which is also where the middle action
              // button (remove) lands.
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Grade first, then the art: the chip is what the eye scans a
                // list of duplicates for, so it leads the row.
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ConditionChipTokens.horizontalPadding,
                    vertical: ConditionChipTokens.verticalPadding,
                  ),
                  decoration: BoxDecoration(
                    color: conditionColor,
                    borderRadius: BorderRadius.circular(
                      ConditionChipTokens.radius,
                    ),
                  ),
                  child: Text(
                    entry.condition.shortCode,
                    style: const TextStyle(
                      color: ConditionChipColors.onSelected,
                      fontWeight: FontWeight.bold,
                      fontSize: ConditionChipTokens.fontSize,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                // The whole card, uncropped (a portrait card box + contain),
                // rather than the default square centre-crop.
                CardThumbnail(
                  localImagePath: card.localImagePath,
                  size: CardThumbnailSizes.collectionTile,
                  aspectRatio: ScanReticleTokens.cardAspectRatio,
                  fit: BoxFit.contain,
                ),
                const SizedBox(width: AppSpacing.md),
                // Name (up to 2 lines), then the set and the rarity on one line
                // each — sitting to the right of the artwork and centred in the
                // space left between it and the quantity. Even with a wrapped
                // name this block stays inside the action column's height, so
                // the third line costs the row nothing.
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        card.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: palette.onSurface),
                      ),
                      for (final line in [_setLine, _rarityLine])
                        if (line != null) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            line,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: palette.onSurfaceMuted),
                          ),
                        ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                // The count sits on the row's midline, level with the middle
                // (remove) button it belongs to. Fixed width so the action
                // column doesn't shift as the number gains a digit.
                SizedBox(
                  width: CollectionTileTokens.quantityWidth,
                  child: Text(
                    '${entry.quantity}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: palette.onSurface),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                // Add / remove / delete stacked in one column, in that order.
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _TileAction(
                      icon: Icons.add_circle_outline,
                      color: palette.accent,
                      onPressed: onIncrement,
                    ),
                    _TileAction(
                      icon: Icons.remove_circle_outline,
                      color: palette.onSurfaceMuted,
                      onPressed: onDecrement,
                    ),
                    _TileAction(
                      icon: Icons.delete_outline,
                      color: palette.onSurfaceMuted,
                      onPressed: onDelete,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One button in the tile's stacked action column. A plain [IconButton] carries
/// a 48pt minimum on every side, which makes three of them taller than the row
/// they sit in — this trims the box to [CollectionTileTokens.actionButtonSize]
/// while keeping the icon, colour and ripple.
class _TileAction extends StatelessWidget {
  const _TileAction({
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon),
      color: color,
      onPressed: onPressed,
      iconSize: CollectionTileTokens.actionIconSize,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(
        width: CollectionTileTokens.actionButtonSize,
        height: CollectionTileTokens.actionButtonSize,
      ),
    );
  }
}
