import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// A single selectable chip with the project's selected/unselected styling.
/// Shared between the collection filter bar and the add-card condition/
/// edition pickers so both stay visually consistent.
class LabeledChoiceChip extends StatelessWidget {
  const LabeledChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.selectedColor,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final Color selectedColor;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      // Material inserts a leading checkmark when a `ChoiceChip` is selected,
      // which makes the chip **wider than it was**. In a `Wrap` that reflows
      // the whole run: chips after the selected one shift right and can jump a
      // line, so tapping through the language row makes the block flicker and
      // move under the finger. Selection is already unmistakable from
      // [selectedColor] plus the dark label ink, so the checkmark is pure cost.
      showCheckmark: false,
      onSelected: (_) => onSelected(),
      selectedColor: selectedColor,
      backgroundColor: palette.surfaceRaised,
      labelStyle: TextStyle(
        // Selected chips carry a fixed dark ink: the fill colors are the same
        // in both themes, so this can't follow the palette's background.
        color: selected ? ConditionChipColors.onSelected : palette.onSurface,
      ),
    );
  }
}
