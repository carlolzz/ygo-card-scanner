import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/theme/tokens.dart';
import '../../models/card_condition.dart';
import '../../models/card_edition.dart';
import '../../models/card_language.dart';
import '../../models/card_terms.dart';
import '../../models/fast_log_field.dart';
import '../../models/printing.dart';
import '../../models/ygo_card.dart';
import '../../shared/widgets/card_art_thumbnail.dart';
import '../../shared/widgets/card_search_subtitle.dart';
import '../../shared/widgets/fast_log_summary.dart';
import '../../shared/widgets/labeled_choice_chip.dart';
import '../../shared/widgets/search_field.dart';
import '../../shared/widgets/search_language_picker.dart';
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
        title: Text(AppStrings.addCardTitle),
        leading: selection.step == AddCardStep.search
            ? null
            : IconButton(
                tooltip: AppStrings.addCardBackTooltip,
                icon: const Icon(Icons.arrow_back),
                // Under Fast log the printing step is never offered, so this
                // must not route into it: its Skip button would null out a set
                // that was auto-picked, and the step is unreachable by design.
                onPressed: () =>
                    selection.step == AddCardStep.condition &&
                        selection.printings.isNotEmpty &&
                        !controller.fastLogActive
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
          child: Row(
            children: [
              Expanded(
                child: SearchField(
                  autofocus: true,
                  hintText: AppStrings.addCardSearchHint,
                  initialValue: query,
                  onChanged: (query) => ref
                      .read(addCardQueryControllerProvider.notifier)
                      .setQuery(query),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              const SearchLanguagePicker(),
            ],
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
                  final hit = results[index];
                  return ListTile(
                    title: Text(
                      hit.card.name,
                      style: TextStyle(color: palette.onSurface),
                    ),
                    subtitle: CardSearchSubtitle(hit),
                    onTap: () => controller.selectCard(hit.card),
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
    if (widget.selection.card?.passcode != oldWidget.selection.card?.passcode) {
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
        // One scroll view for the card, the search box and the list, with only
        // Skip pinned below. The artwork is tall enough that on a small phone
        // with the keyboard up these no longer fit a fixed layout, and a fixed
        // list above an `Expanded` would overflow rather than scroll.
        Expanded(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _CardIdentity(card: card),
                      const SizedBox(height: AppSpacing.sm),
                      // Type the set instead of scrolling: a reprinted card can
                      // carry a dozen printings, and the user knows which one
                      // is in their hand.
                      TextField(
                        controller: _searchController,
                        style: TextStyle(color: palette.onSurface),
                        onChanged: (value) => setState(() => _query = value),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: AppStrings.setPickerSearchHint,
                          hintStyle: TextStyle(color: palette.onSurfaceMuted),
                          prefixIcon: Icon(
                            Icons.search,
                            color: palette.onSurfaceMuted,
                          ),
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
              ),
              if (matches.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                    ),
                    child: Text(
                      AppStrings.setPickerNoMatches,
                      style: TextStyle(color: palette.onSurfaceMuted),
                    ),
                  ),
                )
              else
                SliverList.builder(
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
                          if (printing.rarity != null)
                            rarityLabel(printing.rarity!),
                        ].join(' · '),
                        style: TextStyle(color: palette.onSurfaceMuted),
                      ),
                      onTap: () => controller.selectPrinting(printing),
                    );
                  },
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: controller.skipPrinting,
              child: Text(AppStrings.addCardPrintingSkip),
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
    final asked = controller.askedFields;

    // Save is pinned below the scroll view rather than at the end of it. With
    // the artwork this tall it would otherwise fall below the fold on a small
    // phone, and this flow is used one-handed, one card after another.
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CardIdentity(
                  card: card,
                  // Unconditional, and under Fast log it is the only thing
                  // naming the set that was auto-picked. It is information, not
                  // a control.
                  setLine: printing == null
                      ? AppStrings.addCardNoPrintingLabel
                      : (printing.setCode ?? printing.setName ?? ''),
                ),
                const SizedBox(height: AppSpacing.lg),
                // Each block below owns its *trailing* gap rather than a leading
                // one, so a block hidden by Fast log takes its spacing with it.
                // The off-state is pixel-identical to before because
                // `lg == md + sm`: three trailing `md`s plus the quantity row's
                // own leading `sm` is the `md, md, lg` this used to read.
                if (asked.contains(FastLogField.condition)) ...[
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      for (final condition in CardCondition.values)
                        LabeledChoiceChip(
                          label: condition.shortCode,
                          selected: selection.condition == condition,
                          selectedColor: ConditionChipColors
                              .byShortCode[condition.shortCode]!,
                          onSelected: () => controller.setCondition(condition),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (asked.contains(FastLogField.edition)) ...[
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
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
                ],
                // The label and its spacer hide with the chips. Unlike the scan
                // panel, this step labels its language row, so it is easy to
                // leave orphaned above nothing.
                if (asked.contains(FastLogField.language)) ...[
                  Text(
                    AppStrings.collectionLanguageLabel,
                    style: TextStyle(color: palette.onSurfaceMuted),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
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
                  const SizedBox(height: AppSpacing.md),
                ],
                // What Save is about to write for the fields with no control.
                if (asked.length < FastLogField.values.length) ...[
                  FastLogSummary(
                    askedFields: asked,
                    condition: selection.condition,
                    edition: selection.edition,
                    language: selection.language,
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Text(
                      AppStrings.collectionQuantityLabel,
                      style: TextStyle(color: palette.onSurface),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () =>
                          controller.setQuantity(selection.quantity - 1),
                    ),
                    Text(
                      '${selection.quantity}',
                      style: TextStyle(color: palette.onSurface, fontSize: 18),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      color: palette.accent,
                      onPressed: () =>
                          controller.setQuantity(selection.quantity + 1),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () async {
                await controller.save();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(AppStrings.addCardSavedMessage)),
                  );
                }
              },
              child: Text(AppStrings.addCardSaveButton),
            ),
          ),
        ),
      ],
    );
  }
}

/// Which card is being logged: artwork, name, type, and on the condition step
/// the set it will be logged against.
///
/// Shared by the printing and condition steps, and shaped after the scan review
/// gate's identity row, because the name alone was the only thing confirming
/// the right card had been picked out of a search list. The wizard was the only
/// logging surface with no picture.
///
/// [CardArtThumbnail], not `CardThumbnail`: the card is not owned yet, so
/// `cards.local_image_path` is NULL and the plain thumbnail would render
/// nothing at all. This one fetches on a miss.
class _CardIdentity extends StatelessWidget {
  const _CardIdentity({required this.card, this.setLine});

  final YgoCard card;

  /// The set line under the type, or null on the printing step, where the set
  /// is what the user is about to choose.
  final String? setLine;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final line = setLine;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The whole card, uncropped: without an aspect ratio the thumbnail is a
        // square `cover` crop, which cut the card off at the sides and bottom.
        // Square corners too, so nothing clips the card's own.
        CardArtThumbnail(
          card: card,
          size: CardThumbnailSizes.addCard,
          aspectRatio: ScanReticleTokens.cardAspectRatio,
          fit: BoxFit.contain,
          cornerRadius: 0,
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
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
              if (card.type != null)
                Text(
                  cardTypeLabel(card.type!),
                  style: TextStyle(color: palette.onSurfaceMuted),
                ),
              if (line != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    line,
                    style: TextStyle(color: palette.onSurfaceMuted),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
