import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/core/constants.dart';
import 'package:ygo_scanner/core/theme/tokens.dart';
import 'package:ygo_scanner/data/db/dao/collection_dao.dart';
import 'package:ygo_scanner/features/collection/collection_scroll_slider_math.dart';
import 'package:ygo_scanner/models/card_condition.dart';
import 'package:ygo_scanner/models/card_edition.dart';
import 'package:ygo_scanner/models/collection_entry.dart';
import 'package:ygo_scanner/models/collection_entry_with_card.dart';
import 'package:ygo_scanner/models/ygo_card.dart';

/// The arithmetic behind the fast-browse slider. A wrong constant here does not
/// crash — it puts the thumb somewhere plausible and slightly wrong — so these
/// pin it directly rather than through a laid-out widget.
void main() {
  CollectionEntryWithCard entryFor(
    YgoCard card, {
    int quantity = 1,
    int createdAt = 0,
  }) => CollectionEntryWithCard(
    entry: CollectionEntry(
      id: 1,
      passcode: card.passcode,
      condition: CardCondition.nearMint,
      edition: CardEdition.unlimited,
      language: 'EN',
      quantity: quantity,
      createdAt: createdAt,
      updatedAt: createdAt,
    ),
    card: card,
  );

  group('collectionSliderReservesGutter', () {
    // The predicate is deliberately a function of the item count alone: the
    // gutter narrows the grid's cross axis, which changes the column count,
    // which changes the scroll extent — so anything measured would feed back
    // into its own input.
    test('reserves nothing below the threshold', () {
      expect(collectionSliderReservesGutter(0), isFalse);
      expect(
        collectionSliderReservesGutter(
          CollectionScrollSliderTokens.minItems - 1,
        ),
        isFalse,
      );
    });

    test('reserves at and above the threshold', () {
      expect(
        collectionSliderReservesGutter(CollectionScrollSliderTokens.minItems),
        isTrue,
      );
      expect(collectionSliderReservesGutter(500), isTrue);
    });
  });

  group('collectionSliderIsScrollable', () {
    test('content that fits paints nothing', () {
      expect(
        collectionSliderIsScrollable((
          pixels: 0,
          maxScrollExtent: 0,
          viewportDimension: 400,
        )),
        isFalse,
      );
    });

    test('overflowing content paints', () {
      expect(
        collectionSliderIsScrollable((
          pixels: 0,
          maxScrollExtent: 1200,
          viewportDimension: 400,
        )),
        isTrue,
      );
    });

    // An unbounded viewport reports infinity; nothing downstream should divide
    // by it.
    test('a non-finite extent paints nothing', () {
      expect(
        collectionSliderIsScrollable((
          pixels: 0,
          maxScrollExtent: double.infinity,
          viewportDimension: 400,
        )),
        isFalse,
      );
    });
  });

  group('sliderThumbExtent', () {
    test('is the viewport in the same proportion as the content', () {
      // A quarter of the content visible: a quarter of a 400pt track.
      expect(
        sliderThumbExtent(
          trackExtent: 400,
          viewportDimension: 400,
          contentExtent: 1600,
        ),
        100,
      );
    });

    test('is floored so it stays grabbable on a very long list', () {
      final extent = sliderThumbExtent(
        trackExtent: 400,
        viewportDimension: 400,
        contentExtent: 100000,
      );
      expect(extent, CollectionScrollSliderTokens.minThumbExtent);
    });

    test('never exceeds the track', () {
      expect(
        sliderThumbExtent(
          trackExtent: 400,
          viewportDimension: 400,
          contentExtent: 401,
        ),
        lessThanOrEqualTo(400),
      );
    });

    test('degrades to zero rather than dividing by zero', () {
      expect(
        sliderThumbExtent(
          trackExtent: 400,
          viewportDimension: 400,
          contentExtent: 0,
        ),
        0,
      );
      expect(
        sliderThumbExtent(
          trackExtent: 0,
          viewportDimension: 400,
          contentExtent: 1600,
        ),
        0,
      );
    });
  });

  group('sliderFractionForOffset', () {
    test('maps the scroll range onto 0..1', () {
      expect(sliderFractionForOffset(offset: 0, maxScrollExtent: 800), 0);
      expect(sliderFractionForOffset(offset: 400, maxScrollExtent: 800), 0.5);
      expect(sliderFractionForOffset(offset: 800, maxScrollExtent: 800), 1);
    });

    test('clamps an overscrolled offset', () {
      expect(sliderFractionForOffset(offset: -50, maxScrollExtent: 800), 0);
      expect(sliderFractionForOffset(offset: 900, maxScrollExtent: 800), 1);
    });

    // The case that makes every caller safe before the first layout has
    // reported real content dimensions.
    test('non-scrolling content is fraction zero', () {
      expect(sliderFractionForOffset(offset: 0, maxScrollExtent: 0), 0);
      expect(
        sliderFractionForOffset(offset: 10, maxScrollExtent: double.infinity),
        0,
      );
    });
  });

  group('thumb position round-trips', () {
    test('sliderThumbTop spans the travel, not the whole track', () {
      // 400pt track, 100pt thumb: the top edge can only reach 300.
      expect(
        sliderThumbTop(fraction: 0, trackExtent: 400, thumbExtent: 100),
        0,
      );
      expect(
        sliderThumbTop(fraction: 1, trackExtent: 400, thumbExtent: 100),
        300,
      );
      expect(
        sliderThumbTop(fraction: 0.5, trackExtent: 400, thumbExtent: 100),
        150,
      );
    });

    // Dragging and the resulting scroll have to agree exactly, or the thumb
    // fights the finger.
    test('offset and thumb top are exact inverses', () {
      for (final fraction in [0.0, 0.13, 0.5, 0.87, 1.0]) {
        final top = sliderThumbTop(
          fraction: fraction,
          trackExtent: 400,
          thumbExtent: 100,
        );
        final offset = sliderOffsetForThumbTop(
          thumbTop: top,
          trackExtent: 400,
          thumbExtent: 100,
          maxScrollExtent: 2000,
        );
        expect(
          sliderFractionForOffset(offset: offset, maxScrollExtent: 2000),
          moreOrLessEquals(fraction, epsilon: 1e-9),
        );
      }
    });

    // Content that barely overflows leaves the thumb filling the track: there
    // is nowhere to drag it, and the naive division is by zero.
    test('a thumb that fills the track cannot be dragged', () {
      expect(
        sliderOffsetForThumbTop(
          thumbTop: 40,
          trackExtent: 400,
          thumbExtent: 400,
          maxScrollExtent: 20,
        ),
        0,
      );
    });

    test('a drag past either end clamps to the scroll range', () {
      expect(
        sliderOffsetForThumbTop(
          thumbTop: -80,
          trackExtent: 400,
          thumbExtent: 100,
          maxScrollExtent: 2000,
        ),
        0,
      );
      expect(
        sliderOffsetForThumbTop(
          thumbTop: 9999,
          trackExtent: 400,
          thumbExtent: 100,
          maxScrollExtent: 2000,
        ),
        2000,
      );
    });
  });

  group('sliderIndexForFraction', () {
    test('is exact at both ends', () {
      expect(sliderIndexForFraction(0, 200), 0);
      expect(sliderIndexForFraction(1, 200), 199);
    });

    test('is linear in between', () {
      expect(sliderIndexForFraction(0.5, 201), 100);
    });

    test('an empty collection has no item to name', () {
      expect(sliderIndexForFraction(0.5, 0), 0);
    });

    test('never runs off the end', () {
      expect(sliderIndexForFraction(1.5, 10), 9);
      expect(sliderIndexForFraction(-1, 10), 0);
    });
  });

  group('sliderLabelTop', () {
    test('centres the bubble on the thumb', () {
      expect(
        sliderLabelTop(
          thumbTop: 100,
          thumbExtent: 40,
          labelExtent: 36,
          trackExtent: 400,
        ),
        102,
      );
    });

    test('keeps the bubble inside the track at both ends', () {
      expect(
        sliderLabelTop(
          thumbTop: 0,
          thumbExtent: 40,
          labelExtent: 60,
          trackExtent: 400,
        ),
        0,
      );
      expect(
        sliderLabelTop(
          thumbTop: 360,
          thumbExtent: 40,
          labelExtent: 60,
          trackExtent: 400,
        ),
        340,
      );
    });
  });

  group('collectionScrollLabel', () {
    const blueEyes = YgoCard(
      passcode: '89631139',
      name: 'Blue-Eyes White Dragon',
    );
    const raigeki = YgoCard(
      passcode: '12580477',
      name: 'Raigeki',
      frameType: 'spell',
    );
    const mirrorForce = YgoCard(
      passcode: '44095762',
      name: 'Mirror Force',
      frameType: 'trap',
    );

    test('by name it is the initial letter', () {
      expect(
        collectionScrollLabel(entryFor(blueEyes), CollectionSortBy.name),
        'B',
      );
    });

    // Common enough to need a bucket: "7 Colored Fish", "8-Claws Scorpion".
    test('a name starting with a digit falls into the # bucket', () {
      const numbered = YgoCard(passcode: '1', name: '7 Colored Fish');
      expect(
        collectionScrollLabel(entryFor(numbered), CollectionSortBy.name),
        AppStrings.collectionScrollLabelOther,
      );
    });

    test('by quantity it matches the cell badge', () {
      expect(
        collectionScrollLabel(
          entryFor(blueEyes, quantity: 12),
          CollectionSortBy.quantity,
        ),
        'x12',
      );
    });

    // The same isSpell/isTrap rule the DAO's CASE expression buckets on, so an
    // unrecognised frame lands with the monsters in both.
    test('by card type it names the same buckets the DAO orders by', () {
      expect(
        collectionScrollLabel(entryFor(blueEyes), CollectionSortBy.cardType),
        AppStrings.collectionScrollLabelMonsters,
      );
      expect(
        collectionScrollLabel(entryFor(raigeki), CollectionSortBy.cardType),
        AppStrings.collectionScrollLabelSpells,
      );
      expect(
        collectionScrollLabel(entryFor(mirrorForce), CollectionSortBy.cardType),
        AppStrings.collectionScrollLabelTraps,
      );
    });

    test('by date added it is the month', () {
      final march = DateTime(2026, 3, 14, 9, 30);
      expect(
        collectionScrollLabel(
          entryFor(blueEyes, createdAt: march.millisecondsSinceEpoch),
          CollectionSortBy.dateAdded,
        ),
        'Mar 2026',
      );
    });

    // Local time, unlike the CSV exporter's deliberate UTC: this is a label read
    // against the user's own sense of when they logged a card.
    test('the month label is local, and covers every month', () {
      for (var month = 1; month <= 12; month++) {
        expect(
          collectionMonthLabel(DateTime(2026, month, 15).millisecondsSinceEpoch),
          '${AppStrings.monthAbbreviations[month - 1]} 2026',
        );
      }
    });
  });
}
