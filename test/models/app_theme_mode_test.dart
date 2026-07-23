import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/models/app_theme_mode.dart';

void main() {
  test('toDb produces the exact persisted values', () {
    expect(AppThemeMode.system.toDb(), 'SYSTEM');
    expect(AppThemeMode.light.toDb(), 'LIGHT');
    expect(AppThemeMode.dark.toDb(), 'DARK');
  });

  test('fromDb(toDb(v)) round-trips for every value', () {
    for (final mode in AppThemeMode.values) {
      expect(AppThemeMode.fromDb(mode.toDb()), mode);
    }
  });

  test('fromDb rejects an unknown value', () {
    expect(() => AppThemeMode.fromDb('BROKEN'), throwsArgumentError);
  });

  test('toMaterial maps onto Flutter ThemeMode', () {
    expect(AppThemeMode.system.toMaterial(), ThemeMode.system);
    expect(AppThemeMode.light.toMaterial(), ThemeMode.light);
    expect(AppThemeMode.dark.toMaterial(), ThemeMode.dark);
  });
}
