import 'package:go_router/go_router.dart';

import '../features/home/home_screen.dart';
import '../shared/widgets/coming_soon_screen.dart';
import 'constants.dart';
import 'routes.dart';

GoRouter buildAppRouter() {
  return GoRouter(
    initialLocation: AppRoutes.home,
    routes: [
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.scan,
        builder: (context, state) =>
            const ComingSoonScreen(title: AppStrings.homeTileLogCards),
      ),
      GoRoute(
        path: AppRoutes.collection,
        builder: (context, state) =>
            const ComingSoonScreen(title: AppStrings.homeTileMyCollection),
      ),
      GoRoute(
        path: AppRoutes.statistics,
        builder: (context, state) =>
            const ComingSoonScreen(title: AppStrings.homeTileStatistics),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (context, state) =>
            const ComingSoonScreen(title: AppStrings.homeTileSettings),
      ),
    ],
  );
}
