import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/constants.dart';
import 'core/router.dart';
import 'core/theme/app_theme.dart';

class App extends StatelessWidget {
  const App({super.key});

  static final GoRouter _router = buildAppRouter();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: AppStrings.appName,
      theme: buildAppTheme(),
      routerConfig: _router,
    );
  }
}
