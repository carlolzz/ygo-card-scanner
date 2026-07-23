import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/theme/tokens.dart';
import '../../data/repositories/collection_repository.dart';
import '../../models/card_language.dart';
import '../../models/collection_entry_with_card.dart';
import '../../models/printing.dart';
import '../../shared/widgets/card_thumbnail.dart';
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
              child: CardThumbnail(
                localImagePath: card.localImagePath,
                size: CardThumbnailSizes.detail,
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
            if (card.attribute != null)
              _DetailRow(
                label: AppStrings.collectionCardAttributeLabel,
                value: card.attribute!,
              ),
            if (card.race != null)
              _DetailRow(
                label: AppStrings.collectionCardRaceLabel,
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
            if (widget.entryWithCard.printing != null)
              _DetailRow(
                label: AppStrings.collectionSetLabel,
                value: _setValue(widget.entryWithCard.printing!),
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

  String _setValue(Printing printing) {
    final parts = [
      if (printing.setCode != null) printing.setCode!,
      if (printing.setName != null) printing.setName!,
      if (printing.rarity != null) printing.rarity!,
    ];
    return parts.join(' · ');
  }

  Future<void> _increment(int id) async {
    final repository = await ref.read(collectionRepositoryProvider.future);
    final next = _quantity + 1;
    await repository.setQuantity(id, next);
    ref.invalidate(collectionEntriesProvider);
    setState(() => _quantity = next);
  }

  Future<void> _decrement(int id) async {
    final repository = await ref.read(collectionRepositoryProvider.future);
    await repository.decrement(id);
    ref.invalidate(collectionEntriesProvider);
    if (_quantity <= 1) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    setState(() => _quantity -= 1);
  }

  Future<void> _confirmDelete(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppStrings.collectionDeleteDialogTitle),
        content: const Text(AppStrings.collectionDeleteDialogMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(AppStrings.collectionDeleteDialogCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(AppStrings.collectionDeleteDialogConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final repository = await ref.read(collectionRepositoryProvider.future);
    await repository.delete(id);
    ref.invalidate(collectionEntriesProvider);
    if (mounted) Navigator.of(context).pop();
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
