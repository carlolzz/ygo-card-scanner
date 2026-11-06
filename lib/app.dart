import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/constants.dart';
import 'core/router.dart';
import 'core/theme/app_theme.dart';
import 'features/settings/settings_providers.dart';
import 'features/sync/initial_sync_providers.dart';
import 'features/sync/initial_sync_screen.dart';
import 'models/app_language.dart';
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
    return Scaffold(
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

    // A language change from a loaded state only. The first load resolves
    // before any route has been built, so there is nothing stale to rebuild.
    ref.listen(
      settingsControllerProvider.select((value) => value.value?.appLanguage),
      (previous, next) {
        if (previous != null && previous != next) {
          _rebuildAllDescendants(context);
        }
      },
    );

    // Gating the whole app on settings (not just the themed branch) is what
    // lets every downstream controller read them synchronously: by the time
    // any route builds, `settingsControllerProvider` has a value. It also
    // avoids a first-frame flash of dark before a light preference loads.
    if (settings.isLoading) return _app(home: const _SplashScreen());

    final resolved = settings.value ?? const AppSettings();
    final themeMode = resolved.themeMode.toMaterial();
    final language = resolved.appLanguage;

    return needsSync.when(
      data: (needsSync) => needsSync
          ? _app(
              home: const InitialSyncScreen(),
              themeMode: themeMode,
              language: language,
            )
          : _app(router: _router, themeMode: themeMode, language: language),
      loading: () => _app(
        home: const _SplashScreen(),
        themeMode: themeMode,
        language: language,
      ),
      error: (error, stackTrace) => _app(
        home: const InitialSyncScreen(),
        themeMode: themeMode,
        language: language,
      ),
    );
  }

  static const _localizationsDelegates = [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  static final _supportedLocales = [
    for (final language in AppLanguage.values) language.toLocale(),
  ];

  /// Re-runs `build` on every element below [context], in place, so each one
  /// re-reads its text from `AppStrings`. The same walk a hot reload does.
  ///
  /// **The strings are plain getters, not an inherited widget, so nothing below
  /// `App` depends on them** and a `const` widget that reads one in `build` is
  /// otherwise never rebuilt. A `ValueKey` on `MaterialApp` looks like the
  /// obvious fix and does not work: go_router's navigator carries a `GlobalKey`,
  /// so the navigator is moved into the new tree intact and `const HomeScreen()`
  /// keeps its English text. Rebuilding in place also keeps the current route,
  /// scroll positions and everything else held in `State`.
  ///
  /// Marking only: the rebuilds happen in the next frame, from a listener that
  /// runs outside the build phase.
  static void _rebuildAllDescendants(BuildContext context) {
    void visit(Element element) {
      element
        ..markNeedsBuild()
        ..visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
  }

  /// One place that knows how the app is themed and localized, so the four gate
  /// branches can't drift apart.
  Widget _app({
    Widget? home,
    GoRouter? router,
    ThemeMode themeMode = ThemeMode.dark,
    AppLanguage language = AppLanguage.english,
  }) {
    final theme = buildAppTheme(brightness: Brightness.light);
    final darkTheme = buildAppTheme(brightness: Brightness.dark);

    if (router != null) {
      return MaterialApp.router(
        title: AppStrings.appName,
        theme: theme,
        darkTheme: darkTheme,
        themeMode: themeMode,
        locale: language.toLocale(),
        supportedLocales: _supportedLocales,
        localizationsDelegates: _localizationsDelegates,
        routerConfig: router,
      );
    }
    return MaterialApp(
      title: AppStrings.appName,
      theme: theme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      locale: language.toLocale(),
      supportedLocales: _supportedLocales,
      localizationsDelegates: _localizationsDelegates,
      home: home,
    );
  }
}
