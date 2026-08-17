import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/core/theme/tokens.dart';
import 'package:ygo_scanner/features/collection/collection_list_tile.dart';
import 'package:ygo_scanner/models/card_condition.dart';
import 'package:ygo_scanner/models/collection_entry.dart';
import 'package:ygo_scanner/models/collection_entry_with_card.dart';
import 'package:ygo_scanner/models/printing.dart';
import 'package:ygo_scanner/models/ygo_card.dart';
import 'package:ygo_scanner/shared/widgets/card_thumbnail.dart';

/// The collection row's height is the point of the step-24 change, so these
/// assert the number rather than describing it.
///
/// **They exist because the tokens used to lie.** `_TileAction` sized its
/// buttons through `constraints`, which Material 3 applies *inside* an
/// [IconButton]'s `ButtonStyle` minimum — so the buttons rendered at
/// `visualDensity: compact`'s 40pt floor whatever `actionButtonSize` said, and
/// the row was 132pt while `CollectionTileTokens` documented 102. Nothing
/// caught it, because nothing measured the row. These do.
///
/// The row is as tall as its tallest child plus
/// `2 * CollectionTileTokens.verticalPadding`, and that child is the
/// three-button action column. The artwork and the text block both have to stay
/// under it — either one growing past would grow every row in the list.

/// Carries a `localImagePath`, so `CardArtThumbnail` short-circuits to the
/// plain thumbnail and never reaches `cardArtProvider`. The file is absent, so
/// the placeholder renders — which occupies the same box as the image would.
const _card = YgoCard(
  passcode: '89631139',
  name: 'Blue-Eyes White Dragon',
  type: 'Normal Monster',
  localImagePath: 'no-such-file.jpg',
);

/// The worst case for height: a name long enough to wrap to two lines, plus
/// both secondary lines. If the row holds its height here it holds it anywhere.
const _longNameCard = YgoCard(
  passcode: '12345678',
  name: 'Elemental HERO Shining Flare Wingman',
  type: 'Fusion Monster',
  localImagePath: 'no-such-file.jpg',
);

CollectionEntryWithCard _entry({
  YgoCard card = _card,
  Printing? printing,
  int quantity = 1,
}) => CollectionEntryWithCard(
  entry: CollectionEntry(
    id: 1,
    passcode: card.passcode,
    printingId: printing?.id,
    condition: CardCondition.nearMint,
    language: 'EN',
    quantity: quantity,
    createdAt: 1,
    updatedAt: 1,
  ),
  card: card,
  printing: printing,
);

/// The row height the tokens describe: the action column plus the inset.
const double _expectedHeight =
    3 * CollectionTileTokens.actionButtonSize +
    2 * CollectionTileTokens.verticalPadding;

void main() {
  Future<void> pumpTile(
    WidgetTester tester,
    CollectionEntryWithCard entryWithCard, {
    bool selectionActive = false,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: CollectionListTile(
              entryWithCard: entryWithCard,
              selectionActive: selectionActive,
              onTap: () {},
              onLongPress: () {},
              onIncrement: () {},
              onDecrement: () {},
              onDelete: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a plain row is exactly as tall as its tokens say', (
    tester,
  ) async {
    await pumpTile(tester, _entry());

    expect(
      tester.getSize(find.byType(CollectionListTile)).height,
      _expectedHeight,
    );
  });

  // The whole shrink is worth nothing if a wrapped name and both secondary
  // lines push past the action column. `CollectionTileTokens.secondaryFontSize`
  // is what keeps that block inside the budget.
  testWidgets('a wrapped name with a set and a rarity costs nothing', (
    tester,
  ) async {
    await pumpTile(
      tester,
      _entry(
        card: _longNameCard,
        printing: const Printing(
          id: 7,
          passcode: '12345678',
          setCode: 'LOB-EN001',
          setName: 'Legend of Blue Eyes White Dragon',
          rarity: 'Ultra Rare',
        ),
      ),
    );

    expect(find.text('LOB-EN001'), findsOneWidget);
    expect(find.text('Ultra Rare'), findsOneWidget);
    expect(
      tester.getSize(find.byType(CollectionListTile)).height,
      _expectedHeight,
    );
  });

  // Entering multi-select replaces the action column with a slot of the same
  // size, so the list must not reflow under the finger that long-pressed.
  testWidgets('selection mode does not change the row height', (tester) async {
    await pumpTile(tester, _entry(), selectionActive: true);

    expect(
      tester.getSize(find.byType(CollectionListTile)).height,
      _expectedHeight,
    );
  });

  // The bug this file exists for: each button must actually be
  // `actionButtonSize`, not Material's 40pt compact floor. Measured, because a
  // token that is ignored looks exactly like a token that is honoured.
  testWidgets('each action button is really its token size', (tester) async {
    await pumpTile(tester, _entry());

    final buttons = find.byType(IconButton);
    expect(buttons, findsNWidgets(3));
    for (var i = 0; i < 3; i++) {
      expect(
        tester.getSize(buttons.at(i)),
        const Size.square(CollectionTileTokens.actionButtonSize),
      );
    }
  });

  // The artwork is free only while it stays under the column that sets the
  // height. Above that, every row in the list grows.
  test('the artwork fits inside the action column', () {
    expect(
      CardThumbnailSizes.collectionTile,
      lessThanOrEqualTo(3 * CollectionTileTokens.actionButtonSize),
    );
  });

  // A square crop, not the portrait card the rest of the app draws — which is
  // the only reason a bigger picture and a shorter row are compatible at all.
  testWidgets('the artwork is a square crop aligned above centre', (
    tester,
  ) async {
    await pumpTile(tester, _entry());

    final thumbnail = tester.widget<CardThumbnail>(find.byType(CardThumbnail));
    expect(thumbnail.aspectRatio, isNull, reason: 'square, not 59/86');
    expect(thumbnail.fit, BoxFit.cover);
    expect(thumbnail.alignment, CollectionTileTokens.artAlignment);
    expect(
      CollectionTileTokens.artAlignment.y,
      lessThan(0),
      reason: 'a centred crop would cut the card name off the top',
    );

    final art = tester.getSize(find.byType(CardThumbnail));
    expect(art.width, art.height);
    expect(art.width, CardThumbnailSizes.collectionTile);
  });
}
