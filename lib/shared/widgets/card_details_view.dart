import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/theme/tokens.dart';
import '../../models/ygo_card.dart';
import 'card_art_thumbnail.dart';

/// A card's own facts — artwork, type, stats, effect text — with nothing about
/// owning it.
///
/// Shared by the two screens that show a card: the collection detail screen,
/// which wraps this with everything entry-specific (grade, quantity, set,
/// edition, language), and the card-search detail screen, which has no entry at
/// all. Extracted rather than duplicated because these rows carry real rules —
/// the Spell/Trap label switch, hiding a Spell's redundant attribute, flavour
/// text vs card effect — and a copy would drift from them silently.
class CardDetailsView extends StatelessWidget {
  const CardDetailsView({super.key, required this.card, this.leading});

  final YgoCard card;

  /// Rendered between the artwork and the fact rows. The collection screen puts
  /// its condition pill and price estimate here, so those stay directly under
  /// the picture without this widget knowing anything about them.
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          // The whole card, uncropped (portrait card box + contain) rather
          // than a square centre-crop.
          child: CardArtThumbnail(
            card: card,
            size: CardThumbnailSizes.detail,
            aspectRatio: ScanReticleTokens.cardAspectRatio,
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        ?leading,
        if (card.type != null)
          CardDetailRow(
            label: AppStrings.collectionCardTypeLabel,
            value: card.type!,
          ),
        // A Spell/Trap's `attribute` is just "SPELL"/"TRAP" (redundant with
        // the type row above), so it's only shown for monsters.
        if (card.attribute != null && !card.isSpellOrTrap)
          CardDetailRow(
            label: AppStrings.collectionCardAttributeLabel,
            value: card.attribute!,
          ),
        if (card.race != null)
          CardDetailRow(
            // For Spell/Trap, `race` is the card's own kind, not a monster
            // type — and naming the frame ("Spell Type"/"Trap Type") is
            // what players call it, so it beats a generic "Property".
            label: switch (card) {
              _ when card.isSpell => AppStrings.collectionCardSpellTypeLabel,
              _ when card.isTrap => AppStrings.collectionCardTrapTypeLabel,
              _ => AppStrings.collectionCardRaceLabel,
            },
            value: card.race!,
          ),
        if (card.level != null)
          CardDetailRow(
            label: AppStrings.collectionCardLevelLabel,
            value: '${card.level}',
          ),
        if (card.atk != null || card.def != null)
          CardDetailRow(
            label: AppStrings.collectionCardAtkDefLabel,
            value: '${card.atk ?? '-'} / ${card.def ?? '-'}',
          ),
        if (card.archetype != null)
          CardDetailRow(
            label: AppStrings.collectionCardArchetypeLabel,
            value: card.archetype!,
          ),
        if (card.description != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            card.isNormalMonster
                ? AppStrings.collectionFlavorTextLabel
                : AppStrings.collectionCardEffectLabel,
            style: TextStyle(
              color: palette.onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            card.description!,
            style: TextStyle(color: palette.onSurfaceMuted),
          ),
        ],
      ],
    );
  }
}

/// One `label · value` line on a card screen. Public because both detail
/// screens and the pricing view build rows in this shape, and three private
/// copies would drift on the label column's width alone.
class CardDetailRow extends StatelessWidget {
  const CardDetailRow({
    super.key,
    required this.label,
    required this.value,
    this.valueLeading,
  });

  final String label;
  final String value;

  /// Rendered immediately before [value]. A widget rather than something folded
  /// into the value string: the language rows put a flag here, and prefixing the
  /// glyph onto the text would change what every exact-text matcher over this
  /// screen sees while adding nothing.
  final Widget? valueLeading;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          SizedBox(
            width: CardDetailTokens.labelWidth,
            child: Text(label, style: TextStyle(color: palette.onSurfaceMuted)),
          ),
          if (valueLeading != null) ...[
            valueLeading!,
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: Text(value, style: TextStyle(color: palette.onSurface)),
          ),
        ],
      ),
    );
  }
}
