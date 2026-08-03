import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/search_terms.dart';
import '../../core/theme/tokens.dart';

/// A one-of-many picker built around a text box: the user types and the options
/// narrow underneath it.
///
/// The `String`-keyed sibling of [PrintingPicker], for the same reason that one
/// exists — a `Wrap` of chips is fine for seven conditions and hopeless for the
/// hundred set names a real collection spans, where it becomes the tallest thing
/// in the sheet and still has to be read one chip at a time.
///
/// It is a *separate widget* rather than a generalisation of [PrintingPicker]:
/// that one is keyed to `Printing`/`int?` across three live call sites in the
/// logging flows, and making it generic would churn all of them to save a file.
/// What they do share is the filter rule ([matchesSearchTerms]), which is the
/// part that would actually be wrong if it drifted.
///
/// Selection is always one of [values] — never free text — so a filter built
/// from it can't fail to match anything. The field doubles as the query and the
/// current selection: while focused it holds whatever is being typed, and on
/// blur it snaps back to the selected label so a half-typed query can never read
/// as a choice.
class SearchableTextPicker extends StatefulWidget {
  const SearchableTextPicker({
    super.key,
    required this.values,
    required this.selected,
    required this.onSelected,
    required this.anyLabel,
    this.hintText,
  });

  /// Every option, in the order they should be offered. May be empty.
  final List<String> values;

  /// The current choice, or null for "no constraint".
  final String? selected;

  final ValueChanged<String?> onSelected;

  /// Wording for the null option, e.g. "All".
  final String anyLabel;

  /// Placeholder while nothing is selected. Defaults to [anyLabel].
  final String? hintText;

  @override
  State<SearchableTextPicker> createState() => _SearchableTextPickerState();
}

class _SearchableTextPickerState extends State<SearchableTextPicker> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  String _query = '';
  bool _open = false;

  @override
  void initState() {
    super.initState();
    _controller.text = widget.selected ?? '';
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(SearchableTextPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The selection can change from outside — Reset clears the whole draft
    // filter, and the box must not keep showing what it just cleared.
    if (widget.selected != oldWidget.selected && !_focusNode.hasFocus) {
      _controller.text = widget.selected ?? '';
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
        _controller.text = widget.selected ?? '';
        _query = '';
      } else {
        // Typing replaces the label rather than editing it character by
        // character — the field is a search box the moment it is tapped.
        _controller.clear();
        _query = '';
      }
    });
  }

  void _select(String? value) {
    widget.onSelected(value);
    _focusNode.unfocus();
    setState(() {
      _open = false;
      _query = '';
      _controller.text = value ?? '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final matches = [
      for (final value in widget.values)
        if (matchesSearchTerms(value, _query)) value,
    ];

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
            hintText: widget.hintText ?? widget.anyLabel,
            hintStyle: TextStyle(color: palette.onSurfaceMuted),
            prefixIcon: Icon(Icons.search, color: palette.onSurfaceMuted),
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear),
                    color: palette.onSurfaceMuted,
                    tooltip: AppStrings.setPickerClearTooltip,
                    // Clearing the box clears the choice too: an empty box and
                    // an applied filter would otherwise disagree.
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
                  _PickerOption(
                    label: widget.anyLabel,
                    selected: widget.selected == null,
                    onTap: () => _select(null),
                  ),
                  for (final value in matches)
                    _PickerOption(
                      label: value,
                      selected: widget.selected == value,
                      onTap: () => _select(value),
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
class _PickerOption extends StatelessWidget {
  const _PickerOption({
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
            if (selected) Icon(Icons.check, size: 18, color: palette.accent),
          ],
        ),
      ),
    );
  }
}
