/// Card edition. Persisted to SQLite by name, never by ordinal.
enum CardEdition {
  first('1st Edition'),
  unlimited('Unlimited'),
  limited('Limited Edition');

  const CardEdition(this.label);

  final String label;

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
