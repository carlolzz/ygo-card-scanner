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
