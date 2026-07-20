import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/core/constants.dart';
import 'package:ygo_scanner/core/router.dart';
import 'package:ygo_scanner/core/theme/tokens.dart';
import 'package:ygo_scanner/features/home/home_menu_tile.dart';

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

  for (final tileLabel in [
    AppStrings.homeTileLogCards,
    AppStrings.homeTileMyCollection,
    AppStrings.homeTileStatistics,
    AppStrings.homeTileSettings,
  ]) {
    testWidgets('tapping "$tileLabel" navigates to its coming-soon screen', (
      tester,
    ) async {
      await pumpApp(tester);

      await tester.tap(find.text(tileLabel));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text(tileLabel),
        ),
        findsOneWidget,
      );
      expect(find.text(AppStrings.comingSoonMessage), findsOneWidget);
    });
  }

  testWidgets('home tiles meet the minimum tap target size', (tester) async {
    await pumpApp(tester);

    final size = tester.getSize(find.byType(HomeMenuTile).first);

    expect(size.width, greaterThanOrEqualTo(AppTapTarget.minSize));
    expect(size.height, greaterThanOrEqualTo(AppTapTarget.minSize));
  });
}
