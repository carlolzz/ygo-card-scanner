import '../core/constants.dart';

/// Card edition. Persisted to SQLite by name, never by ordinal.
enum CardEdition {
  first,
  unlimited,
  limited;

  /// The edition's name in the current interface language. A getter rather
  /// than a constructor field so it follows `AppStrings.select`.
  String get label => switch (this) {
    CardEdition.first => AppStrings.editionFirst,
    CardEdition.unlimited => AppStrings.editionUnlimited,
    CardEdition.limited => AppStrings.editionLimited,
  };

  String toDb() => switch (this) {
    CardEdition.first => 'FIRST',
    CardEdition.unlimited => 'UNLIMITED',
    CardEdition.limited => 'LIMITED',
  };

  static CardEdition fromDb(String value) => switch (value) {
    'FIRST' => CardEdition.first,
    'UNLIMITED' => CardEdition.unlimited,
    'LIMITED' => CardEdition.limited,
    _ => throw ArgumentError('Unknown CardEdition db value: $value'),
  };
}
