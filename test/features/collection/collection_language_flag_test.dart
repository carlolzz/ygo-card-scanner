import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/features/collection/collection_grid_tile.dart';
import 'package:ygo_scanner/features/collection/collection_list_tile.dart';
import 'package:ygo_scanner/models/card_condition.dart';
import 'package:ygo_scanner/models/card_language.dart';
import 'package:ygo_scanner/models/collection_entry.dart';
import 'package:ygo_scanner/models/collection_entry_with_card.dart';
import 'package:ygo_scanner/models/ygo_card.dart';
import 'package:ygo_scanner/shared/widgets/language_flag.dart';

/// A card carrying a `localImagePath`, so [CardArtThumbnail] short-circuits to
/// the plain thumbnail and never reaches `cardArtProvider` — these tests are
/// about the flag, and the file being absent just renders the placeholder.
const _card = YgoCard(
  passcode: '89631139',
  name: 'Blue-Eyes White Dragon',
  type: 'Normal Monster',
  localImagePath: 'no-such-file.jpg',
);

CollectionEntryWithCard _entry(String language) => CollectionEntryWithCard(
  entry: CollectionEntry(
    id: 1,
    passcode: _card.passcode,
    condition: CardCondition.nearMint,
    language: language,
    createdAt: 1,
    updatedAt: 1,
  ),
  card: _card,
);

void main() {
  Future<void> pumpTile(WidgetTester tester, Widget tile) async {
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp(home: Scaffold(body: tile))),
    );
    await tester.pump();
  }

  Widget listTile(String language) => CollectionListTile(
    entryWithCard: _entry(language),
    onTap: () {},
    onLongPress: () {},
    onIncrement: () {},
    onDecrement: () {},
    onDelete: () {},
  );

  Widget gridTile(String language, {required bool showName}) =>
      CollectionGridTile(
        entryWithCard: _entry(language),
        showName: showName,
        onTap: () {},
        onLongPress: () {},
      );

  group('the standard row', () {
    testWidgets('flags the entry language', (tester) async {
      await pumpTile(tester, listTile('DE'));

      expect(find.byType(LanguageFlag), findsOneWidget);
      expect(find.text(kCardLanguageFlags['DE']!), findsOneWidget);
    });

    testWidgets('flags English too, so the grade chip never shifts', (
      tester,
    ) async {
      await pumpTile(tester, listTile('EN'));

      expect(find.text(kCardLanguageFlags['EN']!), findsOneWidget);
    });

    testWidgets('the flag sits below the grade chip, the pair centred', (
      tester,
    ) async {
      await pumpTile(tester, listTile('DE'));

      final tile = tester.getRect(find.byType(CollectionListTile));
      final chip = tester.getRect(find.text(CardCondition.nearMint.shortCode));
      final flag = tester.getRect(find.byType(LanguageFlag));
      // The chip's own Column — the nearest one enclosing the flag.
      final block = tester.getRect(
        find
            .ancestor(
              of: find.byType(LanguageFlag),
              matching: find.byType(Column),
            )
            .first,
      );

      // Below, not beside.
      expect(flag.top, greaterThanOrEqualTo(chip.bottom));
      // And the pair straddles the row's midline, which is what leaves them at
      // equal distances from the tile's top and bottom edges.
      expect(block.center.dy, closeTo(tile.center.dy, 0.5));
      expect(block.top - tile.top, closeTo(tile.bottom - block.bottom, 0.5));
    });

    testWidgets('a language with no country renders the code instead', (
      tester,
    ) async {
      await pumpTile(tester, listTile('AE'));

      expect(find.byType(LanguageFlag), findsOneWidget);
      expect(find.text('AE'), findsOneWidget);
    });

    testWidgets('so does an unlisted code a CSV import brought in', (
      tester,
    ) async {
      await pumpTile(tester, listTile('NL'));

      expect(find.text('NL'), findsOneWidget);
    });
  });

  group('the minified grids', () {
    testWidgets('artwork + name cells carry the flag', (tester) async {
      await pumpTile(tester, gridTile('JP', showName: true));

      expect(find.text(kCardLanguageFlags['JP']!), findsOneWidget);
    });

    testWidgets('artwork-only cells carry it too', (tester) async {
      await pumpTile(tester, gridTile('JP', showName: false));

      expect(find.text(kCardLanguageFlags['JP']!), findsOneWidget);
    });

    testWidgets('it sits bottom-left, clear of the quantity badge', (
      tester,
    ) async {
      await pumpTile(tester, gridTile('FR', showName: false));

      final cell = tester.getRect(find.byType(CollectionGridTile));
      final flag = tester.getRect(find.byType(LanguageFlag));

      expect(flag.left - cell.left, lessThan(cell.width / 2));
      expect(cell.bottom - flag.bottom, lessThan(cell.height / 2));
    });
  });
}
