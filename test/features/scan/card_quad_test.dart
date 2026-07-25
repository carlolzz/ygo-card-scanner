import 'package:flutter/painting.dart' show Offset, Rect, Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/core/theme/tokens.dart';
import 'package:ygo_scanner/features/scan/card_quad.dart';

/// The detector gates against the whole (already cropped) buffer.
const _wholeImage = Rect.fromLTRB(0, 0, 1, 1);
const _imageSize = Size(400, 600);

/// A card-shaped quad centred in the image, sized as a fraction of it.
List<Offset> cardQuad({
  double fraction = 0.85,
  Offset centre = const Offset(200, 300),
}) {
  // Fill `fraction` of the image height, with a real card's aspect ratio.
  final height = _imageSize.height * fraction;
  final width = height * ScanReticleTokens.cardAspectRatio;
  return [
    centre + Offset(-width / 2, -height / 2),
    centre + Offset(width / 2, -height / 2),
    centre + Offset(width / 2, height / 2),
    centre + Offset(-width / 2, height / 2),
  ];
}

List<Offset> rectQuad(Rect rect) => [
  rect.topLeft,
  rect.topRight,
  rect.bottomRight,
  rect.bottomLeft,
];

void main() {
  group('orderQuadCorners', () {
    test('orders a shuffled rectangle into TL, TR, BR, BL', () {
      const rect = Rect.fromLTRB(10, 20, 110, 220);
      final shuffled = [
        rect.bottomRight,
        rect.topLeft,
        rect.bottomLeft,
        rect.topRight,
      ];
      expect(orderQuadCorners(shuffled), [
        rect.topLeft,
        rect.topRight,
        rect.bottomRight,
        rect.bottomLeft,
      ]);
    });
  });

  group('shape metrics', () {
    test('quadArea matches the rectangle it describes', () {
      expect(quadArea(rectQuad(const Rect.fromLTWH(0, 0, 30, 40))), 1200);
    });

    test('quadAspect is width over height', () {
      expect(
        quadAspect(rectQuad(const Rect.fromLTWH(0, 0, 59, 86))),
        closeTo(ScanReticleTokens.cardAspectRatio, 1e-9),
      );
    });

    test('quadRectangularity is 1 for a rectangle, low for a sheared one', () {
      expect(
        quadRectangularity(rectQuad(const Rect.fromLTWH(0, 0, 40, 60))),
        closeTo(1, 1e-9),
      );
      // A parallelogram sheared 45 degrees: same side lengths as a rectangle
      // twice its area, so only this metric catches it.
      final sheared = [
        const Offset(0, 0),
        const Offset(100, 0),
        const Offset(180, 60),
        const Offset(80, 60),
      ];
      expect(quadRectangularity(sheared), lessThan(0.7));
    });

    test('quadTiltDegrees reads the top edge angle', () {
      expect(quadTiltDegrees(rectQuad(const Rect.fromLTWH(0, 0, 40, 60))), 0);
      final tilted = [
        const Offset(0, 0),
        const Offset(40, 40),
        const Offset(0, 80),
        const Offset(-40, 40),
      ];
      expect(quadTiltDegrees(tilted), closeTo(45, 1e-9));
    });

    test('quadContains is true only when every corner is inside', () {
      final outer = rectQuad(const Rect.fromLTRB(0, 0, 100, 100));
      expect(quadContains(outer, rectQuad(const Rect.fromLTRB(10, 10, 90, 90))),
          isTrue);
      expect(
        quadContains(outer, rectQuad(const Rect.fromLTRB(10, 10, 110, 90))),
        isFalse,
      );
    });
  });

  group('evaluateCardQuad', () {
    test('accepts a well-framed card', () {
      final candidate = evaluateCardQuad(
        cardQuad(),
        imageSize: _imageSize,
        searchRoi: _wholeImage,
      );
      expect(candidate, isNotNull);
      expect(candidate!.aspectError, closeTo(1, 1e-9));
      expect(candidate.rectangularity, closeTo(1, 1e-9));
      expect(candidate.score, greaterThan(CardDetectionTuning.minScore));
    });

    test('rejects a quad reaching outside the search region', () {
      CardQuadRejection? reason;
      final candidate = evaluateCardQuad(
        cardQuad(),
        imageSize: _imageSize,
        // A guide box in the middle of the image; the card overflows it.
        searchRoi: const Rect.fromLTRB(0.4, 0.4, 0.6, 0.6),
        onReject: (r) => reason = r,
      );
      expect(candidate, isNull);
      expect(reason, CardQuadRejection.outsideRoi);
    });

    test('rejects a square — the wrong aspect ratio', () {
      CardQuadRejection? reason;
      // Big enough to clear the area gate, so it is the aspect that rejects it.
      expect(
        evaluateCardQuad(
          rectQuad(const Rect.fromLTRB(50, 150, 350, 450)),
          imageSize: _imageSize,
          searchRoi: _wholeImage,
          onReject: (r) => reason = r,
        ),
        isNull,
      );
      expect(reason, CardQuadRejection.aspect);
    });

    test('rejects a landscape card-ratio quad', () {
      expect(
        evaluateCardQuad(
          rectQuad(const Rect.fromLTWH(20, 200, 344, 236)),
          imageSize: _imageSize,
          searchRoi: _wholeImage,
        ),
        isNull,
      );
    });

    test('rejects a blob whose corners are not a rectangle', () {
      CardQuadRejection? reason;
      // Card-ish bounding shape, but one corner pulled far in.
      final blob = [
        const Offset(100, 60),
        const Offset(300, 60),
        const Offset(300, 540),
        const Offset(200, 300),
      ];
      expect(
        evaluateCardQuad(
          blob,
          imageSize: _imageSize,
          searchRoi: _wholeImage,
          onReject: (r) => reason = r,
        ),
        isNull,
      );
      expect(
        reason,
        anyOf(
          CardQuadRejection.rectangularity,
          CardQuadRejection.sideBalance,
          CardQuadRejection.aspect,
        ),
      );
    });

    test('rejects a card rotated too far for corner ordering to be safe', () {
      final centre = const Offset(200, 300);
      final quad = cardQuad(fraction: 0.6);
      // Rotate 40 degrees about the centre.
      const cos = 0.766;
      const sin = 0.643;
      final rotated = orderQuadCorners([
        for (final corner in quad)
          Offset(
            centre.dx +
                (corner.dx - centre.dx) * cos -
                (corner.dy - centre.dy) * sin,
            centre.dy +
                (corner.dx - centre.dx) * sin +
                (corner.dy - centre.dy) * cos,
          ),
      ]);
      final reasons = <CardQuadRejection>[];
      expect(
        evaluateCardQuad(
          rotated,
          imageSize: _imageSize,
          searchRoi: _wholeImage,
          onReject: reasons.add,
        ),
        isNull,
      );
      expect(reasons, isNotEmpty);
    });

    test('rejects a card too small a share of the guide box', () {
      CardQuadRejection? reason;
      expect(
        evaluateCardQuad(
          cardQuad(fraction: 0.25),
          imageSize: _imageSize,
          searchRoi: _wholeImage,
          onReject: (r) => reason = r,
        ),
        isNull,
      );
      expect(reason, CardQuadRejection.area);
    });
  });

  group('selectCardQuad', () {
    test('returns null when nothing is card-shaped', () {
      expect(
        selectCardQuad(
          [rectQuad(const Rect.fromLTRB(100, 200, 300, 400))],
          imageSize: _imageSize,
          searchRoi: _wholeImage,
        ),
        isNull,
      );
    });

    test('prefers the card over a larger, better-filling wrong shape', () {
      // A big background rectangle that fills more of the frame than the card,
      // but isn't card-shaped. Under the old area-dominated score this won.
      final background = rectQuad(const Rect.fromLTRB(5, 5, 395, 400));
      final card = cardQuad(fraction: 0.8);
      final best = selectCardQuad(
        [background, card],
        imageSize: _imageSize,
        searchRoi: _wholeImage,
      );
      expect(best, isNotNull);
      expect(best!.corners, card);
    });

    test('sleeve and card: the inner (card) outline wins', () {
      final sleeve = cardQuad(fraction: 0.92);
      // ~0.85 of the sleeve's area — a perfect-fit sleeve around a card.
      final card = cardQuad(fraction: 0.92 * 0.92);
      final best = selectCardQuad(
        [sleeve, card],
        imageSize: _imageSize,
        searchRoi: _wholeImage,
      );
      expect(best!.corners, card);
    });

    test(
      'the descent stops at the card and does not walk onto its inner border',
      () {
        // Sleeve, card, and the card's own printed inner border — each nested
        // in the last at a ratio above `innerQuadMinAreaRatio`. An unbounded
        // descent walks all the way to the border and shrinks the warp, which
        // hashes the wrong pixels while still looking like a clean detection.
        final sleeve = cardQuad(fraction: 0.95);
        final card = cardQuad(fraction: 0.95 * 0.92);
        final innerBorder = cardQuad(fraction: 0.95 * 0.92 * 0.90);
        final best = selectCardQuad(
          [sleeve, card, innerBorder],
          imageSize: _imageSize,
          searchRoi: _wholeImage,
        );
        expect(best!.corners, card);
      },
    );

    test('the two sides of one dilated edge band count as a single quad', () {
      // A near-duplicate pair must not consume the one permitted descent, or
      // the real sleeve/card step never happens.
      final sleeveOuter = cardQuad(fraction: 0.95);
      final sleeveInner = cardQuad(fraction: 0.95 * 0.99);
      final card = cardQuad(fraction: 0.95 * 0.92);
      final best = selectCardQuad(
        [sleeveOuter, sleeveInner, card],
        imageSize: _imageSize,
        searchRoi: _wholeImage,
      );
      expect(best!.corners, card);
    });

    test('a nested quad far smaller than the card is not descended into', () {
      // The art box is ~0.4 of the card — well below the ratio — so it can
      // never be mistaken for the card's outline.
      final card = cardQuad(fraction: 0.9);
      final artBox = rectQuad(
        Rect.fromLTWH(
          card[0].dx + 20,
          card[0].dy + 40,
          (card[1].dx - card[0].dx) - 40,
          (card[3].dy - card[0].dy) * 0.45,
        ),
      );
      final best = selectCardQuad(
        [card, artBox],
        imageSize: _imageSize,
        searchRoi: _wholeImage,
      );
      expect(best!.corners, card);
    });

    test('between two valid cards, the more centred one wins', () {
      final centred = cardQuad(fraction: 0.7);
      final offCentre = cardQuad(
        fraction: 0.7,
        centre: const Offset(320, 300),
      );
      final best = selectCardQuad(
        [offCentre, centred],
        imageSize: _imageSize,
        searchRoi: _wholeImage,
      );
      expect(best!.corners, centred);
    });
  });
}
