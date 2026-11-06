import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/theme/tokens.dart';

/// The app's search box: a filled, rounded field with a search glyph on the
/// left and, while there is anything typed, a clear button on the right.
///
/// One widget because the collection, the card search and the manual add
/// wizard all carried an identical hand-rolled `TextField`, and none of them
/// could be cleared without deleting the query a character at a time.
///
/// Stateful to own the [TextEditingController] the clear button needs. The
/// query itself still lives in the caller's provider; [initialValue] seeds the
/// field from it, so a remounted field shows what is actually being searched
/// rather than an empty box over a filtered list.
class SearchField extends StatefulWidget {
  const SearchField({
    super.key,
    required this.hintText,
    required this.onChanged,
    this.initialValue = '',
    this.autofocus = false,
  });

  final String hintText;

  /// Called on every edit, and with `''` when the clear button is tapped.
  final ValueChanged<String> onChanged;

  final String initialValue;
  final bool autofocus;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    // `clear()` does not fire `onChanged` — only user edits do — so the
    // provider has to be told explicitly or the list stays filtered.
    widget.onChanged('');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return TextField(
      controller: _controller,
      autofocus: widget.autofocus,
      style: TextStyle(color: palette.onSurface),
      onChanged: (value) {
        // Rebuild only to show or hide the clear button.
        setState(() {});
        widget.onChanged(value);
      },
      decoration: InputDecoration(
        hintText: widget.hintText,
        hintStyle: TextStyle(color: palette.onSurfaceMuted),
        prefixIcon: Icon(Icons.search, color: palette.onSurfaceMuted),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear),
                color: palette.onSurfaceMuted,
                tooltip: AppStrings.searchClearTooltip,
                onPressed: _clear,
              ),
        filled: true,
        fillColor: palette.surfaceRaised,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
