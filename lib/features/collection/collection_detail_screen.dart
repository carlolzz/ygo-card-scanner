import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/theme/tokens.dart';
import '../../data/repositories/collection_repository.dart';
import '../../models/card_condition.dart';
import '../../models/card_edition.dart';
import '../../models/card_language.dart';
import '../../models/card_terms.dart';
import '../../models/collection_entry_with_card.dart';
import '../../models/printing.dart';
import '../../shared/widgets/card_details_view.dart';
import '../../shared/widgets/labeled_choice_chip.dart';
import '../../shared/widgets/language_flag.dart';
import '../../shared/widgets/printing_picker.dart';
import '../pricing/card_prices_view.dart';
import 'collection_copies_view.dart';
import 'collection_delete_confirm.dart';
import 'collection_providers.dart';

/// Where the Prices tab sits, for the price estimate's link to it. Named because
/// a wrong index here fails silently, landing on a different tab.
const int _pricesTabIndex = 2;

class CollectionDetailScreen extends ConsumerStatefulWidget {
  const CollectionDetailScreen({super.key, required this.entryWithCard});

  final CollectionEntryWithCard entryWithCard;

  @override
  ConsumerState<CollectionDetailScreen> createState() =>
      _CollectionDetailScreenState();
}

class _CollectionDetailScreenState
    extends ConsumerState<CollectionDetailScreen> {
  late int _quantity;

  @override
  void initState() {
    super.initState();
    _quantity = widget.entryWithCard.entry.quantity;
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entryWithCard.entry;
    final card = widget.entryWithCard.card;
    final conditionColor =
        ConditionChipColors.byShortCode[entry.condition.shortCode]!;

    final palette = AppPalette.of(context);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(card.name),
          actions: [
            IconButton(
              tooltip: AppStrings.collectionEditTooltip,
              icon: const Icon(Icons.edit_outlined),
              onPressed: _openEdit,
            ),
            IconButton(
              tooltip: AppStrings.collectionDeleteTooltip,
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _confirmDelete(entry.id!),
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: AppStrings.cardTabDetails),
              Tab(text: AppStrings.cardTabCopies),
              Tab(text: AppStrings.cardTabPrices),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The card's own facts, shared verbatim with the card-search
                  // detail screen — the Spell/Trap label switch and the
                  // flavour-vs-effect heading are rules, not formatting, and a
                  // second copy of them would drift.
                  Builder(
                    // Its own context so `DefaultTabController.of` finds the
                    // controller above.
                    builder: (context) => CardDetailsView(
                      card: card,
                      leading: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: AppSpacing.xs,
                            ),
                            decoration: BoxDecoration(
                              color: conditionColor,
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                            child: Text(
                              entry.condition.label,
                              style: const TextStyle(
                                color: ConditionChipColors.onSelected,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          // Priced for the copies actually held, so the number
                          // answers "what is this stack worth" rather than
                          // "what is one of these worth".
                          CardPriceEstimate(
                            passcode: entry.passcode,
                            quantity: _quantity,
                            onTap: () => DefaultTabController.of(
                              context,
                            ).animateTo(_pricesTabIndex),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  // Everything below is about *this entry* rather than the
                  // card, which is why it stays here and not in the shared view.
                  //
                  // Set and rarity are separate rows: `displayLabel` trails the
                  // rarity onto the set code for the pickers (which search over
                  // it), but here rarity is a field in its own right.
                  if (widget.entryWithCard.printing != null)
                    CardDetailRow(
                      label: AppStrings.collectionSetLabel,
                      value: widget.entryWithCard.printing!.setLabel,
                    ),
                  if (widget.entryWithCard.printing?.rarity != null)
                    CardDetailRow(
                      label: AppStrings.collectionRarityLabel,
                      value: rarityLabel(widget.entryWithCard.printing!.rarity!),
                    ),
                  CardDetailRow(
                    label: AppStrings.collectionEditionLabel,
                    value: entry.edition.label,
                  ),
                  CardDetailRow(
                    label: AppStrings.collectionLanguageLabel,
                    valueLeading: LanguageFlag(language: entry.language),
                    value: languageLabel(entry.language),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    children: [
                      Text(
                        AppStrings.collectionQuantityLabel,
                        style: TextStyle(color: palette.onSurface),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () => _decrement(entry.id!),
                      ),
                      Text(
                        '$_quantity',
                        style: TextStyle(
                          color: palette.onSurface,
                          fontSize: 18,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        color: palette.accent,
                        onPressed: () => _increment(entry.id!),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            CollectionCopiesView(
              passcode: entry.passcode,
              currentEntryId: entry.id,
            ),
            CardPricesView(passcode: entry.passcode),
          ],
        ),
      ),
    );
  }

  Future<void> _increment(int id) async {
    final repository = await ref.read(collectionRepositoryProvider.future);
    final next = _quantity + 1;
    await repository.setQuantity(id, next);
    ref.invalidate(collectionEntriesProvider);
    _invalidateCopies();
    setState(() => _quantity = next);
  }

  Future<void> _decrement(int id) async {
    // Decrementing the last copy removes the card — confirm first, like delete.
    if (_quantity <= 1) {
      if (!await confirmRemoveCard(context, ref)) return;
      final repository = await ref.read(collectionRepositoryProvider.future);
      await repository.decrement(id);
      ref.invalidate(collectionEntriesProvider);
      // The last copy takes the row with it, so a rarity may no longer be held.
      ref.invalidate(collectionFilterOptionsProvider);
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final repository = await ref.read(collectionRepositoryProvider.future);
    await repository.decrement(id);
    ref.invalidate(collectionEntriesProvider);
    _invalidateCopies();
    setState(() => _quantity -= 1);
  }

  /// The tab's provider is normally disposed while the tab is off screen and so
  /// re-reads on return, but tap + and swipe straight across and the tab has
  /// already read the old count by the time the write lands. Without this it
  /// would go on showing that count.
  void _invalidateCopies() => ref.invalidate(
    ownedCopiesProvider(widget.entryWithCard.entry.passcode),
  );

  Future<void> _confirmDelete(int id) async {
    if (!await confirmRemoveCard(context, ref)) return;
    final repository = await ref.read(collectionRepositoryProvider.future);
    await repository.delete(id);
    ref.invalidate(collectionEntriesProvider);
    ref.invalidate(collectionFilterOptionsProvider);
    if (mounted) Navigator.of(context).pop();
  }

  /// Opens the edit sheet. On save the passed-in entry is stale (and a merge may
  /// have removed this row), so the detail screen pops back to the list, which
  /// re-fetches — and a snackbar reports the result there.
  Future<void> _openEdit() async {
    final result = await showModalBottomSheet<_EditResult>(
      context: context,
      isScrollControlled: true,
      // See `showCollectionFilterSheet` — without this the sheet's own
      // `SafeArea` is stripped and a tall sheet runs under the status bar.
      useSafeArea: true,
      backgroundColor: AppPalette.of(context).surface,
      builder: (_) => _EditEntrySheet(entryWithCard: widget.entryWithCard),
    );
    if (result == null || !mounted) return;
    ref.invalidate(collectionEntriesProvider);
    // The edit can move the entry to a different printing, i.e. a different
    // rarity — the one non-delete path that changes the filter row's options.
    ref.invalidate(collectionFilterOptionsProvider);
    _invalidateCopies();
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          result.merged
              ? AppStrings.collectionEditMergedMessage
              : AppStrings.collectionEditSavedMessage,
        ),
      ),
    );
  }
}

/// The outcome of the edit sheet, popped back to the detail screen: whether the
/// edit merged this entry into a pre-existing matching one (vs. a plain update),
/// so the right confirmation message is shown.
class _EditResult {
  const _EditResult({required this.merged});

  final bool merged;
}

/// A modal sheet to edit an entry's condition/edition/language/set. Local state,
/// seeded from the entry; on save it calls
/// [CollectionRepository.updateEntryDetails] (which merges on a duplicate) and
/// pops an [_EditResult].
class _EditEntrySheet extends ConsumerStatefulWidget {
  const _EditEntrySheet({required this.entryWithCard});

  final CollectionEntryWithCard entryWithCard;

  @override
  ConsumerState<_EditEntrySheet> createState() => _EditEntrySheetState();
}

class _EditEntrySheetState extends ConsumerState<_EditEntrySheet> {
  late CardCondition _condition;
  late CardEdition _edition;
  late String _language;
  late int? _printingId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final entry = widget.entryWithCard.entry;
    _condition = entry.condition;
    _edition = entry.edition;
    _language = entry.language;
    _printingId = entry.printingId;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final repository = await ref.read(collectionRepositoryProvider.future);
    final survivorId = await repository.updateEntryDetails(
      widget.entryWithCard.entry.id!,
      printingId: _printingId,
      condition: _condition,
      edition: _edition,
      language: _language,
    );
    if (!mounted) return;
    Navigator.of(
      context,
    ).pop(_EditResult(merged: survivorId != widget.entryWithCard.entry.id));
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final passcode = widget.entryWithCard.entry.passcode;
    final printingsAsync = ref.watch(cardPrintingsProvider(passcode));

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          top: AppSpacing.lg,
          bottom: AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppStrings.collectionEditTitle,
                style: TextStyle(
                  color: palette.onSurface,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              // First, above the chips: the picker's search field raises the
              // keyboard, which would otherwise cover it and the language row.
              _label(AppStrings.collectionEditSetLabel),
              printingsAsync.when(
                data: _printingPicker,
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: LinearProgressIndicator(),
                ),
                error: (_, _) => _printingPicker(const <Printing>[]),
              ),
              const SizedBox(height: AppSpacing.md),
              _label(AppStrings.collectionEditConditionLabel),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final condition in CardCondition.values)
                    LabeledChoiceChip(
                      label: condition.shortCode,
                      selected: _condition == condition,
                      selectedColor:
                          ConditionChipColors.byShortCode[condition.shortCode]!,
                      onSelected: () => setState(() => _condition = condition),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _label(AppStrings.collectionEditEditionLabel),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final edition in CardEdition.values)
                    LabeledChoiceChip(
                      label: edition.label,
                      selected: _edition == edition,
                      selectedColor: palette.accent,
                      onSelected: () => setState(() => _edition = edition),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _label(AppStrings.collectionEditLanguageLabel),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final language in kCardLanguages)
                    LabeledChoiceChip(
                      label: languageLabel(language),
                      selected: _language == language,
                      selectedColor: palette.accent,
                      onSelected: () => setState(() => _language = language),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: Text(AppStrings.collectionEditCancelButton),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child: Text(AppStrings.collectionEditSaveButton),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
    child: Text(
      text,
      style: TextStyle(color: AppPalette.of(context).onSurfaceMuted),
    ),
  );

  Widget _printingPicker(List<Printing> printings) {
    // Keep the selection valid: a printing_id always refers to a printing of
    // this passcode (the schema forbids deleting one with entries), but guard
    // anyway so a stale value can't select a row the picker isn't showing.
    final ids = printings.map((p) => p.id).toSet();
    return PrintingPicker(
      printings: printings,
      selectedId: ids.contains(_printingId) ? _printingId : null,
      noSetLabel: AppStrings.collectionEditNoPrinting,
      onSelected: (id) => setState(() => _printingId = id),
    );
  }
}
