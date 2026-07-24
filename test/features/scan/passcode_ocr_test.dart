import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/features/scan/passcode_ocr.dart';

/// Places a span at a fixed spot; position only matters for the ROI tests.
RecognizedSpan span(String text, {Rect? box}) =>
    RecognizedSpan(text, box ?? const Rect.fromLTWH(0, 0, 10, 10));

void main() {
  group('extractPasscode', () {
    test('returns an exact 8-digit run', () {
      expect(extractPasscode([span('46986414')]), '46986414');
    });

    test('strips separators within a line before counting digits', () {
      expect(extractPasscode([span('4698 6414')]), '46986414');
    });

    test('rejects fewer than 8 digits (no padding)', () {
      expect(extractPasscode([span('4698641')]), isNull);
    });

    test('rejects more than 8 digits (no truncation)', () {
      expect(extractPasscode([span('469864141')]), isNull);
    });

    test('ignores non-digit noise entirely', () {
      expect(extractPasscode([span('Dark Magician')]), isNull);
      expect(extractPasscode([span('ATK/2500')]), isNull);
    });

    test('returns the value when multiple spans agree', () {
      expect(
        extractPasscode([span('46986414'), span('46986414')]),
        '46986414',
      );
    });

    test('returns null when two spans disagree (ambiguous frame)', () {
      expect(
        extractPasscode([span('46986414'), span('89631139')]),
        isNull,
      );
    });

    test('ignores adjacent text on the same line (the "1st Edition" case)', () {
      // The passcode often shares an OCR line with neighbouring card text; the
      // stray "1" of "1st" must not be counted as a ninth digit.
      expect(extractPasscode([span('46986414 1st Edition')]), '46986414');
      expect(extractPasscode([span('1st Edition 46986414')]), '46986414');
    });

    test('returns null when one line holds two different 8-digit runs', () {
      expect(extractPasscode([span('46986414 89631139')]), isNull);
    });

    test('accepts the same 8-digit run repeated on a line', () {
      expect(extractPasscode([span('46986414 46986414')]), '46986414');
    });

    group('with a bottom-left ROI', () {
      const frame = Size(100, 100);
      // Bottom-left 60% wide, bottom 50% tall.
      const roi = Rect.fromLTRB(0, 0.5, 0.6, 1);

      test('keeps a span whose centre falls inside the ROI', () {
        final inside = span('46986414', box: const Rect.fromLTWH(5, 85, 10, 10));
        expect(
          extractPasscode([inside], frameSize: frame, roi: roi),
          '46986414',
        );
      });

      test('drops a span whose centre falls outside the ROI', () {
        final outside =
            span('46986414', box: const Rect.fromLTWH(85, 5, 10, 10));
        expect(
          extractPasscode([outside], frameSize: frame, roi: roi),
          isNull,
        );
      });
    });
  });
}
