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
    final selection = ref.watch(collectionSelectionControllerProvider);
    // `.value ?? default`: the list must not blank out while settings resolve,
    // and Standard is what it would have rendered before this setting existed.
    final viewMode =
        ref.watch(settingsControllerProvider).value?.collectionViewMode ??
        CollectionViewMode.standard;

    // Android back cancels the selection rather than leaving the screen. Without
    // this the only way out is the close icon, and backing out of a mode is what
    // the system button is for.
    return PopScope(
      canPop: !selection.active,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          ref.read(collectionSelectionControllerProvider.notifier).exit();
        }
      },
      child: Scaffold(
        appBar: selection.active
            ? _selectionAppBar(context, ref, selection, entriesAsync.value)
            : AppBar(
                title: const Text(AppStrings.homeTileMyCollection),
                actions: [
                  // Sort moved here when the chip rows it used to sit among were
                  // replaced by the filter sheet — it belongs beside its own
                  // direction toggle, and sorting is not a filter.
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
                      PopupMenuItem(
                        value: CollectionSortBy.cardType,
                        child: Text(AppStrings.collectionSortByCardType),
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
            // Hidden while selecting: changing the filter clears the selection
            // by design (see `CollectionSelectionController.build`), so offering
            // it here would look like it silently discarded the user's picks.
            if (!selection.active) const CollectionFilterBar(),
            Expanded(
              child: entriesAsync.when(
                data: (entries) => _CollectionList(
                  entries: entries,
                  viewMode: viewMode,
                  selection: selection,
                  onIncrement: (entry) => _incrementQuantity(ref, entry),
                  onDecrement: (entry) =>
                      _decrementQuantity(context, ref, entry),
                  onDelete: (entry) => _deleteEntry(context, ref, entry),
                  onOpenDetail: (entry) => _openDetail(context, entry),
                  onToggleSelect: (entry) => ref
                      .read(collectionSelectionControllerProvider.notifier)
                      .toggle(entry.entry.id!),
                  onEnterSelect: (entry) => ref
                      .read(collectionSelectionControllerProvider.notifier)
                      .enter(entry.entry.id!),
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
      ),
    );
  }

  /// The app bar while multi-selecting. Sort and its direction toggle are gone —
  /// reordering the list under a live selection is noise, and the actions that
  /// belong here are the ones that act on the selection.
  PreferredSizeWidget _selectionAppBar(
    BuildContext context,
    WidgetRef ref,
    CollectionSelection selection,
    List<CollectionEntryWithCard>? entries,
  ) {
    final controller = ref.read(
      collectionSelectionControllerProvider.notifier,
    );
    final visible = entries ?? const <CollectionEntryWithCard>[];
    final allSelected =
        visible.isNotEmpty &&
        visible.every((entry) => selection.contains(entry.entry.id));
    return AppBar(
      leading: IconButton(
        tooltip: AppStrings.collectionExitSelectionTooltip,
        icon: const Icon(Icons.close),
        onPressed: controller.exit,
      ),
      title: Text(
        '${selection.count} ${AppStrings.collectionSelectedSuffix}',
      ),
      actions: [
        IconButton(
          tooltip: allSelected
              ? AppStrings.collectionSelectNoneTooltip
              : AppStrings.collectionSelectAllTooltip,
          icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
          onPressed: () => allSelected
              ? controller.clearSelection()
              // Only what the filter currently shows, which is also all the
              // selection is ever allowed to hold — see the controller.
              : controller.selectAll(visible.map((e) => e.entry.id!)),
        ),
        IconButton(
          tooltip: AppStrings.collectionDeleteSelectedTooltip,
          icon: const Icon(Icons.delete_outline),
          onPressed: selection.ids.isEmpty
              ? null
              : () => _deleteSelected(context, ref, selection.ids.toList()),
        ),
      ],
    );
  }

  Future<void> _deleteSelected(
    BuildContext context,
    WidgetRef ref,
    List<int> ids,
  ) async {
    // `bulkCount` marks the multi-select path, which always prompts whatever
    // "Ask before deleting" says — see `confirmRemoveCard`.
    if (!await confirmRemoveCard(context, ref, bulkCount: ids.length)) return;
    final repository = await ref.read(collectionRepositoryProvider.future);
    final removed = await repository.deleteMany(ids);
    ref.invalidate(collectionEntriesProvider);
    // A bulk delete can take the last card holding a rarity, set or language
    // with it — the documented case for invalidating the options too.
    ref.invalidate(collectionFilterOptionsProvider);
    ref.read(collectionSelectionControllerProvider.notifier).exit();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$removed ${AppStrings.collectionDeletedManyMessage}'),
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
    required this.selection,
    required this.onIncrement,
    required this.onDecrement,
    required this.onDelete,
    required this.onOpenDetail,
    required this.onToggleSelect,
    required this.onEnterSelect,
  });

  final List<CollectionEntryWithCard> entries;
  final CollectionViewMode viewMode;
  final CollectionSelection selection;
  final ValueChanged<CollectionEntryWithCard> onIncrement;
  final ValueChanged<CollectionEntryWithCard> onDecrement;
  final ValueChanged<CollectionEntryWithCard> onDelete;
  final ValueChanged<CollectionEntryWithCard> onOpenDetail;
  final ValueChanged<CollectionEntryWithCard> onToggleSelect;
  final ValueChanged<CollectionEntryWithCard> onEnterSelect;

  /// What a tap means depends on the mode, and the decision is made here rather
  /// than in the tiles — they stay presentation-only, mutations flowing up via
  /// callbacks exactly as their doc comments say.
  VoidCallback _onTap(CollectionEntryWithCard entry) => selection.active
      ? () => onToggleSelect(entry)
      : () => onOpenDetail(entry);

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
            onTap: _onTap(entryWithCard),
            onLongPress: () => onEnterSelect(entryWithCard),
            onIncrement: () => onIncrement(entryWithCard),
            onDecrement: () => onDecrement(entryWithCard),
            onDelete: () => onDelete(entryWithCard),
            selectionActive: selection.active,
            selected: selection.contains(entryWithCard.entry.id),
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
          onTap: _onTap(entryWithCard),
          onLongPress: () => onEnterSelect(entryWithCard),
          selectionActive: selection.active,
          selected: selection.contains(entryWithCard.entry.id),
        );
      },
    );
  }
}
