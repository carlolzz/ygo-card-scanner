import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../models/collection_entry_with_card.dart';
import '../../shared/widgets/card_art_thumbnail.dart';
import '../../shared/widgets/language_flag.dart';

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
    required this.onLongPress,
    this.selectionActive = false,
    this.selected = false,
  });

  final CollectionEntryWithCard entryWithCard;

  /// Whether to caption the artwork with the card's name.
  final bool showName;

  final VoidCallback onTap;

  /// Enters selection mode with this cell picked.
  final VoidCallback onLongPress;

  final bool selectionActive;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final entry = entryWithCard.entry;
    final card = entryWithCard.card;

    return Material(
      color: palette.surfaceRaised,
      // `shape` rather than `borderRadius` — [Material] asserts if given both,
      // and the shape has to carry the radius so the selected outline follows
      // the corners. An outline as well as the corner check mark: in
      // `minifyFull` the cell is nothing but artwork, so a small badge is thin
      // evidence that a card scrolled two rows up is still part of what Remove
      // will take.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        side: selected
            ? BorderSide(
                color: palette.accent,
                width: CollectionGridTokens.selectedBorderWidth,
              )
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CardArtThumbnail(
                    card: card,
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
                  // Top-left, the opposite corner from the quantity badge, so
                  // the two can never overlap however small the cell gets.
                  if (selectionActive)
                    Positioned(
                      left: 2,
                      top: 2,
                      child: _SelectionCheck(selected: selected),
                    ),
                  // Bottom-left: the one corner the other two overlays don't
                  // claim. Inside the artwork [Stack] rather than beside the
                  // caption, so it renders in `minifyFull` too and the cell
                  // height — computed from `nameCaptionHeight` by the grid
                  // delegate in `collection_screen.dart` — is untouched.
                  Positioned(
                    left: 2,
                    bottom: 2,
                    child: _LanguageBadge(language: entry.language),
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

/// The selection check over a cell's artwork. Scrimmed like [_QuantityBadge],
/// and for the same reason: it sits on card art, which is any colour at all, so
/// a bare icon would vanish against half the collection.
class _SelectionCheck extends StatelessWidget {
  const _SelectionCheck({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppPalette.dark.background.withValues(alpha: 0.85),
        shape: BoxShape.circle,
      ),
      child: Icon(
        selected ? Icons.check_circle : Icons.circle_outlined,
        size: CollectionGridTokens.selectionCheckSize,
        color: selected
            ? AppPalette.dark.accent
            : AppPalette.dark.onSurfaceMuted,
      ),
    );
  }
}

/// The language flag over a cell's artwork, scrimmed like [_QuantityBadge] and
/// for the same reason. The scrim is what makes the fixed light ink correct
/// here in either theme: the badge sits on a dark panel of its own, not on the
/// surface underneath.
class _LanguageBadge extends StatelessWidget {
  const _LanguageBadge({required this.language});

  final String language;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ConditionChipTokens.verticalPadding,
        vertical: ConditionChipTokens.verticalPadding,
      ),
      decoration: BoxDecoration(
        color: AppPalette.dark.background.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(ConditionChipTokens.radius),
      ),
      child: LanguageFlag(
        language: language,
        color: AppPalette.dark.onSurface,
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
