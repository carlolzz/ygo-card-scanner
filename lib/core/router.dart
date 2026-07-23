import 'package:go_router/go_router.dart';

import '../features/add_card/add_card_screen.dart';
import '../features/collection/collection_detail_screen.dart';
import '../features/collection/collection_screen.dart';
import '../features/home/home_screen.dart';
import '../features/scan/scan_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/statistics/statistics_screen.dart';
import '../models/collection_entry_with_card.dart';
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
        builder: (context, state) => const ScanScreen(),
      ),
      GoRoute(
        path: AppRoutes.addCard,
        builder: (context, state) => const AddCardScreen(),
      ),
      GoRoute(
        path: AppRoutes.collection,
        builder: (context, state) => const CollectionScreen(),
      ),
      GoRoute(
        path: AppRoutes.collectionDetail,
        builder: (context, state) => CollectionDetailScreen(
          entryWithCard: state.extra! as CollectionEntryWithCard,
        ),
      ),
      GoRoute(
        path: AppRoutes.statistics,
        builder: (context, state) => const StatisticsScreen(),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
}
