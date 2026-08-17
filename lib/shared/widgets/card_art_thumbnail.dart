import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/theme/tokens.dart';
import '../../data/repositories/card_repository.dart';
import '../../models/ygo_card.dart';
import 'card_thumbnail.dart';

part 'card_art_thumbnail.g.dart';

/// Ensures a card's artwork is downloaded (once, cached under `card_images/`)
/// and returns its local path, or null if it couldn't be fetched. Lets a
/// thumbnail lazily pull the art of any card whose image isn't on disk yet —
/// the artwork-match candidates, and every row of a freshly imported
/// collection. API-compliant: reuses [CardRepository.ensureImageDownloaded],
/// which never re-downloads and never hotlinks, and whose downloader caps how
/// many fetches run at once.
@riverpod
Future<String?> cardArt(Ref ref, String passcode) async {
  final repository = await ref.watch(cardRepositoryProvider.future);
  await repository.ensureImageDownloaded(passcode);
  final card = await repository.getByPasscode(passcode);
  final path = card?.localImagePath;
  if (path != null && await File(path).exists()) {
    // Hits are cached for the app's lifetime; **misses are not**. A grid
    // rebuilds a cell every time it scrolls back into view, and re-answering
    // costs two sqflite round trips plus a `File.exists` per cell — 30 cells a
    // screenful — to return the same short string. But caching a *failure*
    // would mean one offline moment permanently blanked a card until the app
    // was relaunched, so a miss stays retryable.
    ref.keepAlive();
    return path;
  }
  return null;
}

/// A [CardThumbnail] that lazily fetches the art for cards whose image hasn't
/// been downloaded yet. Cards that already carry a `localImagePath` render
/// immediately and **never touch the provider at all**, which is what makes
/// this safe to use on every collection surface.
///
/// It is used on all of them because a CSV import goes straight to
/// `CollectionDao.applyImport` and so never fires the art download that
/// `CollectionRepository.addOrIncrement` does — imported rows arrive with a
/// NULL `cards.local_image_path` and the plain [CardThumbnail] would show the
/// placeholder for them forever.
///
/// Deliberately does **not** invalidate `collectionEntriesProvider` when a
/// download lands: the tile renders the path this provider returns, so it heals
/// itself, while invalidating the list would re-run `getAll` once per image
/// fetched. The `CollectionEntryWithCard` in hand simply stays stale — that is
/// fine, and it is why nobody should "fix" it later.
class CardArtThumbnail extends ConsumerWidget {
  const CardArtThumbnail({
    super.key,
    required this.card,
    this.size = CardThumbnailSizes.list,
    this.aspectRatio,
    this.fit = BoxFit.cover,
  });

  final YgoCard card;

  /// As [CardThumbnail.size], nullable included: null means "fill the space the
  /// parent gives me", which is what a collection grid cell needs.
  final double? size;

  final double? aspectRatio;
  final BoxFit fit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Already on disk (an owned card that has been seen before) — render
    // straight away, no provider, no download.
    if (card.localImagePath != null) {
      return CardThumbnail(
        localImagePath: card.localImagePath,
        size: size,
        aspectRatio: aspectRatio,
        fit: fit,
      );
    }
    // Not yet downloaded — pull it once. `.value` is null while it resolves (or
    // if the fetch fails), so the thumbnail shows its placeholder until ready.
    final art = ref.watch(cardArtProvider(card.passcode));
    return CardThumbnail(
      localImagePath: art.value,
      size: size,
      aspectRatio: aspectRatio,
      fit: fit,
    );
  }
}
