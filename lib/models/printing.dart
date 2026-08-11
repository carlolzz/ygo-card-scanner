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

  /// "SET-CODE · Set Name · Rarity", omitting whatever this row doesn't carry.
  /// The single place a printing is formatted for display, shared by the scan
  /// review gate's set picker and the collection edit sheet. Empty when the row
  /// carries none of the three (callers substitute their own "no set" label).
  ///
  /// Includes the rarity because [filterPrintings] searches this string — a
  /// user narrowing the picker types "raiders super". Where rarity is shown as
  /// a field of its own, use [setLabel] instead.
  String get displayLabel =>
      [setCode, setName, rarity].whereType<String>().join(' · ');

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
/// wizard — and they used to carry their own copies of the "only one printing"
/// half. It lives here, pure and tested, because every way of getting it wrong
/// is silent: a wrong preselection logs a real card against the wrong set, and
/// the user has no reason to re-check a field that was already filled in.
///
/// The rules, in order:
///
/// 1. **No printings** — nothing to pick. Callers already special-case this
///    (the wizard skips its printing step, the scan gate's picker hides itself).
/// 2. **Exactly one printing** — that one, whatever [defaultRarity] says. The
///    card came from somewhere, and making the user tap a decision with one
///    option only risks them leaving it untapped and logging no set at all.
/// 3. **Several printings and exactly one of them matches [defaultRarity]** —
///    that one. A card printed only in Ultra and Secret Rare gets nothing when
///    the preference is Common; the preference selects among what a card
///    actually has, it never invents a printing.
/// 4. **Anything else** — null. Two printings of the same rarity in different
///    sets is genuinely the user's call, and the camera cannot tell which
///    reprint is in hand; picking one arbitrarily would silently log the wrong
///    set half the time.
///
/// Matching is case- and whitespace-insensitive because [defaultRarity] is
/// persisted free-form text, not an enum.
Printing? preferredPrinting(
  List<Printing> printings, {
  String? defaultRarity,
}) {
  if (printings.isEmpty) return null;
  if (printings.length == 1) return printings.single;

  final wanted = defaultRarity?.trim().toLowerCase();
  if (wanted == null || wanted.isEmpty) return null;

  final matching = [
    for (final printing in printings)
      if (printing.rarity?.trim().toLowerCase() == wanted) printing,
  ];
  return matching.length == 1 ? matching.single : null;
}
