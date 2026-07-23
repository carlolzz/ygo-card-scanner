import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/constants.dart';
import 'core/router.dart';
import 'core/theme/app_theme.dart';
import 'features/settings/settings_providers.dart';
import 'features/sync/initial_sync_providers.dart';
import 'features/sync/initial_sync_screen.dart';
import 'models/app_settings.dart';

/// Shown before [needsInitialSyncProvider] and [settingsControllerProvider]
/// first resolve — a couple of fast local queries, so this is on screen only
/// briefly.
///
/// Deliberately animation-free: no indeterminate spinner. Like
/// `InitialSyncScreen`'s transitional success state (a `SizedBox.shrink`), a
/// state that's only ever on screen for a moment must not host a perpetual
/// `Ticker` — one would hang `pumpAndSettle()` in any test that mounts the
/// real [App]. See `.claude/skills/flutter-test-troubleshooting.md`.
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text(AppStrings.appName),
      ),
    );
  }
}

class App extends ConsumerWidget {
  const App({super.key});

  static final GoRouter _router = buildAppRouter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final needsSync = ref.watch(needsInitialSyncProvider);
    final settings = ref.watch(settingsControllerProvider);

    // Gating the whole app on settings (not just the themed branch) is what
    // lets every downstream controller read them synchronously: by the time
    // any route builds, `settingsControllerProvider` has a value. It also
    // avoids a first-frame flash of dark before a light preference loads.
    if (settings.isLoading) return _app(home: const _SplashScreen());

    final themeMode =
        (settings.value ?? const AppSettings()).themeMode.toMaterial();

    return needsSync.when(
      data: (needsSync) => needsSync
          ? _app(home: const InitialSyncScreen(), themeMode: themeMode)
          : _app(router: _router, themeMode: themeMode),
      loading: () => _app(home: const _SplashScreen(), themeMode: themeMode),
      error: (error, stackTrace) =>
          _app(home: const InitialSyncScreen(), themeMode: themeMode),
    );
  }

  /// One place that knows how the app is themed, so the four gate branches
  /// can't drift apart.
  Widget _app({
    Widget? home,
    GoRouter? router,
    ThemeMode themeMode = ThemeMode.dark,
  }) {
    final theme = buildAppTheme(brightness: Brightness.light);
    final darkTheme = buildAppTheme(brightness: Brightness.dark);

    if (router != null) {
      return MaterialApp.router(
        title: AppStrings.appName,
        theme: theme,
        darkTheme: darkTheme,
        themeMode: themeMode,
        routerConfig: router,
      );
    }
    return MaterialApp(
      title: AppStrings.appName,
      theme: theme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      home: home,
    );
  }
}
