import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/theme/tokens.dart';
import '../../data/repositories/card_repository.dart';
import '../../models/ygo_card.dart';
import 'card_thumbnail.dart';

part 'card_art_thumbnail.g.dart';

/// Ensures a card's artwork is downloaded (once, cached under `card_images/`)
/// and returns its local path, or null if it couldn't be fetched. Lets a
/// thumbnail lazily pull the art of a card the user doesn't own yet — the
/// artwork-match candidates and the automatic top match — a handful at a time.
/// API-compliant: reuses [CardRepository.ensureImageDownloaded], which never
/// re-downloads and never hotlinks.
@riverpod
Future<String?> cardArt(Ref ref, String passcode) async {
  final repository = await ref.watch(cardRepositoryProvider.future);
  await repository.ensureImageDownloaded(passcode);
  final card = await repository.getByPasscode(passcode);
  final path = card?.localImagePath;
  if (path != null && await File(path).exists()) return path;
  return null;
}

/// A [CardThumbnail] that lazily fetches the art for cards whose image hasn't
/// been downloaded yet (scan candidates, the automatic match). Owned cards
/// already carry a `localImagePath`, so they render immediately with no fetch.
class CardArtThumbnail extends ConsumerWidget {
  const CardArtThumbnail({
    super.key,
    required this.card,
    this.size = CardThumbnailSizes.list,
  });

  final YgoCard card;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Already on disk (owned card) — render straight away, no download.
    if (card.localImagePath != null) {
      return CardThumbnail(localImagePath: card.localImagePath, size: size);
    }
    // Not yet downloaded — pull it once. `.value` is null while it resolves (or
    // if the fetch fails), so the thumbnail shows its placeholder until ready.
    final art = ref.watch(cardArtProvider(card.passcode));
    return CardThumbnail(localImagePath: art.value, size: size);
  }
}
