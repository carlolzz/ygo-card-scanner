/// Card condition, in Cardmarket order best -> worst.
///
/// Persisted to SQLite by name (SCREAMING_SNAKE via [toDb]), never by
/// ordinal — enum member order must stay free to be reasoned about without
/// worrying about breaking stored data.
enum CardCondition {
  mint('MT', 'Mint'),
  nearMint('NM', 'Near Mint'),
  excellent('EX', 'Excellent'),
  good('GD', 'Good'),
  lightPlayed('LP', 'Light Played'),
  played('PL', 'Played'),
  poor('PO', 'Poor');

  const CardCondition(this.shortCode, this.label);

  final String shortCode;
  final String label;

  /// Best -> worst. Matches declaration order.
  int get sortOrder => index;

  String toDb() => switch (this) {
    CardCondition.mint => 'MINT',
    CardCondition.nearMint => 'NEAR_MINT',
    CardCondition.excellent => 'EXCELLENT',
    CardCondition.good => 'GOOD',
    CardCondition.lightPlayed => 'LIGHT_PLAYED',
    CardCondition.played => 'PLAYED',
    CardCondition.poor => 'POOR',
  };

  static CardCondition fromDb(String value) => switch (value) {
    'MINT' => CardCondition.mint,
    'NEAR_MINT' => CardCondition.nearMint,
    'EXCELLENT' => CardCondition.excellent,
    'GOOD' => CardCondition.good,
    'LIGHT_PLAYED' => CardCondition.lightPlayed,
    'PLAYED' => CardCondition.played,
    'POOR' => CardCondition.poor,
    _ => throw ArgumentError('Unknown CardCondition db value: $value'),
  };
}
