import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/core/theme/tokens.dart';
import 'package:ygo_scanner/features/collection/filter_chip_collapse.dart';

/// The collapse rule behind every filter chip row in the sheet. Worth pinning on
/// its own rather than only through the sheet: the rows it governs (archetype,
/// card type, race) are the ones whose length depends on the user's collection,
/// so the interesting cases are the ones the fixture seed never produces.
void main() {
  List<String> values(int n) => [for (var i = 0; i < n; i++) 'v$i'];

  bool isNone(String _) => false;
  bool Function(String) selects(String value) => (other) => other == value;

  test('a row at or under the threshold is returned whole', () {
    const threshold = CollectionFilterTokens.chipCollapseThreshold;
    for (final n in [0, 1, threshold - 1, threshold]) {
      expect(
        visibleFilterChoices(values(n), isSelected: isNone, expanded: false),
        hasLength(n),
        reason: '$n values should not collapse',
      );
    }
  });

  test('a longer row collapses to the threshold', () {
    final visible = visibleFilterChoices(
      values(40),
      isSelected: isNone,
      expanded: false,
    );
    expect(visible, hasLength(CollectionFilterTokens.chipCollapseThreshold));
    // The head keeps the DAO's order, so the collapsed row agrees with the
    // expanded one about what comes first.
    expect(visible.first, 'v0');
    expect(visible.last, 'v9');
  });

  test('expanding returns the identical list, whatever the length', () {
    final all = values(40);
    expect(
      visibleFilterChoices(all, isSelected: isNone, expanded: true),
      same(all),
    );
  });

  test('a selection inside the head is not duplicated', () {
    final visible = visibleFilterChoices(
      values(40),
      isSelected: selects('v3'),
      expanded: false,
    );
    expect(visible, hasLength(CollectionFilterTokens.chipCollapseThreshold));
    expect(visible.where((v) => v == 'v3'), hasLength(1));
  });

  // The load-bearing case: a collapsed row that hides the active filter reads as
  // an unset filter, while the filter bar's badge still counts it. Verified to
  // fail with the append branch removed before being kept.
  test('a selection past the threshold stays visible', () {
    final visible = visibleFilterChoices(
      values(40),
      isSelected: selects('v37'),
      expanded: false,
    );
    expect(visible, contains('v37'));
    expect(
      visible,
      hasLength(CollectionFilterTokens.chipCollapseThreshold + 1),
      reason: 'the selection is appended, not substituted for a head value',
    );
    expect(visible.first, 'v0', reason: 'the head is left intact');
  });

  test('a predicate matching nothing collapses cleanly', () {
    // The rarity row asks `selected == filterFor(value)`, which is false for
    // every element when no rarity filter is set.
    final visible = visibleFilterChoices(
      values(40),
      isSelected: isNone,
      expanded: false,
    );
    expect(visible, hasLength(CollectionFilterTokens.chipCollapseThreshold));
  });

  test('nullable values work, so the rarity row can share the rule', () {
    // Its list is `List<String?>` where null is the distinct "no rarity" option,
    // which is why the rule takes a predicate rather than comparing to a `T?`.
    final rarities = <String?>[null, ...values(20)];
    final visible = visibleFilterChoices<String?>(
      rarities,
      isSelected: (rarity) => rarity == null,
      expanded: false,
    );
    expect(visible, contains(null));
    expect(visible, hasLength(CollectionFilterTokens.chipCollapseThreshold));
  });
}
