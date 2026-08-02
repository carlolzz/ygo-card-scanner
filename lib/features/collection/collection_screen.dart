import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/routes.dart';
import '../../core/theme/tokens.dart';
import '../../data/db/dao/collection_dao.dart';
import '../../data/repositories/collection_repository.dart';
import '../../models/collection_entry_with_card.dart';
import '../../models/collection_view_mode.dart';
import '../settings/settings_providers.dart';
import 'collection_delete_confirm.dart';
import 'collection_filter_bar.dart';
import 'collection_grid_tile.dart';
import 'collection_list_tile.dart';
import 'collection_providers.dart';

class CollectionScreen extends ConsumerWidget {
  const CollectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(collectionEntriesProvider);
    final filter = ref.watch(collectionFilterControllerProvider);
    // `.value ?? default`: the list must not blank out while settings resolve,
    // and Standard is what it would have rendered before this setting existed.
    final viewMode =
        ref.watch(settingsControllerProvider).value?.collectionViewMode ??
        CollectionViewMode.standard;

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.homeTileMyCollection),
        actions: [
          // Sort moved here when the chip rows it used to sit among were
          // replaced by the filter sheet — it belongs beside its own direction
          // toggle, and sorting is not a filter.
          PopupMenuButton<CollectionSortBy>(
            tooltip: AppStrings.collectionSortTooltip,
            icon: const Icon(Icons.sort),
            initialValue: filter.sortBy,
            onSelected: ref
                .read(collectionFilterControllerProvider.notifier)
                .setSortBy,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: CollectionSortBy.name,
                child: Text(AppStrings.collectionSortByName),
              ),
              PopupMenuItem(
                value: CollectionSortBy.dateAdded,
                child: Text(AppStrings.collectionSortByDateAdded),
              ),
              PopupMenuItem(
                value: CollectionSortBy.quantity,
                child: Text(AppStrings.collectionSortByQuantity),
              ),
            ],
          ),
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
                viewMode: viewMode,
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
    ref.invalidate(collectionFilterOptionsProvider);
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
    ref.invalidate(collectionFilterOptionsProvider);
  }

  void _openDetail(BuildContext context, CollectionEntryWithCard entryWithCard) {
    context.push(AppRoutes.collectionDetail, extra: entryWithCard);
  }
}

class _CollectionList extends StatelessWidget {
  const _CollectionList({
    required this.entries,
    required this.viewMode,
    required this.onIncrement,
    required this.onDecrement,
    required this.onDelete,
    required this.onOpenDetail,
  });

  final List<CollectionEntryWithCard> entries;
  final CollectionViewMode viewMode;
  final ValueChanged<CollectionEntryWithCard> onIncrement;
  final ValueChanged<CollectionEntryWithCard> onDecrement;
  final ValueChanged<CollectionEntryWithCard> onDelete;
  final ValueChanged<CollectionEntryWithCard> onOpenDetail;

  static const _padding = EdgeInsets.symmetric(
    horizontal: AppSpacing.md,
    vertical: AppSpacing.sm,
  );

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
    return viewMode.isGrid ? _buildGrid() : _buildList();
  }

  Widget _buildList() {
    return ListView.builder(
      padding: _padding,
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

  Widget _buildGrid() {
    final showName = viewMode.showsName;
    final extent = showName
        ? CollectionGridTokens.artworkAndNameExtent
        : CollectionGridTokens.artworkOnlyExtent;
    // `maxCrossAxisExtent`, not a fixed column count: the right number of
    // columns is a function of the viewport, and pinning it would be correct on
    // one device and wrong on the next.
    return GridView.builder(
      padding: _padding,
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: extent,
        crossAxisSpacing: CollectionGridTokens.spacing,
        mainAxisSpacing: CollectionGridTokens.spacing,
        // The cell is the card's own aspect plus, when captioned, a fixed strip
        // for the name — so the artwork keeps its true proportions in both
        // modes instead of the caption squashing it.
        childAspectRatio: showName
            ? 1 /
                  (1 / ScanReticleTokens.cardAspectRatio +
                      CollectionGridTokens.nameCaptionHeight / extent)
            : ScanReticleTokens.cardAspectRatio,
      ),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entryWithCard = entries[index];
        return CollectionGridTile(
          entryWithCard: entryWithCard,
          showName: showName,
          onTap: () => onOpenDetail(entryWithCard),
        );
      },
    );
  }
}
