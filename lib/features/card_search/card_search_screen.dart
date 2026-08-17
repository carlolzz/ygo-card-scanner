import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/routes.dart';
import '../../core/theme/tokens.dart';
import '../../shared/widgets/card_art_thumbnail.dart';
import 'card_search_providers.dart';

/// Search the whole card database and open a card to read it.
///
/// Deliberately separate from the add-card wizard's search step, which looks
/// almost identical and does something else: that one picks a card to *log*
/// and moves straight into a set/condition flow. This one goes to a read-only
/// card page, is reachable from the home menu, and shows artwork, because
/// recognising the card you meant is most of the job when you are browsing
/// rather than logging something already in your hand.
class CardSearchScreen extends ConsumerWidget {
  const CardSearchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(cardSearchQueryControllerProvider);
    final resultsAsync = ref.watch(cardSearchResultsProvider);
    final palette = AppPalette.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.cardSearchTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: TextField(
              autofocus: true,
              style: TextStyle(color: palette.onSurface),
              decoration: InputDecoration(
                hintText: AppStrings.cardSearchHint,
                hintStyle: TextStyle(color: palette.onSurfaceMuted),
                prefixIcon: Icon(Icons.search, color: palette.onSurfaceMuted),
                filled: true,
                fillColor: palette.surfaceRaised,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (value) => ref
                  .read(cardSearchQueryControllerProvider.notifier)
                  .setQuery(value),
            ),
          ),
          Expanded(
            child: resultsAsync.when(
              data: (results) {
                if (results.isEmpty) {
                  // An empty field is not an empty result — say what the screen
                  // is for rather than reporting that nothing matched "".
                  return _Message(
                    query.isEmpty
                        ? AppStrings.cardSearchPrompt
                        : AppStrings.cardSearchEmptyMessage,
                  );
                }
                return ListView.builder(
                  itemCount: results.length,
                  itemBuilder: (context, index) {
                    final card = results[index];
                    return ListTile(
                      // The art thumbnail, not the plain one: a card the user
                      // does not own has never been through `addOrIncrement`,
                      // so its picture has never been downloaded.
                      leading: CardArtThumbnail(
                        card: card,
                        size: CardThumbnailSizes.list,
                        aspectRatio: ScanReticleTokens.cardAspectRatio,
                        fit: BoxFit.contain,
                      ),
                      title: Text(
                        card.name,
                        style: TextStyle(color: palette.onSurface),
                      ),
                      subtitle: card.type == null
                          ? null
                          : Text(
                              card.type!,
                              style: TextStyle(color: palette.onSurfaceMuted),
                            ),
                      onTap: () =>
                          context.push(AppRoutes.cardDetail, extra: card),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => _Message('$error'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: AppPalette.of(context).onSurfaceMuted),
      ),
    ),
  );
}
