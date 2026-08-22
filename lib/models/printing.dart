import 'package:freezed_annotation/freezed_annotation.dart';

import '../core/search_terms.dart';

part 'printing.freezed.dart';

/// Maps to the `printings` table. `id` is null until the row has been
/// inserted (AUTOINCREMENT primary key).
@freezed
abstract class Printing with _$Printing {
  const Printing._();

  const factory Printing({
    int? id,
    required String passcode,
    String? setCode,
    String? setName,
    String? rarity,
  }) = _Printing;

  factory Printing.fromMap(Map<String, Object?> map) => Printing(
    id: map['id'] as int?,
    passcode: map['passcode'] as String,
    setCode: map['set_code'] as String?,
    setName: map['set_name'] as String?,
    rarity: map['rarity'] as String?,
  );

  /// "SET-CODE (Rarity) Set Name", omitting whatever this row doesn't carry.
  /// The single place a printing is formatted for display, shared by the scan
  /// review gate's set picker and the collection edit sheet. Empty when the row
  /// carries none of the three (callers substitute their own "no set" label).
  ///
  /// **Rarity sits second, not last, and that is the whole reason for this
  /// ordering.** Set names run long ("Legendary Collection 4: Joey's World Mega
  /// Pack"), so a rarity trailing them was the first thing an ellipsis ate — and
  /// a list of reprints where every row shows a truncated set name and no rarity
  /// is a list you cannot pick from, which is exactly what the picker is for.
  /// Set code and rarity together are the `printings` UNIQUE key, so the two
  /// fields that actually identify the row now lead it; the set name is the
  /// human-readable gloss and is the right thing to lose to the edge.
  ///
  /// Parenthesised rather than a third `·`-separated field because it is now
  /// interrupting the code→name pair rather than following it.
  ///
  /// Includes the rarity at all because [filterPrintings] searches this string —
  /// a user narrowing the picker types "raiders super", and the shared
  /// [matchesSearchTerms] rule is order-independent, so this reordering does not
  /// change what any query matches. Where rarity is shown as a field of its own,
  /// use [setLabel] instead.
  String get displayLabel =>
      [?setCode, if (rarity != null) '($rarity)', ?setName].join(' ');

  /// "SET-CODE · Set Name" — [displayLabel] without the rarity, for screens
  /// that give rarity a row of its own rather than trailing it onto the set.
  String get setLabel => [setCode, setName].whereType<String>().join(' · ');

  Map<String, Object?> toMap() => {
    'passcode': passcode,
    'set_code': setCode,
    'set_name': setName,
    'rarity': rarity,
  };
}

/// Narrows [printings] to those matching a free-typed [query], for the set
/// search box shared by the scan review gate, the manual add wizard and the
/// collection edit sheet.
///
/// Matched against [Printing.displayLabel] under the shared
/// [matchesSearchTerms] rule, so this box and the collection filter sheet's set
/// box narrow identically.
List<Printing> filterPrintings(List<Printing> printings, String query) => [
  for (final printing in printings)
    if (matchesSearchTerms(printing.displayLabel, query)) printing,
];

/// The printing to preselect when a card is resolved, or null to leave the
/// choice to the user.
///
/// Both logging flows ask this — the scan review gate and the manual add
/// wizard — and they used to carry their own copies of it. It lives here, pure
/// and tested, because every way of getting it wrong is silent: a wrong
/// preselection logs a real card against the wrong set, and the user has no
/// reason to re-check a field that was already filled in.
///
/// The rules:
///
/// 1. **No printings** — nothing to pick. Callers already special-case this
///    (the wizard skips its printing step, the scan gate's picker hides itself).
/// 2. **Exactly one printing** — that one. The card came from somewhere, and
///    making the user tap a decision with one option only risks them leaving it
///    untapped and logging no set at all.
/// 3. **Several printings** — null. Which reprint is in hand is genuinely the
///    user's call and the camera cannot tell; picking one arbitrarily would
///    silently log the wrong set.
///
/// A `defaultRarity` preference used to sit between rules 2 and 3, narrowing
/// several printings down to the one matching a persisted rarity. It was
/// removed in step 24: its option list came from `PrintingDao.distinctRarities`
/// over the whole synced database, which is ~90 open-ended YGOPRODeck
/// `set_rarity` strings (`10000 Secret Rare`, `Duel Terminal Normal Parallel
/// Rare`, the bare values `2` and `3`), so the control was unusable. Nothing
/// about this function needed it.
Printing? preferredPrinting(List<Printing> printings) =>
    printings.length == 1 ? printings.single : null;
