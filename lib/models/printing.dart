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

  /// "SET-CODE · Set Name · Rarity", omitting whatever this row doesn't carry.
  /// The single place a printing is formatted for display, shared by the scan
  /// review gate's set picker and the collection edit sheet. Empty when the row
  /// carries none of the three (callers substitute their own "no set" label).
  String get displayLabel =>
      [setCode, setName, rarity].whereType<String>().join(' · ');

  Map<String, Object?> toMap() => {
    'passcode': passcode,
    'set_code': setCode,
    'set_name': setName,
    'rarity': rarity,
  };
}

/// Narrows [printings] to those matching a free-typed [query], for the set
/// search box shared by the scan review gate, the manual add wizard and the
/// collection edit sheet.
///
/// Every whitespace-separated term must appear somewhere in the printing's
/// [Printing.displayLabel], case-insensitively and in any order — so "raiders
/// super" finds "MRD-EN094 · Metal Raiders · Super Rare", and a set code typed
/// with or without its language block still matches. An empty query keeps the
/// list intact rather than emptying it: the box starts as a plain list the user
/// can scroll, and typing only ever narrows it.
List<Printing> filterPrintings(List<Printing> printings, String query) {
  final terms = query.toLowerCase().split(RegExp(r'\s+'))
    ..removeWhere((term) => term.isEmpty);
  if (terms.isEmpty) return printings;
  return [
    for (final printing in printings)
      if (terms.every(printing.displayLabel.toLowerCase().contains)) printing,
  ];
}
