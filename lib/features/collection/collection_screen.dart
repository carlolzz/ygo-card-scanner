import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/routes.dart';
import '../../core/theme/tokens.dart';
import '../../data/repositories/collection_repository.dart';
import '../../models/collection_entry_with_card.dart';
import 'collection_delete_confirm.dart';
import 'collection_filter_bar.dart';
import 'collection_list_tile.dart';
import 'collection_providers.dart';

class CollectionScreen extends ConsumerWidget {
  const CollectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(collectionEntriesProvider);
    final filter = ref.watch(collectionFilterControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.homeTileMyCollection),
        actions: [
          IconButton(
            tooltip: AppStrings.collectionSortDirectionTooltip,
            icon: Icon(
              filter.sortDescending
                  ? Icons.arrow_downward
                  : Icons.arrow_upward,
            ),
            onPressed: () => ref
                .read(collectionFilterControllerProvider.notifier)
                .toggleSortDirection(),
          ),
        ],
      ),
      body: Column(
        children: [
          const CollectionFilterBar(),
          Expanded(
            child: entriesAsync.when(
              data: (entries) => _CollectionList(
                entries: entries,
                onIncrement: (entry) => _incrementQuantity(ref, entry),
                onDecrement: (entry) =>
                    _decrementQuantity(context, ref, entry),
                onDelete: (entry) => _deleteEntry(context, ref, entry),
                onOpenDetail: (entry) => _openDetail(context, entry),
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Text(
                    '$error',
                    style: TextStyle(
                      color: AppPalette.of(context).onSurfaceMuted,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _incrementQuantity(
    WidgetRef ref,
    CollectionEntryWithCard entryWithCard,
  ) async {
    final repository = await ref.read(collectionRepositoryProvider.future);
    await repository.setQuantity(
      entryWithCard.entry.id!,
      entryWithCard.entry.quantity + 1,
    );
    ref.invalidate(collectionEntriesProvider);
  }

  Future<void> _decrementQuantity(
    BuildContext context,
    WidgetRef ref,
    CollectionEntryWithCard entryWithCard,
  ) async {
    // Decrementing the last copy removes the card — confirm first, like delete.
    if (entryWithCard.entry.quantity <= 1 &&
        !await confirmRemoveCard(context, ref)) {
      return;
    }
    final repository = await ref.read(collectionRepositoryProvider.future);
    await repository.decrement(entryWithCard.entry.id!);
    ref.invalidate(collectionEntriesProvider);
    // The last copy takes the row with it, so a rarity may no longer be held.
    ref.invalidate(collectionRarityOptionsProvider);
  }

  Future<void> _deleteEntry(
    BuildContext context,
    WidgetRef ref,
    CollectionEntryWithCard entryWithCard,
  ) async {
    if (!await confirmRemoveCard(context, ref)) return;
    final repository = await ref.read(collectionRepositoryProvider.future);
    await repository.delete(entryWithCard.entry.id!);
    ref.invalidate(collectionEntriesProvider);
    ref.invalidate(collectionRarityOptionsProvider);
  }

  void _openDetail(BuildContext context, CollectionEntryWithCard entryWithCard) {
    context.push(AppRoutes.collectionDetail, extra: entryWithCard);
  }
}

class _CollectionList extends StatelessWidget {
  const _CollectionList({
    required this.entries,
    required this.onIncrement,
    required this.onDecrement,
    required this.onDelete,
    required this.onOpenDetail,
  });

  final List<CollectionEntryWithCard> entries;
  final ValueChanged<CollectionEntryWithCard> onIncrement;
  final ValueChanged<CollectionEntryWithCard> onDecrement;
  final ValueChanged<CollectionEntryWithCard> onDelete;
  final ValueChanged<CollectionEntryWithCard> onOpenDetail;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text(
            AppStrings.collectionEmptyMessage,
            style: TextStyle(color: AppPalette.of(context).onSurfaceMuted),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entryWithCard = entries[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: CollectionListTile(
            entryWithCard: entryWithCard,
            onTap: () => onOpenDetail(entryWithCard),
            onIncrement: () => onIncrement(entryWithCard),
            onDecrement: () => onDecrement(entryWithCard),
            onDelete: () => onDelete(entryWithCard),
          ),
        );
      },
    );
  }
}
