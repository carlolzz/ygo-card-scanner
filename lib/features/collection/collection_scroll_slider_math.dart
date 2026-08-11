/// The geometry and labelling behind the collection's fast-browse slider.
///
/// Pure and host-tested, for the reason `card_quad.dart` gives: the widget
/// itself needs a laid-out scrollable and a real gesture to exercise, while
/// every interesting decision here is arithmetic. A wrong constant does not
/// crash — it puts the thumb somewhere plausible and slightly wrong, which is
/// exactly the kind of defect a widget test is bad at catching.
library;

import 'dart:math' as math;

import '../../core/constants.dart';
import '../../core/theme/tokens.dart';
import '../../data/db/dao/collection_dao.dart';
import '../../models/collection_entry_with_card.dart';

/// The three numbers the slider needs from the scroll position.
///
/// A record for its free structural equality: metrics arrive on every scroll
/// notification, and an unchanged value must not rebuild the thumb.
typedef ScrollSliderMetrics = ({
  double pixels,
  double maxScrollExtent,
  double viewportDimension,
});

/// Whether the gutter reserves width at all, for [itemCount] entries.
///
/// **Deliberately a function of the item count and nothing measured.** The
/// gutter narrows the grid's cross axis, which changes how many columns fit,
/// which changes the scroll extent — so a predicate reading any post-layout
/// number would feed back into its own input and could oscillate between two
/// layouts forever. `itemCount` is an input to layout, so it cannot.
bool collectionSliderReservesGutter(int itemCount) =>
    itemCount >= CollectionScrollSliderTokens.minItems;

/// Whether the rail and thumb are actually painted, given real metrics.
///
/// The second gate, and safe to make layout-dependent because it only decides
/// what is drawn *inside* an already-reserved gutter — it cannot change the
/// layout that produced it. Covers the tablet case where [minItems] entries
/// genuinely fit on one screen.
bool collectionSliderIsScrollable(ScrollSliderMetrics metrics) =>
    metrics.maxScrollExtent.isFinite &&
    metrics.maxScrollExtent > 0 &&
    metrics.viewportDimension > 0;

/// How long the thumb is, in the same proportion to the track as the viewport
/// is to the whole content — floored so it stays grabbable on a long list.
double sliderThumbExtent({
  required double trackExtent,
  required double viewportDimension,
  required double contentExtent,
}) {
  if (trackExtent <= 0) return 0;
  if (!contentExtent.isFinite || contentExtent <= 0) return 0;
  final proportional = trackExtent * (viewportDimension / contentExtent);
  return proportional
      .clamp(
        math.min(CollectionScrollSliderTokens.minThumbExtent, trackExtent),
        trackExtent,
      )
      .toDouble();
}

/// How far through the scrollable [offset] is, as 0..1.
///
/// Returns 0 for content that does not scroll, which is what makes every caller
/// safe before the first layout has reported real dimensions.
double sliderFractionForOffset({
  required double offset,
  required double maxScrollExtent,
}) {
  if (!maxScrollExtent.isFinite || maxScrollExtent <= 0) return 0;
  return (offset / maxScrollExtent).clamp(0, 1).toDouble();
}

/// Where the thumb's top edge sits for a given [fraction].
double sliderThumbTop({
  required double fraction,
  required double trackExtent,
  required double thumbExtent,
}) {
  final travel = math.max(trackExtent - thumbExtent, 0.0);
  return (fraction.clamp(0, 1) * travel).toDouble();
}

/// The scroll offset for a thumb dragged to [thumbTop] — the inverse of
/// [sliderThumbTop], so dragging and the resulting scroll agree exactly.
double sliderOffsetForThumbTop({
  required double thumbTop,
  required double trackExtent,
  required double thumbExtent,
  required double maxScrollExtent,
}) {
  if (!maxScrollExtent.isFinite || maxScrollExtent <= 0) return 0;
  final travel = math.max(trackExtent - thumbExtent, 0.0);
  // Content that barely overflows leaves the thumb filling the track; there is
  // nowhere to drag it, and the division would be by zero.
  if (travel <= 0) return 0;
  final fraction = (thumbTop / travel).clamp(0, 1);
  return fraction * maxScrollExtent;
}

/// The entry the bubble names at [fraction] through a list of [itemCount].
///
/// Linear in the fraction rather than an attempt to name the top *visible* row.
/// Naming that row needs the grid's column count, i.e. the delegate's own maths
/// re-implemented against a threaded-through viewport width — and it is wrong at
/// the bottom end anyway, reporting the first card of the last screenful when
/// the user has plainly dragged to "Z". The linear map is exact at both ends and
/// mid-list differs by `viewport / content`, which is under a percent on any
/// collection long enough for the slider to appear.
int sliderIndexForFraction(double fraction, int itemCount) {
  if (itemCount <= 0) return 0;
  final scaled = (fraction.clamp(0, 1) * (itemCount - 1)).round();
  return scaled.clamp(0, itemCount - 1);
}

/// Keeps the bubble beside the thumb without letting it slide off the track.
double sliderLabelTop({
  required double thumbTop,
  required double thumbExtent,
  required double labelExtent,
  required double trackExtent,
}) {
  final centred = thumbTop + thumbExtent / 2 - labelExtent / 2;
  final lowest = math.max(trackExtent - labelExtent, 0.0);
  return centred.clamp(0, lowest).toDouble();
}

/// What the bubble says at a given entry, under the collection's active sort.
///
/// Every branch reads the same field the DAO orders by (`collection_dao.dart`'s
/// `orderExpression`), so the label cannot disagree with the ordering it is
/// meant to describe — a bubble showing "M" while the list is ordered by date
/// would be worse than no bubble.
String collectionScrollLabel(
  CollectionEntryWithCard entry,
  CollectionSortBy sortBy,
) {
  switch (sortBy) {
    case CollectionSortBy.name:
      return _initialLetter(entry.card.name);
    case CollectionSortBy.dateAdded:
      return collectionMonthLabel(entry.entry.createdAt);
    case CollectionSortBy.quantity:
      // Matches the grid cell's own `xN` count badge.
      return 'x${entry.entry.quantity}';
    case CollectionSortBy.cardType:
      // The same `isSpell`/`isTrap` rule the DAO's CASE expression buckets on,
      // so a NULL or unrecognised frame lands with the monsters in both.
      if (entry.card.isSpell) return AppStrings.collectionScrollLabelSpells;
      if (entry.card.isTrap) return AppStrings.collectionScrollLabelTraps;
      return AppStrings.collectionScrollLabelMonsters;
  }
}

/// The first letter of a card's name, or `#` for the many that start with a
/// digit ("7 Colored Fish", "8-Claws Scorpion") or punctuation.
String _initialLetter(String name) {
  final trimmed = name.trimLeft();
  if (trimmed.isEmpty) return AppStrings.collectionScrollLabelOther;
  final first = trimmed[0].toUpperCase();
  final code = first.codeUnitAt(0);
  const a = 0x41;
  const z = 0x5A;
  return (code >= a && code <= z) ? first : AppStrings.collectionScrollLabelOther;
}

/// "Mar 2026" for an epoch-millisecond timestamp.
///
/// **Local** time, unlike `collection_csv.dart`'s deliberate UTC: this is a
/// label a person reads against their own sense of when they logged a card, not
/// an interchange field. Hand-formatted because `intl` is not in the approved
/// stack and one month name does not justify adding it.
String collectionMonthLabel(int epochMs) {
  final date = DateTime.fromMillisecondsSinceEpoch(epochMs);
  return '${AppStrings.monthAbbreviations[date.month - 1]} ${date.year}';
}
