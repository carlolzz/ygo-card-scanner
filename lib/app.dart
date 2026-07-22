import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/constants.dart';
import 'core/router.dart';
import 'core/theme/app_theme.dart';
import 'features/sync/initial_sync_providers.dart';
import 'features/sync/initial_sync_screen.dart';

/// Shown before [needsInitialSyncProvider]'s first read resolves — a
/// couple of fast local queries, so this is on screen only briefly.
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

    return needsSync.when(
      data: (needsSync) => needsSync
          ? MaterialApp(
              title: AppStrings.appName,
              theme: buildAppTheme(),
              home: const InitialSyncScreen(),
            )
          : MaterialApp.router(
              title: AppStrings.appName,
              theme: buildAppTheme(),
              routerConfig: _router,
            ),
      loading: () => MaterialApp(
        title: AppStrings.appName,
        theme: buildAppTheme(),
        home: const _SplashScreen(),
      ),
      error: (error, stackTrace) => MaterialApp(
        title: AppStrings.appName,
        theme: buildAppTheme(),
        home: const InitialSyncScreen(),
      ),
    );
  }
}
