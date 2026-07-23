import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/data/api/card_image_downloader.dart';

void main() {
  // The digit check runs before any filesystem/network access, so these
  // assertions need no path_provider/Dio mocking.
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
