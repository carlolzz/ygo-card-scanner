import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/data/api/card_image_downloader.dart';

void main() {
  // The gate exists because a minified collection grid puts 15-30 cells on
  // screen at once, and after a CSV import every one of them has to fetch its
  // artwork — thirty simultaneous requests at YGOPRODeck, against exactly the
  // conservative-access posture this whole download path exists to honour.
  group('ConcurrencyLimiter', () {
    test('never runs more than the cap at once', () async {
      final limiter = ConcurrencyLimiter(2);
      final gates = List.generate(5, (_) => Completer<void>());
      var started = 0;

      for (final gate in gates) {
        unawaited(
          limiter.run(() async {
            started++;
            await gate.future;
          }),
        );
      }
      await Future<void>.delayed(Duration.zero);

      expect(started, 2);
      for (final gate in gates) {
        gate.complete();
      }
    });

    test('finishing one lets exactly one more start', () async {
      final limiter = ConcurrencyLimiter(2);
      final gates = List.generate(5, (_) => Completer<void>());
      var started = 0;

      for (final gate in gates) {
        unawaited(
          limiter.run(() async {
            started++;
            await gate.future;
          }),
        );
      }
      await Future<void>.delayed(Duration.zero);
      expect(started, 2);

      gates[0].complete();
      await Future<void>.delayed(Duration.zero);
      expect(started, 3);

      gates[1].complete();
      await Future<void>.delayed(Duration.zero);
      expect(started, 4);

      for (final gate in gates) {
        if (!gate.isCompleted) gate.complete();
      }
    });

    // The one that matters. A body that throws must hand its slot on, or a few
    // failed downloads (offline, a 404) deadlock every later one for the life
    // of the app — and `ensureImageDownloaded` swallows exceptions, so nothing
    // would ever say why the artwork stopped appearing.
    test('a throwing body releases its slot', () async {
      final limiter = ConcurrencyLimiter(1);
      var ran = false;

      await expectLater(
        limiter.run(() async => throw StateError('download failed')),
        throwsStateError,
      );
      await limiter.run(() async => ran = true);

      expect(ran, isTrue);
    });

    test('runs queued work in submission order', () async {
      final limiter = ConcurrencyLimiter(1);
      final order = <int>[];
      await Future.wait([
        for (var i = 0; i < 4; i++) limiter.run(() async => order.add(i)),
      ]);

      expect(order, [0, 1, 2, 3]);
    });

    test("returns each body's value", () async {
      final limiter = ConcurrencyLimiter(2);
      final values = await Future.wait([
        for (var i = 0; i < 4; i++) limiter.run(() async => i * 10),
      ]);

      expect(values, [0, 10, 20, 30]);
    });
  });

  // The digit check runs before any filesystem/network access — and before the
  // concurrency gate, so a malformed passcode does not wait in a queue to say
  // so. These assertions need no path_provider/Dio mocking.
  group('CardImageDownloader.download passcode validation', () {
    final downloader = CardImageDownloader();

    for (final bad in <String>[
      '',
      'abc',
      '123a',
      '../evil',
      '12/34',
      '89631139.jpg',
    ]) {
      test('rejects non-numeric passcode "$bad"', () {
        expect(
          downloader.download(bad, 'https://example.com/art.jpg'),
          throwsArgumentError,
        );
      });
    }
  });
}
