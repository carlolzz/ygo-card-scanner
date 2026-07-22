import 'card_condition.dart';
import 'card_edition.dart';
import 'collection_entry.dart';
import 'printing.dart';
import 'ygo_card.dart';

/// Read-only view model joining a [CollectionEntry] with its [YgoCard] and,
/// when one was chosen, the [Printing] it was logged under — for list
/// rendering. Built from `CollectionDao.getAll()`'s joined query.
///
/// Deliberately not freezed: it's a DAO-internal join projection, never
/// mutated or diffed, so `copyWith`/equality codegen buys nothing here.
class CollectionEntryWithCard {
  const CollectionEntryWithCard({
    required this.entry,
    required this.card,
    this.printing,
  });

  final CollectionEntry entry;
  final YgoCard card;
  final Printing? printing;

  /// Expects a row from a query that selects `collection_entries.*`,
  /// `cards` columns aliased with a `card_` prefix, and `printings`
  /// columns aliased with a `printing_` prefix (see `CollectionDao.getAll`),
  /// to avoid column-name collisions between the tables in the flat row map.
  factory CollectionEntryWithCard.fromRow(Map<String, Object?> row) {
    final entry = CollectionEntry(
      id: row['id'] as int?,
      passcode: row['passcode'] as String,
      printingId: row['printing_id'] as int?,
      condition: CardCondition.fromDb(row['condition'] as String),
      edition: CardEdition.fromDb(row['edition'] as String),
      language: row['language'] as String,
      quantity: row['quantity'] as int,
      notes: row['notes'] as String?,
      createdAt: row['created_at'] as int,
      updatedAt: row['updated_at'] as int,
    );
    final card = YgoCard(
      passcode: row['passcode'] as String,
      name: row['card_name'] as String,
      type: row['card_type'] as String?,
      frameType: row['card_frame_type'] as String?,
      attribute: row['card_attribute'] as String?,
      race: row['card_race'] as String?,
      atk: row['card_atk'] as int?,
      def: row['card_def'] as int?,
      level: row['card_level'] as int?,
      description: row['card_description'] as String?,
      imageUrl: row['card_image_url'] as String?,
      localImagePath: row['card_local_image_path'] as String?,
      archetype: row['card_archetype'] as String?,
    );
    final printing = entry.printingId == null
        ? null
        : Printing(
            id: entry.printingId,
            passcode: entry.passcode,
            setCode: row['printing_set_code'] as String?,
            setName: row['printing_set_name'] as String?,
            rarity: row['printing_rarity'] as String?,
          );
    return CollectionEntryWithCard(entry: entry, card: card, printing: printing);
  }
}
