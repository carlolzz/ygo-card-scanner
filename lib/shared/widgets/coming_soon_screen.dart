import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/theme/tokens.dart';

/// Shared placeholder for any route whose real screen hasn't been built
/// yet, so tapping a home tile never dead-ends.
class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text(
            AppStrings.comingSoonMessage,
            style: const TextStyle(color: AppColors.onSurfaceMuted),
          ),
        ),
      ),
    );
  }
}
