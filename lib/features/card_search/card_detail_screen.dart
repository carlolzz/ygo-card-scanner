import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/theme/tokens.dart';
import '../../models/ygo_card.dart';
import '../../shared/widgets/card_details_view.dart';
import '../pricing/card_prices_view.dart';

/// A card the user does not necessarily own: its facts, and its prices.
///
/// Two tabs rather than one long scroll, and the same two the collection detail
/// screen carries, so a card reads the same wherever it is reached from. The
/// split is not cosmetic: the Details tab is answered entirely from the local
/// database, while Prices needs the network — folding them together would make
/// reading a card's effect text depend on being online.
class CardDetailScreen extends StatelessWidget {
  const CardDetailScreen({super.key, required this.card});

  final YgoCard card;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(card.name),
          bottom: const TabBar(
            tabs: [
              Tab(text: AppStrings.cardTabDetails),
              Tab(text: AppStrings.cardTabPrices),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Builder(
                // Its own context so `DefaultTabController.of` finds the
                // controller above, which is what lets the estimate row send
                // the user to the tab holding the rest of the answer.
                builder: (context) => CardDetailsView(
                  card: card,
                  leading: CardPriceEstimate(
                    passcode: card.passcode,
                    onTap: () => DefaultTabController.of(context).animateTo(1),
                  ),
                ),
              ),
            ),
            CardPricesView(passcode: card.passcode),
          ],
        ),
      ),
    );
  }
}
