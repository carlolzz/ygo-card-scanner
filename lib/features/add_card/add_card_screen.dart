import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/theme/tokens.dart';
import '../../models/card_condition.dart';
import '../../models/card_edition.dart';
import '../../models/card_language.dart';
import '../../models/printing.dart';
import '../../shared/widgets/labeled_choice_chip.dart';
import 'add_card_providers.dart';

/// Manual add-card flow: search by name -> pick a printing (skipped when
/// none exist) -> pick condition/edition/quantity -> save. All state lives
/// in [AddCardSelectionController] rather than local widget state, so the
/// step-skip logic and save/reset behavior stay out of `build()`.
class AddCardScreen extends ConsumerWidget {
  const AddCardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(addCardSelectionControllerProvider);
    final controller = ref.read(addCardSelectionControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.addCardTitle),
        leading: selection.step == AddCardStep.search
            ? null
            : IconButton(
                tooltip: AppStrings.addCardBackTooltip,
                icon: const Icon(Icons.arrow_back),
                onPressed: () => selection.step == AddCardStep.condition &&
                        selection.printings.isNotEmpty
                    ? controller.backToPrinting()
                    : controller.backToSearch(),
              ),
      ),
      body: switch (selection.step) {
        AddCardStep.search => const _SearchStep(),
        AddCardStep.printing => _PrintingStep(selection: selection),
        AddCardStep.condition => _ConditionStep(selection: selection),
      },
    );
  }
}

class _SearchStep extends ConsumerWidget {
  const _SearchStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(addCardQueryControllerProvider);
    final resultsAsync = ref.watch(addCardSearchResultsProvider);
    final controller = ref.read(addCardSelectionControllerProvider.notifier);
    final palette = AppPalette.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: TextField(
            autofocus: true,
            style: TextStyle(color: palette.onSurface),
            decoration: InputDecoration(
              hintText: AppStrings.addCardSearchHint,
              hintStyle: TextStyle(color: palette.onSurfaceMuted),
              prefixIcon: Icon(
                Icons.search,
                color: palette.onSurfaceMuted,
              ),
              filled: true,
              fillColor: palette.surfaceRaised,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (query) => ref
                .read(addCardQueryControllerProvider.notifier)
                .setQuery(query),
          ),
        ),
        Expanded(
          child: resultsAsync.when(
            data: (results) {
              if (results.isEmpty) {
                if (query.isEmpty) return const SizedBox.shrink();
                return Center(
                  child: Text(
                    AppStrings.addCardSearchEmptyMessage,
                    style: TextStyle(color: palette.onSurfaceMuted),
                  ),
                );
              }
              return ListView.builder(
                itemCount: results.length,
                itemBuilder: (context, index) {
                  final card = results[index];
                  return ListTile(
                    title: Text(
                      card.name,
                      style: TextStyle(color: palette.onSurface),
                    ),
                    subtitle: card.type == null
                        ? null
                        : Text(
                            card.type!,
                            style: TextStyle(
                              color: palette.onSurfaceMuted,
                            ),
                          ),
                    onTap: () => controller.selectCard(card),
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) => Center(
              child: Text(
                '$error',
                style: TextStyle(color: palette.onSurfaceMuted),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The printing step of the wizard: pick which set/expansion this copy is from.
///
/// Stateful only for the search box's [TextEditingController] — the query is
/// ephemeral input state, not part of the card being logged, so it stays out of
/// [AddCardSelection] (which resets between cards anyway).
class _PrintingStep extends ConsumerStatefulWidget {
  const _PrintingStep({required this.selection});

  final AddCardSelection selection;

  @override
  ConsumerState<_PrintingStep> createState() => _PrintingStepState();
}

class _PrintingStepState extends ConsumerState<_PrintingStep> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void didUpdateWidget(_PrintingStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different card means a different set list — don't carry the last card's
    // query over and show an empty list.
    if (widget.selection.card?.passcode !=
        oldWidget.selection.card?.passcode) {
      _searchController.clear();
      _query = '';
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(addCardSelectionControllerProvider.notifier);
    final card = widget.selection.card!;
    final palette = AppPalette.of(context);
    final matches = filterPrintings(widget.selection.printings, _query);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                card.name,
                style: TextStyle(
                  color: palette.onSurface,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              // Type the set instead of scrolling: a reprinted card can carry a
              // dozen printings, and the user knows which one is in their hand.
              TextField(
                controller: _searchController,
                style: TextStyle(color: palette.onSurface),
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: AppStrings.setPickerSearchHint,
                  hintStyle: TextStyle(color: palette.onSurfaceMuted),
                  prefixIcon: Icon(Icons.search, color: palette.onSurfaceMuted),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          color: palette.onSurfaceMuted,
                          tooltip: AppStrings.setPickerClearTooltip,
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        ),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: matches.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  child: Text(
                    AppStrings.setPickerNoMatches,
                    style: TextStyle(color: palette.onSurfaceMuted),
                  ),
                )
              : ListView.builder(
                  itemCount: matches.length,
                  itemBuilder: (context, index) {
                    final printing = matches[index];
                    return ListTile(
                      title: Text(
                        printing.setCode ?? printing.setName ?? '',
                        style: TextStyle(color: palette.onSurface),
                      ),
                      subtitle: Text(
                        [
                          if (printing.setName != null) printing.setName!,
                          if (printing.rarity != null) printing.rarity!,
                        ].join(' · '),
                        style: TextStyle(color: palette.onSurfaceMuted),
                      ),
                      onTap: () => controller.selectPrinting(printing),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: controller.skipPrinting,
              child: const Text(AppStrings.addCardPrintingSkip),
            ),
          ),
        ),
      ],
    );
  }
}

class _ConditionStep extends ConsumerWidget {
  const _ConditionStep({required this.selection});

  final AddCardSelection selection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(addCardSelectionControllerProvider.notifier);
    final card = selection.card!;
    final printing = selection.printing;
    final palette = AppPalette.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            card.name,
            style: TextStyle(
              color: palette.onSurface,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            printing == null
                ? AppStrings.addCardNoPrintingLabel
                : (printing.setCode ?? printing.setName ?? ''),
            style: TextStyle(color: palette.onSurfaceMuted),
          ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.xs,
            children: [
              for (final condition in CardCondition.values)
                LabeledChoiceChip(
                  label: condition.shortCode,
                  selected: selection.condition == condition,
                  selectedColor:
                      ConditionChipColors.byShortCode[condition.shortCode]!,
                  onSelected: () => controller.setCondition(condition),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.xs,
            children: [
              for (final edition in CardEdition.values)
                LabeledChoiceChip(
                  label: edition.label,
                  selected: selection.edition == edition,
                  selectedColor: palette.accent,
                  onSelected: () => controller.setEdition(edition),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            AppStrings.collectionLanguageLabel,
            style: TextStyle(color: palette.onSurfaceMuted),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            children: [
              for (final language in kCardLanguages)
                LabeledChoiceChip(
                  label: languageLabel(language),
                  selected: selection.language == language,
                  selectedColor: palette.accent,
                  onSelected: () => controller.setLanguage(language),
                ),
            ],
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
                onPressed: () => controller.setQuantity(selection.quantity - 1),
              ),
              Text(
                '${selection.quantity}',
                style: TextStyle(color: palette.onSurface, fontSize: 18),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                color: palette.accent,
                onPressed: () => controller.setQuantity(selection.quantity + 1),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () async {
                await controller.save();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text(AppStrings.addCardSavedMessage)),
                  );
                }
              },
              child: const Text(AppStrings.addCardSaveButton),
            ),
          ),
        ],
      ),
    );
  }
}
