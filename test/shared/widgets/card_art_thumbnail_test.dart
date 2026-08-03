import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/core/theme/tokens.dart';
import 'package:ygo_scanner/models/ygo_card.dart';
import 'package:ygo_scanner/shared/widgets/card_art_thumbnail.dart';
import 'package:ygo_scanner/shared/widgets/card_thumbnail.dart';

const _passcode = '46986414';
const _owned = YgoCard(
  passcode: _passcode,
  name: 'Dark Magician',
  localImagePath: '/already/downloaded.jpg',
);
const _notDownloaded = YgoCard(passcode: _passcode, name: 'Dark Magician');

void main() {
  // The contract that makes this widget safe to put on *every* collection
  // surface: a card whose art is already on disk must not touch the provider at
  // all. A hundred rows each doing a repository lookup to re-learn a path they
  // were handed in the join would be a rebuild storm on the most-used screen.
  testWidgets('a card that already has its art never reads the provider', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: CardArtThumbnail(card: _owned)),
      ),
    );

    final container = ProviderScope.containerOf(
      tester.element(find.byType(CardArtThumbnail)),
    );
    expect(container.exists(cardArtProvider(_passcode)), isFalse);
    expect(
      tester.widget<CardThumbnail>(find.byType(CardThumbnail)).localImagePath,
      _owned.localImagePath,
    );
  });

  // The CSV-import case: `CollectionDao.applyImport` writes rows without ever
  // going through `addOrIncrement`, so imported cards arrive with a NULL
  // `local_image_path` and used to show the placeholder forever.
  testWidgets('a card with no art on disk fetches it', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cardArtProvider(_passcode).overrideWith((ref) async => '/fetched.jpg'),
        ],
        child: const MaterialApp(home: CardArtThumbnail(card: _notDownloaded)),
      ),
    );
    await tester.pump();

    expect(
      tester.widget<CardThumbnail>(find.byType(CardThumbnail)).localImagePath,
      '/fetched.jpg',
    );
  });

  testWidgets('a fetch that fails leaves the placeholder', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cardArtProvider(_passcode).overrideWith((ref) async => null),
        ],
        child: const MaterialApp(home: CardArtThumbnail(card: _notDownloaded)),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
  });

  // The real regression risk of widening this widget's API: a forwarded
  // parameter silently dropped. `size: null` in particular is what lets a grid
  // cell size the artwork from its own width, and losing it would collapse
  // every minified cell to the default 48pt square.
  group('every parameter reaches the inner CardThumbnail', () {
    Future<CardThumbnail> pump(
      WidgetTester tester, {
      required double? size,
      required double? aspectRatio,
      required BoxFit fit,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Center(
              child: SizedBox(
                width: 100,
                child: CardArtThumbnail(
                  card: _owned,
                  size: size,
                  aspectRatio: aspectRatio,
                  fit: fit,
                ),
              ),
            ),
          ),
        ),
      );
      return tester.widget<CardThumbnail>(find.byType(CardThumbnail));
    }

    testWidgets('a grid cell (null size, card aspect, contain)', (tester) async {
      final thumbnail = await pump(
        tester,
        size: null,
        aspectRatio: ScanReticleTokens.cardAspectRatio,
        fit: BoxFit.contain,
      );
      expect(thumbnail.size, isNull);
      expect(thumbnail.aspectRatio, ScanReticleTokens.cardAspectRatio);
      expect(thumbnail.fit, BoxFit.contain);
    });

    testWidgets('a fixed-size list row', (tester) async {
      final thumbnail = await pump(
        tester,
        size: CardThumbnailSizes.collectionTile,
        aspectRatio: ScanReticleTokens.cardAspectRatio,
        fit: BoxFit.contain,
      );
      expect(thumbnail.size, CardThumbnailSizes.collectionTile);
      expect(thumbnail.aspectRatio, ScanReticleTokens.cardAspectRatio);
      expect(thumbnail.fit, BoxFit.contain);
    });

    testWidgets('the historical square default', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: CardArtThumbnail(card: _owned)),
        ),
      );
      final thumbnail = tester.widget<CardThumbnail>(
        find.byType(CardThumbnail),
      );
      expect(thumbnail.size, CardThumbnailSizes.list);
      expect(thumbnail.aspectRatio, isNull);
      expect(thumbnail.fit, BoxFit.cover);
    });
  });
}
