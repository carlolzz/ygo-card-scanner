import 'package:dio/dio.dart';

import '../../models/printing.dart';
import '../../models/ygo_card.dart';

/// A card plus all of its printings, as parsed from a single YGOPRODeck
/// `cardinfo.php` entry.
class YgoProdeckCard {
  const YgoProdeckCard({required this.card, required this.printings});

  final YgoCard card;
  final List<Printing> printings;
}

/// Thin wrapper over the YGOPRODeck REST API. Card JSON parsing (as opposed
/// to the SQLite mapping on [YgoCard]/[Printing]) lives here, since the two
/// shapes differ.
class YgoProdeckClient {
  YgoProdeckClient({Dio? dio})
    : _dio =
          dio ??
          Dio(BaseOptions(baseUrl: 'https://db.ygoprodeck.com/api/v7'));

  final Dio _dio;

  /// Fetches the full card database in one request (~13k entries) and
  /// flattens each entry's nested `card_sets` into printing rows.
  ///
  /// Fetch once, not per-card — the API is rate-limited to roughly 20
  /// requests/second.
  Future<List<YgoProdeckCard>> fetchAllCards() async {
    final response = await _dio.get<Map<String, Object?>>('/cardinfo.php');
    final data = response.data?['data'] as List<Object?>? ?? const [];
    return data
        .map((entry) => _parseEntry(entry! as Map<String, Object?>))
        .toList();
  }

  YgoProdeckCard _parseEntry(Map<String, Object?> json) {
    final passcode = json['id'].toString();

    final card = YgoCard(
      passcode: passcode,
      name: json['name']! as String,
      type: json['type'] as String?,
      frameType: json['frameType'] as String?,
      attribute: json['attribute'] as String?,
      race: json['race'] as String?,
      atk: (json['atk'] as num?)?.toInt(),
      def: (json['def'] as num?)?.toInt(),
      level: (json['level'] as num?)?.toInt(),
      description: json['desc'] as String?,
      imageUrl: _firstImageUrl(json['card_images']),
      archetype: json['archetype'] as String?,
    );

    final sets = json['card_sets'] as List<Object?>? ?? const [];
    final printings = sets
        .map((s) => s! as Map<String, Object?>)
        .map(
          (s) => Printing(
            passcode: passcode,
            setCode: s['set_code'] as String?,
            setName: s['set_name'] as String?,
            rarity: s['set_rarity'] as String?,
          ),
        )
        .toList();

    return YgoProdeckCard(card: card, printings: printings);
  }

  String? _firstImageUrl(Object? images) {
    if (images is! List || images.isEmpty) return null;
    final first = images.first;
    if (first is! Map<String, Object?>) return null;
    return first['image_url'] as String?;
  }
}
