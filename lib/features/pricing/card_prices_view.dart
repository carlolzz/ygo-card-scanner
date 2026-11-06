import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/money.dart';
import '../../core/theme/tokens.dart';
import '../../models/card_prices.dart';
import 'price_providers.dart';

/// One card's prices: the card-level figures from every vendor YGOPRODeck
/// tracks, then a per-set table.
///
/// **The two halves are not the same measurement, and the notes say so.** The
/// vendor block is one figure per marketplace for the *card*, documented by the
/// API as the lowest across every version of it. The per-set table is a
/// different quantity — what that specific printing sells for — and it exists
/// in US dollars only, because YGOPRODeck reports Cardmarket at the card level
/// and nowhere else. Presenting them as one table would imply a per-set
/// Cardmarket price that does not exist.
class CardPricesView extends ConsumerWidget {
  const CardPricesView({super.key, required this.passcode});

  final String passcode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pricingAsync = ref.watch(cardPricingProvider(passcode));

    return pricingAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => _Failure(
        onRetry: () => ref.invalidate(cardPricingProvider(passcode)),
      ),
      data: (pricing) {
        if (pricing == null) return const _Unknown();
        return _Loaded(
          pricing: pricing,
          onRefresh: () => ref.invalidate(cardPricingProvider(passcode)),
        );
      },
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({required this.pricing, required this.onRefresh});

  final CardPricing pricing;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final card = pricing.card;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Row(
          children: [
            Expanded(child: _SectionTitle(AppStrings.pricesMarketSection)),
            IconButton(
              tooltip: AppStrings.pricesRefreshTooltip,
              icon: const Icon(Icons.refresh),
              onPressed: onRefresh,
            ),
          ],
        ),
        _PriceRow(AppStrings.pricesCardmarket, formatEur(card.cardmarket)),
        _PriceRow(AppStrings.pricesTcgplayer, formatUsd(card.tcgplayer)),
        const SizedBox(height: AppSpacing.sm),
        _Note(AppStrings.pricesCardLevelNote),
        const SizedBox(height: AppSpacing.lg),
        _SectionTitle(AppStrings.pricesBySetSection),
        const SizedBox(height: AppSpacing.xs),
        if (pricing.sets.isEmpty)
          Text(
            AppStrings.pricesNoSets,
            style: TextStyle(color: palette.onSurfaceMuted),
          )
        else
          for (final set in pricing.sets) _SetPriceRow(set: set),
        const SizedBox(height: AppSpacing.sm),
        _Note(AppStrings.pricesBySetNote),
        const SizedBox(height: AppSpacing.md),
        _Note(AppStrings.pricesFetchedAt(formatFetchedAt(card.updatedAt))),
      ],
    );
  }
}

/// The "as of" stamp, to the minute.
///
/// Hand-formatted rather than through `intl`, which is not in the approved
/// stack — and to the minute rather than the second because the figure it
/// describes is a daily-ish market price, so a second-precise stamp would
/// imply an accuracy the number does not have.
String formatFetchedAt(DateTime when) {
  final local = when.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

class _SetPriceRow extends StatelessWidget {
  const _SetPriceRow({required this.set});

  final SetPrice set;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  set.setLabel,
                  style: TextStyle(color: palette.onSurface),
                ),
                if (set.rarity != null)
                  Text(
                    set.rarity!,
                    style: TextStyle(
                      color: palette.onSurfaceMuted,
                      fontSize: PriceTokens.footnoteFontSize,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          // Fixed width so the figures form a column instead of ragging against
          // set names of wildly different lengths.
          SizedBox(
            width: PriceTokens.setPriceWidth,
            child: Text(
              formatUsd(set.price),
              textAlign: TextAlign.right,
              style: TextStyle(
                color: palette.onSurface,
                fontSize: PriceTokens.valueFontSize,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceRow extends StatelessWidget {
  const _PriceRow(this.label, this.value);

  final String label;
  final String value;

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
          Text(
            value,
            style: TextStyle(
              color: palette.onSurface,
              fontSize: PriceTokens.valueFontSize,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Text(
    title,
    style: TextStyle(
      color: AppPalette.of(context).onSurface,
      fontWeight: FontWeight.bold,
      fontSize: CardDetailTokens.sectionFontSize,
    ),
  );
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      color: AppPalette.of(context).onSurfaceMuted,
      fontSize: PriceTokens.footnoteFontSize,
    ),
  );
}

/// A card the API has no pricing for. Not an error — it is a fact about the
/// card, so it reads as one rather than offering a Retry that cannot help.
class _Unknown extends StatelessWidget {
  const _Unknown();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Text(
        AppStrings.pricesUnknownCard,
        textAlign: TextAlign.center,
        style: TextStyle(color: AppPalette.of(context).onSurfaceMuted),
      ),
    ),
  );
}

/// Offline or a transient failure. Follows `InitialSyncScreen._FailureView`:
/// one icon, one plain sentence, one Retry — and never the exception, which
/// tells the user nothing they can act on.
class _Failure extends StatelessWidget {
  const _Failure({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, color: palette.onSurfaceMuted, size: 40),
            const SizedBox(height: AppSpacing.md),
            Text(
              AppStrings.pricesErrorMessage,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.onSurfaceMuted),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: onRetry,
              child: Text(AppStrings.pricesRetryButton),
            ),
          ],
        ),
      ),
    );
  }
}

/// The tappable estimate on a Details tab: one copy's Cardmarket and TCGplayer
/// figures, and a way through to the full breakdown.
///
/// Degrades to nothing while it resolves and when the card has no price at all,
/// rather than showing a spinner or a row of dashes — a card's effect text is
/// what the user opened this screen for, and an estimate is a bonus that must
/// never push it down or make the screen look broken.
class CardPriceEstimate extends ConsumerWidget {
  const CardPriceEstimate({
    super.key,
    required this.passcode,
    required this.onTap,
    this.quantity = 1,
  });

  final String passcode;
  final VoidCallback onTap;

  /// Copies owned, so the collection screen can show what the stack is worth.
  /// One on the card-search screen, where nothing is owned.
  final int quantity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prices = ref.watch(cardPriceProvider(passcode)).value;
    if (prices == null) return const SizedBox.shrink();
    if (prices.cardmarket == null && prices.tcgplayer == null) {
      return const SizedBox.shrink();
    }

    final palette = AppPalette.of(context);
    final eur = prices.cardmarket == null
        ? null
        : prices.cardmarket! * quantity;
    final usd = prices.tcgplayer == null ? null : prices.tcgplayer! * quantity;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Row(
            children: [
              SizedBox(
                width: CardDetailTokens.labelWidth,
                child: Text(
                  AppStrings.pricesEstimateLabel,
                  style: TextStyle(color: palette.onSurfaceMuted),
                ),
              ),
              Expanded(
                child: Text(
                  '${formatEur(eur)} · ${formatUsd(usd)}',
                  style: TextStyle(
                    color: palette.onSurface,
                    fontSize: PriceTokens.valueFontSize,
                  ),
                ),
              ),
              Text(
                AppStrings.pricesSeeAll,
                style: TextStyle(
                  color: palette.accent,
                  fontSize: PriceTokens.footnoteFontSize,
                ),
              ),
              Icon(Icons.chevron_right, color: palette.accent, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
