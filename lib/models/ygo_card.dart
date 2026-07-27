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
    String? localImagePath,
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
    localImagePath: map['local_image_path'] as String?,
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
    'local_image_path': localImagePath,
    'archetype': archetype,
  };

  /// `type` is YGOPRODeck's own field — "Normal Monster" for true vanillas
  /// and "Pendulum Normal Monster" for their pendulum counterpart, both of
  /// which carry flavour text rather than an effect.
  bool get isNormalMonster => type?.contains('Normal Monster') ?? false;

  /// Whether this is a Spell card. Its `race` is the spell's kind (Normal /
  /// Continuous / Quick-Play / Field / Equip / Ritual), which players call the
  /// Spell Type — see [isSpellOrTrap].
  bool get isSpell => frameType == 'spell';

  /// Whether this is a Trap card. Its `race` is the trap's kind (Normal /
  /// Continuous / Counter), i.e. the Trap Type.
  bool get isTrap => frameType == 'trap';

  /// Whether this is a Spell or Trap card. For these, YGOPRODeck's `race` field
  /// holds the card's kind rather than a monster type, and `attribute` is just
  /// "SPELL"/"TRAP" — so the collection detail screen labels [race] as the
  /// Spell/Trap Type and hides the redundant `attribute` row.
  bool get isSpellOrTrap => isSpell || isTrap;
}
