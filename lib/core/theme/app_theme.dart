import 'package:flutter/material.dart';

import 'tokens.dart';

ThemeData buildAppTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.accent,
    brightness: Brightness.dark,
    surface: AppColors.surface,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.background,
    dividerColor: AppColors.divider,
    textTheme: ThemeData.dark().textTheme.apply(
      bodyColor: AppColors.onSurface,
      displayColor: AppColors.onSurface,
    ),
  );
}
