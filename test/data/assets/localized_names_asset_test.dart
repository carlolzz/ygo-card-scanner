import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/data/assets/localized_names.dart';
import 'package:ygo_scanner/models/card_language.dart';

/// Guards the *committed* `assets/card_names_it.json` against the build that
/// ships with it, for the reason `hash_index_asset_test.dart` gives: the
/// failure mode is a **silent green**. Every other test injects its own
/// `localizedNamesLoader`, so nothing else opens the real file — bumping
/// [kLocalizedNamesVersion] without re-running the tool, or shipping a file
/// under the wrong name, would leave `flutter test` entirely green and break
/// only Italian search on the device.
///
/// Read with `dart:io` rather than `rootBundle` deliberately: the point is to
/// check the file in the repository, not a bundled copy of it.
void main() {
  test('the committed Italian asset matches this build', () {
    final file = File(localizedNamesAssetPath('IT'));
    expect(
      file.existsSync(),
      isTrue,
      reason: 'run: py -3 tools/build_localized_names.py',
    );

    // Through the real parser, which enforces the version and the shape.
    final parsed = parseLocalizedNames(file.readAsStringSync());

    expect(parsed.language, 'IT');
    expect(kSearchLanguages, contains(parsed.language));
    // ~11.6k of YGOPRODeck's ~14.6k cards have an Italian translation.
    expect(parsed.names.length, greaterThan(10000));
    expect(
      parsed.names.firstWhere((n) => n.passcode == '89631139').name,
      'Drago Bianco Occhi Blu',
    );
  });

  test('every shipped search language past English has an asset', () {
    // Adding a code to `kSearchLanguages` without building its file makes the
    // search throw the first time someone picks it.
    for (final language in kSearchLanguages) {
      if (language == kDefaultSearchLanguage) continue;
      expect(
        File(localizedNamesAssetPath(language)).existsSync(),
        isTrue,
        reason: '$language is offered but ships no asset',
      );
    }
  });
}
