import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/core/constants.dart';
import 'package:ygo_scanner/core/router.dart';
import 'package:ygo_scanner/core/theme/tokens.dart';
import 'package:ygo_scanner/features/home/home_menu_tile.dart';
import 'package:ygo_scanner/features/statistics/statistics_providers.dart';
import 'package:ygo_scanner/features/statistics/statistics_screen.dart';

void main() {
  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: buildAppRouter()));
  }

  testWidgets('renders all four home tile labels', (tester) async {
    await pumpApp(tester);

    expect(find.text(AppStrings.homeTileLogCards), findsOneWidget);
    expect(find.text(AppStrings.homeTileMyCollection), findsOneWidget);
    expect(find.text(AppStrings.homeTileStatistics), findsOneWidget);
    expect(find.text(AppStrings.homeTileSettings), findsOneWidget);
  });

  // Every home destination now navigates to a real screen. This asserts only
  // the Statistics *routing*; the screen's own content and its real db-backed
  // aggregates are covered by test/features/statistics/statistics_screen_test
  // .dart. The stats provider is overridden with a ready value here so the
  // navigation check never touches the sqflite background isolate (which, mid
  // route-transition, does not settle under a widget test).
  testWidgets('tapping "Statistics" navigates to the statistics screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          collectionStatsProvider.overrideWith(
            (ref) async => const CollectionStats(
              totalCopies: 1,
              distinctCards: 1,
              byCondition: {'NEAR_MINT': 1},
              byLanguage: {'EN': 1},
              byCardType: {'Normal Monster': 1},
            ),
          ),
        ],
        child: MaterialApp.router(routerConfig: buildAppRouter()),
      ),
    );

    await tester.tap(find.text(AppStrings.homeTileStatistics));
    await tester.pumpAndSettle();

    expect(find.byType(StatisticsScreen), findsOneWidget);
    // No longer a placeholder.
    expect(find.text(AppStrings.comingSoonMessage), findsNothing);
  });

  testWidgets('home tiles meet the minimum tap target size', (tester) async {
    await pumpApp(tester);

    final size = tester.getSize(find.byType(HomeMenuTile).first);

    expect(size.width, greaterThanOrEqualTo(AppTapTarget.minSize));
    expect(size.height, greaterThanOrEqualTo(AppTapTarget.minSize));
  });
}
