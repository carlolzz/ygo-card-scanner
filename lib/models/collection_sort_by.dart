/// How the collection list is ordered. [cardType] is the odd one out: it is not
/// a column but a three-way grouping — monsters, then Spells, then Traps — see
/// `CollectionDao.getAll`.
///
/// Persisted to SQLite by name (in the `meta` table, not a column), never by
/// ordinal — same rule as every other enum here. It lives in `models/` rather
/// than beside `CollectionFilter` in the DAO precisely because it is persisted:
/// `AppSettings` carries it, and a model must not depend on the data layer.
enum CollectionSortBy {
  name,
  dateAdded,
  quantity,
  cardType;

  String toDb() => switch (this) {
    CollectionSortBy.name => 'NAME',
    CollectionSortBy.dateAdded => 'DATE_ADDED',
    CollectionSortBy.quantity => 'QUANTITY',
    CollectionSortBy.cardType => 'CARD_TYPE',
  };

  static CollectionSortBy fromDb(String value) => switch (value) {
    'NAME' => CollectionSortBy.name,
    'DATE_ADDED' => CollectionSortBy.dateAdded,
    'QUANTITY' => CollectionSortBy.quantity,
    'CARD_TYPE' => CollectionSortBy.cardType,
    _ => throw ArgumentError('Unknown CollectionSortBy db value: $value'),
  };
}
