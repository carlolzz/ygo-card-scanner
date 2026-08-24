import 'ygo_card.dart';

/// One card-search result: the card, plus the name that actually matched when
/// the search ran in a language other than English.
///
/// Both search paths (`CardDao.searchByName` and `searchByLocalizedName`) return
/// this one type, so the add-card wizard and the browse screen have a single
/// shape to render.
///
/// [localizedName] is null for an English search: there the matched name *is*
/// [YgoCard.name], and echoing it under itself would be noise. A non-null value
/// is what the user typed against, so it belongs on screen — the card is still
/// shown, named and pictured in English everywhere else.
///
/// A plain class in `models/` rather than a record or a DAO-local type: it
/// crosses from the DAO through a repository and two providers into two widget
/// trees, and a widget should not have to import a DAO to name what it is
/// rendering.
class CardSearchHit {
  const CardSearchHit(this.card, [this.localizedName]);

  final YgoCard card;
  final String? localizedName;
}
