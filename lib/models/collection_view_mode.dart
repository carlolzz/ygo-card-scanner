/// How densely the collection list renders. Persisted to SQLite by name (in the
/// `meta` table, not a column), never by ordinal — same rule as every other enum
/// here.
///
/// The two minified modes are grids rather than shorter rows: the point of
/// minifying is cards per screen, and a row can only ever hold one card however
/// little it says about it. [standard] keeps the full row, with the quantity and
/// the add/remove/delete controls — those live only there, so the grids are for
/// browsing and the list is for editing.
enum CollectionViewMode {
  /// The full row: grade chip, artwork, name, set, rarity, quantity, controls.
  standard('Standard'),

  /// A grid of artwork with the card name captioned under each.
  minifyStandard('Artwork + name'),

  /// A denser grid of artwork alone.
  minifyFull('Artwork only');

  const CollectionViewMode(this.label);

  final String label;

  bool get isGrid => this != CollectionViewMode.standard;

  /// Whether the grid captions each cell with the card's name.
  bool get showsName => this == CollectionViewMode.minifyStandard;

  String toDb() => switch (this) {
    CollectionViewMode.standard => 'STANDARD',
    CollectionViewMode.minifyStandard => 'MINIFY_STANDARD',
    CollectionViewMode.minifyFull => 'MINIFY_FULL',
  };

  static CollectionViewMode fromDb(String value) => switch (value) {
    'STANDARD' => CollectionViewMode.standard,
    'MINIFY_STANDARD' => CollectionViewMode.minifyStandard,
    'MINIFY_FULL' => CollectionViewMode.minifyFull,
    _ => throw ArgumentError('Unknown CollectionViewMode db value: $value'),
  };
}
