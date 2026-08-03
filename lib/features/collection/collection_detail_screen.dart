import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/theme/tokens.dart';
import '../../data/repositories/collection_repository.dart';
import '../../models/card_condition.dart';
import '../../models/card_edition.dart';
import '../../models/card_language.dart';
import '../../models/collection_entry_with_card.dart';
import '../../models/printing.dart';
import '../../shared/widgets/card_art_thumbnail.dart';
import '../../shared/widgets/labeled_choice_chip.dart';
import '../../shared/widgets/printing_picker.dart';
import 'collection_delete_confirm.dart';
import 'collection_providers.dart';

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
    return Scaffold(
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
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              // The whole card, uncropped (portrait card box + contain) rather
              // than a square centre-crop.
              child: CardArtThumbnail(
                card: card,
                size: CardThumbnailSizes.detail,
                aspectRatio: ScanReticleTokens.cardAspectRatio,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
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
            if (card.type != null)
              _DetailRow(
                label: AppStrings.collectionCardTypeLabel,
                value: card.type!,
              ),
            // A Spell/Trap's `attribute` is just "SPELL"/"TRAP" (redundant with
            // the type row above), so it's only shown for monsters.
            if (card.attribute != null && !card.isSpellOrTrap)
              _DetailRow(
                label: AppStrings.collectionCardAttributeLabel,
                value: card.attribute!,
              ),
            if (card.race != null)
              _DetailRow(
                // For Spell/Trap, `race` is the card's own kind, not a monster
                // type — and naming the frame ("Spell Type"/"Trap Type") is
                // what players call it, so it beats a generic "Property".
                label: switch (card) {
                  _ when card.isSpell =>
                    AppStrings.collectionCardSpellTypeLabel,
                  _ when card.isTrap => AppStrings.collectionCardTrapTypeLabel,
                  _ => AppStrings.collectionCardRaceLabel,
                },
                value: card.race!,
              ),
            if (card.level != null)
              _DetailRow(
                label: AppStrings.collectionCardLevelLabel,
                value: '${card.level}',
              ),
            if (card.atk != null || card.def != null)
              _DetailRow(
                label: AppStrings.collectionCardAtkDefLabel,
                value: '${card.atk ?? '-'} / ${card.def ?? '-'}',
              ),
            if (card.archetype != null)
              _DetailRow(
                label: AppStrings.collectionCardArchetypeLabel,
                value: card.archetype!,
              ),
            // Set and rarity are separate rows: `displayLabel` trails the
            // rarity onto the set code for the pickers (which search over it),
            // but here rarity is a field in its own right.
            if (widget.entryWithCard.printing != null)
              _DetailRow(
                label: AppStrings.collectionSetLabel,
                value: widget.entryWithCard.printing!.setLabel,
              ),
            if (widget.entryWithCard.printing?.rarity != null)
              _DetailRow(
                label: AppStrings.collectionRarityLabel,
                value: widget.entryWithCard.printing!.rarity!,
              ),
            _DetailRow(
              label: AppStrings.collectionEditionLabel,
              value: entry.edition.label,
            ),
            _DetailRow(
              label: AppStrings.collectionLanguageLabel,
              value: languageLabel(entry.language),
            ),
            if (card.description != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                card.isNormalMonster
                    ? AppStrings.collectionFlavorTextLabel
                    : AppStrings.collectionCardEffectLabel,
                style: TextStyle(
                  color: palette.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                card.description!,
                style: TextStyle(
                  color: palette.onSurfaceMuted),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Text(
                  AppStrings.collectionQuantityLabel,
                  style: TextStyle(
                  color: palette.onSurface),
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
            _LanguageBreakdown(passcode: entry.passcode),
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
    setState(() => _quantity -= 1);
  }

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
      backgroundColor: AppPalette.of(context).surface,
      builder: (_) => _EditEntrySheet(entryWithCard: widget.entryWithCard),
    );
    if (result == null || !mounted) return;
    ref.invalidate(collectionEntriesProvider);
    // The edit can move the entry to a different printing, i.e. a different
    // rarity — the one non-delete path that changes the filter row's options.
    ref.invalidate(collectionFilterOptionsProvider);
    ref.invalidate(entriesForPasscodeProvider(widget.entryWithCard.entry.passcode));
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

/// Per-language totals for this card, summed across all of its entries. Shown
/// only when the card is held in more than one language — passcodes are
/// language-independent, so the same card in English and German lives as two
/// rows under one passcode, and this is where those rows are reunited.
class _LanguageBreakdown extends ConsumerWidget {
  const _LanguageBreakdown({required this.passcode});

  final String passcode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(entriesForPasscodeProvider(passcode));
    final entries = entriesAsync.value;
    if (entries == null) return const SizedBox.shrink();

    final byLanguage = <String, int>{};
    for (final entry in entries) {
      byLanguage[entry.language] =
          (byLanguage[entry.language] ?? 0) + entry.quantity;
    }
    if (byLanguage.length < 2) return const SizedBox.shrink();

    final languages = byLanguage.keys.toList()..sort();
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.md),
        Text(
          AppStrings.collectionByLanguageLabel,
          style: TextStyle(
            color: palette.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        for (final language in languages)
          _DetailRow(
            label: languageLabel(language),
            value: '×${byLanguage[language]}',
          ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: TextStyle(color: palette.onSurfaceMuted)),
          ),
          Expanded(
            child: Text(value, style: TextStyle(color: palette.onSurface)),
          ),
        ],
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
    Navigator.of(context).pop(
      _EditResult(merged: survivorId != widget.entryWithCard.entry.id),
    );
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
                      onPressed:
                          _saving ? null : () => Navigator.of(context).pop(),
                      child: const Text(AppStrings.collectionEditCancelButton),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child: const Text(AppStrings.collectionEditSaveButton),
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
