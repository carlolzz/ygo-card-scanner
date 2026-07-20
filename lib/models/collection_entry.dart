import 'package:freezed_annotation/freezed_annotation.dart';

import 'card_condition.dart';
import 'card_edition.dart';

part 'collection_entry.freezed.dart';

/// Maps to the `collection_entries` table. `id` is null until inserted.
/// Timestamps are epoch milliseconds.
@freezed
abstract class CollectionEntry with _$CollectionEntry {
  const CollectionEntry._();

  const factory CollectionEntry({
    int? id,
    required String passcode,
    int? printingId,
    required CardCondition condition,
    @Default(CardEdition.unlimited) CardEdition edition,
    @Default('EN') String language,
    @Default(1) int quantity,
    String? notes,
    required int createdAt,
    required int updatedAt,
  }) = _CollectionEntry;

  factory CollectionEntry.fromMap(Map<String, Object?> map) =>
      CollectionEntry(
        id: map['id'] as int?,
        passcode: map['passcode'] as String,
        printingId: map['printing_id'] as int?,
        condition: CardCondition.fromDb(map['condition'] as String),
        edition: CardEdition.fromDb(map['edition'] as String),
        language: map['language'] as String,
        quantity: map['quantity'] as int,
        notes: map['notes'] as String?,
        createdAt: map['created_at'] as int,
        updatedAt: map['updated_at'] as int,
      );

  Map<String, Object?> toMap() => {
    'passcode': passcode,
    'printing_id': printingId,
    'condition': condition.toDb(),
    'edition': edition.toDb(),
    'language': language,
    'quantity': quantity,
    'notes': notes,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };
}
