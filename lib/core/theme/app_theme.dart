import 'package:flutter/material.dart';

import 'tokens.dart';

/// Builds the app theme for [brightness], registering the matching
/// [AppPalette] as a theme extension so every widget's `AppPalette.of(context)`
/// resolves to the right surfaces.
///
/// Defaults to dark: the app is dark-first, and this keeps the theme correct
/// anywhere the mode isn't (or can't yet be) known.
ThemeData buildAppTheme({Brightness brightness = Brightness.dark}) {
  final palette = brightness == Brightness.dark
      ? AppPalette.dark
      : AppPalette.light;

  final colorScheme = ColorScheme.fromSeed(
    seedColor: palette.accent,
    brightness: brightness,
    surface: palette.surface,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: palette.background,
    dividerColor: palette.divider,
    textTheme:
        (brightness == Brightness.dark
                ? ThemeData.dark()
                : ThemeData.light())
            .textTheme
            .apply(
              bodyColor: palette.onSurface,
              displayColor: palette.onSurface,
            ),
    extensions: [palette],
  );
}
