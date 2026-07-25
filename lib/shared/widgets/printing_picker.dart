import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/theme/tokens.dart';
import '../../models/printing.dart';

/// A set/expansion picker built around a text box: the user types a set name,
/// set code or rarity and the card's known printings narrow underneath it.
///
/// Replaces the `DropdownButton` this used to be in every logging flow. A card
/// can carry a dozen printings, and a dropdown makes finding one a scroll — the
/// user knows which set the card in their hand is from, so let them type it.
///
/// The search is over the printings the app already knows for this passcode
/// (from the YGOPRODeck sync), so a pick always resolves to a real
/// `printings.id`; there is no free-text set that the database doesn't have.
/// "No specific set" is always offered — it is what a card with an unknown or
/// irrelevant printing is logged as, and it stays the default.
///
/// The field doubles as the query and the current selection: while focused it
/// holds whatever the user is typing, and on blur it snaps back to the selected
/// printing's label so a half-typed query can never read as a choice.
class PrintingPicker extends StatefulWidget {
  const PrintingPicker({
    super.key,
    required this.printings,
    required this.selectedId,
    required this.onSelected,
    required this.noSetLabel,
  });

  /// Every printing known for this card. May be empty.
  final List<Printing> printings;

  /// The currently chosen `printings.id`, or null for "no specific set".
  final int? selectedId;

  final ValueChanged<int?> onSelected;

  /// Wording for the null option, which differs per flow ("No specific set").
  final String noSetLabel;

  @override
  State<PrintingPicker> createState() => _PrintingPickerState();
}

class _PrintingPickerState extends State<PrintingPicker> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  String _query = '';
  bool _open = false;

  @override
  void initState() {
    super.initState();
    _controller.text = _selectedLabel();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(PrintingPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The selection can change from outside — the scan controller clears it
    // between cards, so the box must not keep showing the previous card's set.
    if (widget.selectedId != oldWidget.selectedId && !_focusNode.hasFocus) {
      _controller.text = _selectedLabel();
      _query = '';
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    setState(() {
      _open = _focusNode.hasFocus;
      if (!_focusNode.hasFocus) {
        // Abandoned query: restore the label of whatever is actually selected.
        _controller.text = _selectedLabel();
        _query = '';
      } else {
        // Typing replaces the label rather than editing it character by
        // character — the field is a search box the moment it is tapped.
        _controller.clear();
        _query = '';
      }
    });
  }

  String _selectedLabel() {
    final id = widget.selectedId;
    if (id == null) return '';
    for (final printing in widget.printings) {
      if (printing.id == id) {
        return printing.displayLabel.isEmpty
            ? widget.noSetLabel
            : printing.displayLabel;
      }
    }
    return '';
  }

  void _select(int? id) {
    widget.onSelected(id);
    _focusNode.unfocus();
    setState(() {
      _open = false;
      _query = '';
      final printing = id == null
          ? null
          : widget.printings.firstWhere((printing) => printing.id == id);
      _controller.text = printing == null
          ? ''
          : (printing.displayLabel.isEmpty
                ? widget.noSetLabel
                : printing.displayLabel);
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final matches = filterPrintings(widget.printings, _query);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          focusNode: _focusNode,
          style: TextStyle(color: palette.onSurface),
          onChanged: (value) => setState(() => _query = value),
          decoration: InputDecoration(
            isDense: true,
            hintText: widget.noSetLabel,
            hintStyle: TextStyle(color: palette.onSurfaceMuted),
            prefixIcon: Icon(Icons.search, color: palette.onSurfaceMuted),
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear),
                    color: palette.onSurfaceMuted,
                    tooltip: AppStrings.setPickerClearTooltip,
                    // Clearing the box also clears the choice: an empty set box
                    // and a card logged under a set would otherwise disagree.
                    onPressed: () => _select(null),
                  ),
            border: const OutlineInputBorder(),
          ),
        ),
        if (_open) ...[
          const SizedBox(height: AppSpacing.xs),
          ConstrainedBox(
            constraints: const BoxConstraints(
              maxHeight: PrintingPickerTokens.maxListHeight,
            ),
            child: Material(
              color: palette.surfaceRaised,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: [
                  _PrintingOption(
                    label: widget.noSetLabel,
                    selected: widget.selectedId == null,
                    onTap: () => _select(null),
                  ),
                  for (final printing in matches)
                    _PrintingOption(
                      label: printing.displayLabel.isEmpty
                          ? widget.noSetLabel
                          : printing.displayLabel,
                      selected: widget.selectedId == printing.id,
                      onTap: () => _select(printing.id),
                    ),
                  if (matches.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                      child: Text(
                        AppStrings.setPickerNoMatches,
                        style: TextStyle(color: palette.onSurfaceMuted),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// One row of the results list.
class _PrintingOption extends StatelessWidget {
  const _PrintingOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.onSurface,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            if (selected)
              Icon(Icons.check, size: 18, color: palette.accent),
          ],
        ),
      ),
    );
  }
}
