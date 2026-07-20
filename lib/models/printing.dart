import 'package:freezed_annotation/freezed_annotation.dart';

part 'printing.freezed.dart';

/// Maps to the `printings` table. `id` is null until the row has been
/// inserted (AUTOINCREMENT primary key).
@freezed
abstract class Printing with _$Printing {
  const Printing._();

  const factory Printing({
    int? id,
    required String passcode,
    String? setCode,
    String? setName,
    String? rarity,
  }) = _Printing;

  factory Printing.fromMap(Map<String, Object?> map) => Printing(
    id: map['id'] as int?,
    passcode: map['passcode'] as String,
    setCode: map['set_code'] as String?,
    setName: map['set_name'] as String?,
    rarity: map['rarity'] as String?,
  );

  Map<String, Object?> toMap() => {
    'passcode': passcode,
    'set_code': setCode,
    'set_name': setName,
    'rarity': rarity,
  };
}
