import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ygo_scanner/data/assets/localized_names.dart';

void main() {
  String assetJson({
    int version = kLocalizedNamesVersion,
    String language = 'IT',
    Map<String, Object?> names = const {'89631139': 'Drago Bianco Occhi Blu'},
  }) => jsonEncode({
    'version': version,
    'language': language,
    'generated_at': '2026-08-24T13:18:59Z',
    'count': names.length,
    'names': names,
  });

  test('parses passcode, language and name', () {
    final parsed = parseLocalizedNames(assetJson());

    expect(parsed.version, kLocalizedNamesVersion);
    expect(parsed.language, 'IT');
    expect(parsed.names.single.passcode, '89631139');
    expect(parsed.names.single.language, 'IT');
    expect(parsed.names.single.name, 'Drago Bianco Occhi Blu');
  });

  test('rejects an asset built by a different version of the tool', () {
    // The build constant is what `ensureLocalizedNames` compares against, so it
    // has to be able to trust that the file agrees. A silent mismatch would
    // mean the import is skipped forever and Italian search finds nothing,
    // with every other signal green.
    expect(
      () => parseLocalizedNames(assetJson(version: kLocalizedNamesVersion + 1)),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects a file that is not the expected shape', () {
    expect(() => parseLocalizedNames('[]'), throwsA(isA<FormatException>()));
    expect(
      () => parseLocalizedNames('{"version": 1, "language": "IT"}'),
      throwsA(isA<FormatException>()),
    );
  });

  test('skips entries whose value is not a string', () {
    final parsed = parseLocalizedNames(
      assetJson(names: const {'1': 'Uno', '2': 42, '3': null}),
    );

    expect(parsed.names.map((n) => n.passcode), ['1']);
  });

  test('the asset path matches what pubspec registers and the tool writes', () {
    expect(localizedNamesAssetPath('IT'), 'assets/card_names_it.json');
  });
}
