import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/repositories/price_repository.dart';
import '../../models/card_prices.dart';

part 'price_providers.g.dart';

/// Disables Riverpod 3's automatic retry, and it is **not** a tidy-up.
///
/// By default a provider that throws is re-run on a doubling backoff, and while
/// that is pending it stays `AsyncLoading` *carrying* the error — so
/// `.when(error:)` never fires and the UI shows a spinner forever. A pricing
/// screen has one honest answer for an offline device ("could not load prices",
/// with a Retry the user drives), and an invisible retry loop replaces it with
/// a screen that looks like it is still working.
///
/// Both providers here own their retry: [CardPricesView] has an explicit Retry
/// button, and [cardPrice] degrades to the cached row instead of failing.
Duration? _noRetry(int retryCount, Object error) => null;

/// Everything one card's Prices tab shows, fetched live.
///
/// `keepAlive` so switching between the Details and Prices tabs, or backing out
/// of a card and returning to it, does not re-request — a tab switch costing a
/// network round trip reads as the app being slow, and the figures do not move
/// within a session. It is still *fetched* live on first read, unlike
/// [cardPrice] below, because the per-set table is the point of this screen and
/// those figures are not stored anywhere.
///
/// Null means YGOPRODeck does not recognise the passcode. That is a normal
/// outcome, not an error: alt-art ids and cards the sync has since moved past
/// both land here.
@Riverpod(keepAlive: true, retry: _noRetry)
Future<CardPricing?> cardPricing(Ref ref, String passcode) async {
  final repository = await ref.watch(priceRepositoryProvider.future);
  return repository.pricingFor(passcode);
}

/// One card's cached prices, for the estimate line on a Details tab.
///
/// Goes through `cachedOrFetch`, so opening a card the user has looked at
/// today costs nothing and an offline moment still shows the last known figure
/// with its own "as of" stamp. Deliberately a different provider from
/// [cardPricing]: an estimate must not pull the per-set table, and it must not
/// fail loudly — a card's effect text should still be readable when pricing is
/// unavailable.
@Riverpod(retry: _noRetry)
Future<CardPrices?> cardPrice(Ref ref, String passcode) async {
  final repository = await ref.watch(priceRepositoryProvider.future);
  return repository.cachedOrFetch(passcode);
}
