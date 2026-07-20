import 'package:freezed_annotation/freezed_annotation.dart';

part 'ygo_card.freezed.dart';

/// Maps to the `cards` table. SQLite mapping is hand-written here and kept
/// separate from any JSON (YGOPRODeck API) serialization — the two shapes
/// differ and conflating them causes trouble later.
@freezed
abstract class YgoCard with _$YgoCard {
  const YgoCard._();

  const factory YgoCard({
    required String passcode,
    required String name,
    String? type,
    String? frameType,
    String? attribute,
    String? race,
    int? atk,
    int? def,
    int? level,
    String? description,
    String? imageUrl,
    String? archetype,
  }) = _YgoCard;

  factory YgoCard.fromMap(Map<String, Object?> map) => YgoCard(
    passcode: map['passcode'] as String,
    name: map['name'] as String,
    type: map['type'] as String?,
    frameType: map['frame_type'] as String?,
    attribute: map['attribute'] as String?,
    race: map['race'] as String?,
    atk: map['atk'] as int?,
    def: map['def'] as int?,
    level: map['level'] as int?,
    description: map['description'] as String?,
    imageUrl: map['image_url'] as String?,
    archetype: map['archetype'] as String?,
  );

  Map<String, Object?> toMap() => {
    'passcode': passcode,
    'name': name,
    'type': type,
    'frame_type': frameType,
    'attribute': attribute,
    'race': race,
    'atk': atk,
    'def': def,
    'level': level,
    'description': description,
    'image_url': imageUrl,
    'archetype': archetype,
  };
}
