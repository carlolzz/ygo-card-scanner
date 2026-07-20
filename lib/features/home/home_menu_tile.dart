import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// One tile in the four-tile home menu grid. Pure presentation — no state,
/// no providers.
class HomeMenuTile extends StatelessWidget {
  const HomeMenuTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceRaised,
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
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: AppColors.accent, size: 40),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  label,
                  style: const TextStyle(color: AppColors.onSurface),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
