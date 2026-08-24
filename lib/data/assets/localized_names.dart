import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../db/dao/card_name_dao.dart';

/// The asset version this build expects, mirroring `OUTPUT_VERSION` in
/// `tools/build_localized_names.py`.
///
/// Held on the Dart side as well as in the file so [CardRepository
/// .ensureLocalizedNames] can decide whether an import is needed *without*
/// reading and decoding the asset first — which would otherwise happen on every
/// single search. [parseLocalizedNames] enforces that the two agree, so a
/// regenerated asset with a bumped version cannot be shipped against a stale
/// expectation: the mismatch is a loud startup-style failure rather than a
/// silent skip, exactly like `HashIndex`'s ROI header guard.
const int kLocalizedNamesVersion = 1;

/// A parsed `assets/card_names_<lang>.json`, as written by
/// `tools/build_localized_names.py`.
///
/// Names for a language the card sync cannot supply. `cardinfo.php` is fetched
/// with no `language` parameter (and adding one would cost another ~18 MB per
/// sync for ~435 KB of data), so the localized names ship in the APK instead —
/// the same arrangement as `assets/card_hashes.json`.
class LocalizedNames {
  const LocalizedNames({
    required this.version,
    required this.language,
    required this.names,
  });

  /// The asset's own version, mirrored into `meta` once loaded so a rebuilt
  /// asset is re-imported and an unchanged one is not.
  final int version;

  /// This app's two-letter code (`IT`), which is what lands in
  /// `card_names.language`.
  final String language;

  final List<CardName> names;
}

/// The asset path for [language] (the app's two-letter code).
///
/// Must match `output_path` in `tools/build_localized_names.py` and the entries
/// registered under `flutter: assets:` in `pubspec.yaml` — the tool names its
/// file after YGOPRODeck's lower-case code, which is this one lower-cased.
String localizedNamesAssetPath(String language) =>
    'assets/card_names_${language.toLowerCase()}.json';

/// Parses the asset's JSON. Pure, so the validation is host-testable without a
/// bundle.
///
/// Throws [FormatException] rather than degrading to an empty list: a malformed
/// asset is a broken build, not a runtime condition, and a silent empty result
/// would present as "Italian search finds nothing" with everything else green.
LocalizedNames parseLocalizedNames(String source) {
  final Object? decoded = jsonDecode(source);
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('card_names asset is not a JSON object');
  }
  final version = decoded['version'];
  final language = decoded['language'];
  final names = decoded['names'];
  if (version is! int) {
    throw const FormatException('card_names asset has no integer version');
  }
  if (version != kLocalizedNamesVersion) {
    throw FormatException(
      'card_names asset is version $version but this build expects '
      '$kLocalizedNamesVersion. Regenerate it with '
      '`py -3 tools/build_localized_names.py`.',
    );
  }
  if (language is! String || language.isEmpty) {
    throw const FormatException('card_names asset has no language');
  }
  if (names is! Map<String, Object?>) {
    throw const FormatException('card_names asset has no names map');
  }
  return LocalizedNames(
    version: version,
    language: language,
    names: [
      for (final entry in names.entries)
        if (entry.value is String)
          CardName(
            passcode: entry.key,
            language: language,
            name: entry.value! as String,
          ),
    ],
  );
}

/// Reads and parses the bundled asset for [language].
///
/// Decoding runs in a [compute] isolate: ~11.6k entries is small next to the
/// hash index, but this is loaded while a search screen is live and the user is
/// typing, which is the worst possible moment to block the UI isolate.
Future<LocalizedNames> loadLocalizedNamesAsset(String language) async {
  final source = await rootBundle.loadString(localizedNamesAssetPath(language));
  return compute(parseLocalizedNames, source);
}
