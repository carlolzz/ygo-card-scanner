import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/money.dart';
import '../../core/theme/tokens.dart';
import '../../data/repositories/price_repository.dart';
import '../pricing/card_prices_view.dart' show formatFetchedAt;
import 'stat_tile.dart';

/// How the breakdown is ordered.
enum ValueSortMode { byValue, byName }

/// The rows behind the two collection-value totals: what each printing owned is
/// worth, and what the copies of it are worth together.
///
/// **Reads nothing from Riverpod.** Everything comes from [value], passed
/// through `go_router`'s `extra` by the Statistics screen that just calculated
/// it — the same idiom as the collection and card detail screens. That is
/// deliberate rather than incidental: it makes this screen a pure function of
/// its argument, so it can be pumped directly under a bare `MaterialApp` in a
/// test, sidestepping the documented hang when a route transition kicks off the
/// sqflite isolate.
///
/// **No artwork, and rows are not tappable.** Both would need a `YgoCard`,
/// which a [CollectionValueLine] does not carry — reaching one means the
/// database, which would cost this screen its pure-`extra` property, fire a
/// burst of art lookups over a list that is one row per *printing*, and roughly
/// double the height of every row on a screen whose job is a dense money list.
/// This is a decision, not an omission.
class CollectionValueScreen extends StatefulWidget {
  const CollectionValueScreen({required this.value, super.key});

  final CollectionValue value;

  @override
  State<CollectionValueScreen> createState() => _CollectionValueScreenState();
}

class _CollectionValueScreenState extends State<CollectionValueScreen> {
  /// Local widget state, like the collection search box: ephemeral input, not
  /// part of the valuation. The export keeps the repository's name order
  /// whatever is chosen here, so a file stays diff-stable against an earlier
  /// one.
  ValueSortMode _sort = ValueSortMode.byValue;

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    final lines = sortValueLines(value.lines, _sort);

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.valueBreakdownTitle),
        actions: [
          PopupMenuButton<ValueSortMode>(
            icon: const Icon(Icons.sort),
            initialValue: _sort,
            onSelected: (mode) => setState(() => _sort = mode),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: ValueSortMode.byValue,
                child: Text(AppStrings.valueBreakdownSortByValue),
              ),
              PopupMenuItem(
                value: ValueSortMode.byName,
                child: Text(AppStrings.valueBreakdownSortByName),
              ),
            ],
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(AppSpacing.lg),
        // The header rides in the list rather than above it so the totals
        // scroll away and the rows get the whole screen.
        itemCount: lines.length + 1,
        itemBuilder: (context, index) => index == 0
            ? _Header(value: value)
            : _ValueLine(line: lines[index - 1]),
      ),
    );
  }
}

/// [lines] in the order [mode] asks for.
///
/// Pure and top-level so the ordering is testable without a widget, and
/// non-mutating so the caller's list — which is the one the export writes — is
/// never reordered underneath it.
///
/// [ValueSortMode.byValue] ranks on the **line total**, not the unit price: the
/// question this screen answers is "where is my collection's value", and four
/// copies of a $10 card outrank one copy of a $30 one. Unpriced lines sort last
/// rather than as zero, so they read as unknown rather than as worthless, and
/// ties fall back to name so the order is total.
List<CollectionValueLine> sortValueLines(
  List<CollectionValueLine> lines,
  ValueSortMode mode,
) {
  final sorted = [...lines];
  if (mode == ValueSortMode.byName) return sorted;
  sorted.sort((a, b) {
    final aTotal = a.tcgplayerUsd == null ? null : a.tcgplayerUsd! * a.quantity;
    final bTotal = b.tcgplayerUsd == null ? null : b.tcgplayerUsd! * b.quantity;
    if (aTotal == null && bTotal == null) return a.name.compareTo(b.name);
    if (aTotal == null) return 1;
    if (bTotal == null) return -1;
    final byTotal = bTotal.compareTo(aTotal);
    return byTotal != 0 ? byTotal : a.name.compareTo(b.name);
  });
  return sorted;
}

class _Header extends StatelessWidget {
  const _Header({required this.value});

  final CollectionValue value;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final footnote = TextStyle(
      color: palette.onSurfaceMuted,
      fontSize: PriceTokens.footnoteFontSize,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The same two tiles as the Statistics screen, in the same shape, so
        // this reads as the detail behind those figures rather than as a
        // second, differently-computed answer.
        Row(
          children: [
            Expanded(
              child: StatTile(
                label: AppStrings.statisticsValueCardmarketLabel,
                value: formatEur(value.cardmarketEur),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: StatTile(
                label: AppStrings.statisticsValueTcgplayerLabel,
                value: formatUsd(value.tcgplayerUsd),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          AppStrings.statisticsValuePrintingPriced(
            value.printingPricedLines,
            value.lines.length,
          ),
          style: footnote,
        ),
        if (value.unpricedCards > 0)
          Text(AppStrings.statisticsValueUnpriced(value.unpricedCards),
              style: footnote),
        Text(AppStrings.statisticsValueNote, style: footnote),
        if (value.asOf != null)
          Text(
            AppStrings.pricesFetchedAt(formatFetchedAt(value.asOf!)),
            style: footnote,
          ),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }
}

/// One printing: what it is, how many are owned, and what they are worth.
class _ValueLine extends StatelessWidget {
  const _ValueLine({required this.line});

  final CollectionValueLine line;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final eurTotal = line.cardmarketEur == null
        ? null
        : line.cardmarketEur! * line.quantity;
    final usdTotal = line.tcgplayerUsd == null
        ? null
        : line.tcgplayerUsd! * line.quantity;
    final setLabel = line.setLabel;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.name, style: TextStyle(color: palette.onSurface)),
                Text(
                  // A line with no printing still says so: "no set recorded" is
                  // why it fell back to the card floor.
                  setLabel.isEmpty ? AppStrings.valueBreakdownNoSet : setLabel,
                  style: TextStyle(
                    color: palette.onSurfaceMuted,
                    fontSize: PriceTokens.footnoteFontSize,
                  ),
                ),
                if (line.rarity != null)
                  Text(
                    line.rarity!,
                    style: TextStyle(
                      color: palette.onSurfaceMuted,
                      fontSize: PriceTokens.footnoteFontSize,
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            width: ValueBreakdownTokens.quantityWidth,
            child: Text(
              '×${line.quantity}',
              textAlign: TextAlign.right,
              style: TextStyle(color: palette.onSurfaceMuted),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: ValueBreakdownTokens.moneyWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatUsd(usdTotal),
                  style: TextStyle(
                    color: palette.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                // Only where the dollars came from the card-level floor, so the
                // absence of a tag means the figure is the printing's own.
                if (line.usdBasis == PriceBasis.cardFloor)
                  Text(
                    AppStrings.valueBreakdownCardFloorTag,
                    style: TextStyle(
                      color: palette.onSurfaceMuted,
                      fontSize: PriceTokens.footnoteFontSize,
                    ),
                  ),
                Text(
                  formatEur(eurTotal),
                  style: TextStyle(
                    color: palette.onSurfaceMuted,
                    fontSize: PriceTokens.footnoteFontSize,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
