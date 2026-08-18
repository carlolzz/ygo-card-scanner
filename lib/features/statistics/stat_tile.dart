import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// One big figure over its label, on a raised card.
///
/// Public and in its own file since step 26, when the value breakdown screen
/// needed the same two totals in the same shape as the Statistics screen it is
/// pushed from. A second copy would have drifted — and the whole point of that
/// screen is showing the numbers behind those tiles.
class StatTile extends StatelessWidget {
  const StatTile({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              color: palette.accent,
              fontWeight: FontWeight.bold,
              fontSize: StatTileTokens.valueFontSize,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(label, style: TextStyle(color: palette.onSurfaceMuted)),
        ],
      ),
    );
  }
}
