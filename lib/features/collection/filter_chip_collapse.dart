import '../../core/theme/tokens.dart';

/// Which of a filter row's values to render when the row is collapsed.
///
/// The filter sheet offers one chip per distinct value held in the collection,
/// and some of those lists are unbounded in practice: archetype, card type and
/// the monster/spell/trap type run to dozens of entries on a real collection, so
/// the sheet becomes a wall of chips read one at a time. Past
/// [CollectionFilterTokens.chipCollapseThreshold] a row shows only its first
/// [threshold] values until the user asks for the rest.
///
/// **The selected value is always visible**, even when it falls outside that
/// slice, and that is the load-bearing part rather than a nicety: a collapsed
/// row that hides the active filter reads as an unset filter, and the filter
/// bar's active-count badge would then contradict what is on screen.
///
/// Takes an [isSelected] predicate rather than comparing against a `T?`, because
/// the rarity row cannot express its selection as a value: its list is
/// `List<String?>` where `null` is the meaningful "no rarity" option, while its
/// selection is a `RarityFilter?`. One rule for every row is worth the
/// indirection — two copies of a collapse rule drift, and the row that drifts is
/// the one that silently hides a filter.
List<T> visibleFilterChoices<T>(
  List<T> values, {
  required bool Function(T) isSelected,
  required bool expanded,
  int threshold = CollectionFilterTokens.chipCollapseThreshold,
}) {
  if (expanded || values.length <= threshold) return values;
  final head = values.take(threshold).toList();
  if (head.any(isSelected)) return head;
  // Appended rather than substituted for the last visible value: the head is in
  // the same order the DAO returned (alphabetical), and dropping one of those to
  // make room would make the collapsed list disagree with the expanded one about
  // what comes first.
  final selected = values.where(isSelected);
  return selected.isEmpty ? head : [...head, selected.first];
}
