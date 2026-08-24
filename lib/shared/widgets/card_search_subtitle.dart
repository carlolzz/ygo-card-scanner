import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../models/card_search_hit.dart';

/// The second line of a card-search row.
///
/// One widget for both search screens because the rule is the interesting part,
/// not the styling: when the search ran in another language, the row must show
/// the name that *matched*, or a search for "Drago Bianco" returns a list of
/// English names with the typed words nowhere in it. The card's type takes that
/// line the rest of the time, as it always has.
///
/// Returns a `SizedBox.shrink` rather than null when there is nothing to say,
/// so callers can pass it straight to `ListTile.subtitle` without repeating the
/// null check. The type is dropped in favour of the localized name rather than
/// shown beneath it: it is on the card's own page, and a third line on a
/// results row buys little.
class CardSearchSubtitle extends StatelessWidget {
  const CardSearchSubtitle(this.hit, {super.key});

  final CardSearchHit hit;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = hit.localizedName ?? hit.card.type;
    if (text == null || text.isEmpty) return const SizedBox.shrink();
    return Text(
      text,
      style: TextStyle(
        color: palette.onSurfaceMuted,
        // Italic only for the localized name, so it reads as the same card
        // under another name rather than as a second card.
        fontStyle: hit.localizedName == null
            ? FontStyle.normal
            : FontStyle.italic,
      ),
    );
  }
}
