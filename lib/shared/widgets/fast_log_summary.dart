import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/theme/tokens.dart';
import '../../models/card_condition.dart';
import '../../models/card_edition.dart';
import '../../models/card_language.dart';
import '../../models/fast_log_field.dart';

/// What a Fast log is about to write for the details it did not ask about.
///
/// The scan review panel's own doc calls it "the spec's non-negotiable
/// 'reviewable before it reaches the database' gate". With every field hidden
/// that panel is a picture, a quantity and a button, and Confirm writes a
/// grade, an edition and a language that appear nowhere on screen: the tap
/// survives but its *meaning* does not. This is the one line that puts the
/// meaning back, and it occupies exactly the space the hidden chip rows vacated.
///
/// Renders only the **unasked** values, since anything asked about has its own
/// control right here. Returns nothing when everything is asked, so both call
/// sites can build it unconditionally.
///
/// The set is deliberately absent. The manual wizard already prints it under
/// the card name, and reaching it in the scan panel would mean a second
/// `cardPrintingsProvider` read for a line that has to be synchronous.
class FastLogSummary extends StatelessWidget {
  const FastLogSummary({
    required this.askedFields,
    required this.condition,
    required this.edition,
    required this.language,
    super.key,
  });

  final Set<FastLogField> askedFields;
  final CardCondition condition;
  final CardEdition edition;
  final String language;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    // Declaration order, so the line reads the same in both flows and matches
    // the order the chip rows would have appeared in.
    final parts = [
      if (!askedFields.contains(FastLogField.condition)) condition.shortCode,
      if (!askedFields.contains(FastLogField.edition)) edition.label,
      if (!askedFields.contains(FastLogField.language)) languageLabel(language),
    ];
    if (parts.isEmpty) return const SizedBox.shrink();

    return Text(
      // The same separator the set picker and the collection tile already use.
      '${AppStrings.fastLogSilentPrefix}${parts.join(' · ')}',
      style: TextStyle(color: palette.onSurfaceMuted),
    );
  }
}
