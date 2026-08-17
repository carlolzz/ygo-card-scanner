import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// One tile in the home menu. Pure presentation — no state, no providers.
class HomeMenuTile extends StatelessWidget {
  const HomeMenuTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.wide = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// The full-width tile under the 2x2 grid.
  ///
  /// Lays the icon and label out in a **row** rather than a column: stacking
  /// them in a box that is much wider than it is tall leaves a band of empty
  /// space either side of a centred column, and forces the tile to be taller
  /// than it needs to be to fit them. See [HomeMenuTokens] for why the fifth
  /// destination is shaped differently at all.
  ///
  /// Only the *layout* differs — the icon is [HomeMenuTokens.iconSize] here as
  /// everywhere else, so all five tiles read as five of the same thing.
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final iconWidget = Icon(
      icon,
      color: palette.accent,
      size: HomeMenuTokens.iconSize,
    );
    final text = Text(
      label,
      style: TextStyle(color: palette.onSurface),
      textAlign: TextAlign.center,
    );

    return Material(
      color: palette.surfaceRaised,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: AppTapTarget.minSize,
            minHeight: AppTapTarget.minSize,
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: wide
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      iconWidget,
                      const SizedBox(width: AppSpacing.sm),
                      Flexible(child: text),
                    ],
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      iconWidget,
                      const SizedBox(height: AppSpacing.sm),
                      text,
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
