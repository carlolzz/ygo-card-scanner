import 'package:flutter/material.dart';

/// The user's theme preference. Persisted to SQLite by name (in the `meta`
/// table, not a column), never by ordinal — same rule as every other enum here.
///
/// Distinct from Material's [ThemeMode] so the persistence format is ours and
/// doesn't drift if Flutter ever reorders or extends its enum.
enum AppThemeMode {
  system('System'),
  light('Light'),
  dark('Dark');

  const AppThemeMode(this.label);

  final String label;

  ThemeMode toMaterial() => switch (this) {
    AppThemeMode.system => ThemeMode.system,
    AppThemeMode.light => ThemeMode.light,
    AppThemeMode.dark => ThemeMode.dark,
  };

  String toDb() => switch (this) {
    AppThemeMode.system => 'SYSTEM',
    AppThemeMode.light => 'LIGHT',
    AppThemeMode.dark => 'DARK',
  };

  static AppThemeMode fromDb(String value) => switch (value) {
    'SYSTEM' => AppThemeMode.system,
    'LIGHT' => AppThemeMode.light,
    'DARK' => AppThemeMode.dark,
    _ => throw ArgumentError('Unknown AppThemeMode db value: $value'),
  };
}
