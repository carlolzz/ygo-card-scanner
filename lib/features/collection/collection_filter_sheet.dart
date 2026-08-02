import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/theme/tokens.dart';
import '../../data/db/dao/collection_dao.dart';
import '../../models/card_condition.dart';
import '../../models/card_edition.dart';
import '../../models/card_language.dart';
import '../../shared/widgets/labeled_choice_chip.dart';
import 'collection_providers.dart';

/// Opens the collection filter sheet. Returns once it closes; applying is done
/// by the sheet itself through [CollectionFilterController.apply].
Future<void> showCollectionFilterSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppPalette.of(context).surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    builder: (context) => const _CollectionFilterSheet(),
  );
}

/// Every filter in one place: a basic group always shown, and an advanced group
/// behind a tick box.
///
/// **Edits a local draft and applies it on a button**, rather than writing
/// through on every tap. Two reasons, both practical: the sheet covers the list
/// it is filtering, so live updates would be invisible anyway; and each change
/// re-runs `getAll` through the sqflite isolate, so a user setting five filters
/// would trigger five full re-queries they never see.
class _CollectionFilterSheet extends ConsumerStatefulWidget {
  const _CollectionFilterSheet();

  @override
  ConsumerState<_CollectionFilterSheet> createState() =>
      _CollectionFilterSheetState();
}

class _CollectionFilterSheetState
    extends ConsumerState<_CollectionFilterSheet> {
  late CollectionFilter _draft;
  bool _advanced = false;

  @override
  void initState() {
    super.initState();
    _draft = ref.read(collectionFilterControllerProvider);
    // Open with the advanced section already expanded if it is in use —
    // otherwise a filter that is narrowing the list would be hidden behind a
    // tick box the user has to remember to look under.
    _advanced =
        _draft.level != null ||
        _draft.frameType != null ||
        _draft.race != null ||
        _draft.attribute != null ||
        _draft.archetype != null ||
        _draft.cardType != null ||
        !_draft.atk.isEmpty ||
        !_draft.def.isEmpty;
  }

  void _update(CollectionFilter next) => setState(() => _draft = next);

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    // `.value`, not `when`: options are optional detail, and a spinner would
    // make the sheet jump on open. The same reading the scan review gate's set
    // picker uses.
    final options =
        ref.watch(collectionFilterOptionsProvider).value ??
        const CollectionFilterOptions();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          top: AppSpacing.lg,
          bottom: AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    AppStrings.collectionFiltersTitle,
                    style: TextStyle(
                      color: palette.onSurface,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
                TextButton(
                  // Keeps the search query and the sort: Reset must not clear
                  // the box the user typed into or reorder the list underneath
                  // them. See `CollectionFilter.cleared`.
                  onPressed: () => _update(_draft.cleared()),
                  child: Text(AppStrings.collectionFiltersReset),
                ),
              ],
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Group(
                      label: AppStrings.collectionFilterConditionLabel,
                      child: _ChipRow<CardCondition>(
                        values: CardCondition.values,
                        selected: _draft.condition,
                        labelOf: (c) => c.shortCode,
                        colorOf: (c) =>
                            ConditionChipColors.byShortCode[c.shortCode]!,
                        onSelected: (value) => _update(
                          _draft.copyWith(
                            condition: value,
                            clearCondition: value == null,
                          ),
                        ),
                      ),
                    ),
                    if (options.rarities.isNotEmpty)
                      _Group(
                        label: AppStrings.collectionFilterRarityLabel,
                        child: _RarityRow(
                          rarities: options.rarities,
                          selected: _draft.rarity,
                          onSelected: (value) => _update(
                            _draft.copyWith(
                              rarity: value,
                              clearRarity: value == null,
                            ),
                          ),
                        ),
                      ),
                    if (options.setNames.isNotEmpty)
                      _Group(
                        label: AppStrings.collectionFilterSetLabel,
                        child: _ChipRow<String>(
                          values: options.setNames,
                          selected: _draft.setName,
                          labelOf: (s) => s,
                          onSelected: (value) => _update(
                            _draft.copyWith(
                              setName: value,
                              clearSetName: value == null,
                            ),
                          ),
                        ),
                      ),
                    _Group(
                      label: AppStrings.collectionFilterEditionLabel,
                      child: _ChipRow<CardEdition>(
                        values: CardEdition.values,
                        selected: _draft.edition,
                        labelOf: (e) => e.label,
                        onSelected: (value) => _update(
                          _draft.copyWith(
                            edition: value,
                            clearEdition: value == null,
                          ),
                        ),
                      ),
                    ),
                    if (options.languages.isNotEmpty)
                      _Group(
                        label: AppStrings.collectionFilterLanguageLabel,
                        child: _ChipRow<String>(
                          values: options.languages,
                          selected: _draft.language,
                          labelOf: languageLabel,
                          onSelected: (value) => _update(
                            _draft.copyWith(
                              language: value,
                              clearLanguage: value == null,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: AppSpacing.sm),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: palette.accent,
                      value: _advanced,
                      onChanged: (value) =>
                          setState(() => _advanced = value ?? false),
                      title: Text(
                        AppStrings.collectionFiltersAdvanced,
                        style: TextStyle(color: palette.onSurface),
                      ),
                    ),
                    if (_advanced) ..._advancedGroups(options),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  ref
                      .read(collectionFilterControllerProvider.notifier)
                      .apply(_draft);
                  Navigator.of(context).pop();
                },
                child: Text(AppStrings.collectionFiltersApply),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _advancedGroups(CollectionFilterOptions options) => [
    if (options.levels.isNotEmpty)
      _Group(
        label: AppStrings.collectionFilterLevelLabel,
        child: _ChipRow<int>(
          values: options.levels,
          selected: _draft.level,
          labelOf: (v) => '$v',
          onSelected: (value) => _update(
            _draft.copyWith(level: value, clearLevel: value == null),
          ),
        ),
      ),
    if (options.frameTypes.isNotEmpty)
      _Group(
        label: AppStrings.collectionFilterFrameTypeLabel,
        child: _ChipRow<String>(
          values: options.frameTypes,
          selected: _draft.frameType,
          labelOf: _titleCase,
          onSelected: (value) => _update(
            _draft.copyWith(frameType: value, clearFrameType: value == null),
          ),
        ),
      ),
    if (options.cardTypes.isNotEmpty)
      _Group(
        label: AppStrings.collectionFilterCardTypeLabel,
        child: _ChipRow<String>(
          values: options.cardTypes,
          selected: _draft.cardType,
          labelOf: (v) => v,
          onSelected: (value) => _update(
            _draft.copyWith(cardType: value, clearCardType: value == null),
          ),
        ),
      ),
    if (options.races.isNotEmpty)
      _Group(
        // YGOPRODeck overloads `race` — it is the monster type on a monster and
        // the Spell/Trap type on a Spell or Trap — so one control covers both
        // and the label has to say so.
        label: AppStrings.collectionFilterRaceLabel,
        child: _ChipRow<String>(
          values: options.races,
          selected: _draft.race,
          labelOf: (v) => v,
          onSelected: (value) =>
              _update(_draft.copyWith(race: value, clearRace: value == null)),
        ),
      ),
    if (options.attributes.isNotEmpty)
      _Group(
        label: AppStrings.collectionFilterAttributeLabel,
        child: _ChipRow<String>(
          values: options.attributes,
          selected: _draft.attribute,
          labelOf: (v) => v,
          onSelected: (value) => _update(
            _draft.copyWith(attribute: value, clearAttribute: value == null),
          ),
        ),
      ),
    if (options.archetypes.isNotEmpty)
      _Group(
        label: AppStrings.collectionFilterArchetypeLabel,
        child: _ChipRow<String>(
          values: options.archetypes,
          selected: _draft.archetype,
          labelOf: (v) => v,
          onSelected: (value) => _update(
            _draft.copyWith(archetype: value, clearArchetype: value == null),
          ),
        ),
      ),
    _Group(
      label: AppStrings.collectionFilterAtkLabel,
      child: _RangeRow(
        range: _draft.atk,
        onChanged: (range) => _update(_draft.copyWith(atk: range)),
      ),
    ),
    _Group(
      label: AppStrings.collectionFilterDefLabel,
      child: _RangeRow(
        range: _draft.def,
        onChanged: (range) => _update(_draft.copyWith(def: range)),
      ),
    ),
  ];
}

/// `normal` -> `Normal`, for YGOPRODeck's lowercase frame types.
String _titleCase(String value) =>
    value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);

/// A labelled block in the sheet.
class _Group extends StatelessWidget {
  const _Group({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: AppPalette.of(context).onSurfaceMuted),
          ),
          const SizedBox(height: AppSpacing.xs),
          child,
        ],
      ),
    );
  }
}

/// "All" plus one chip per value, single-select. Tapping the selected chip
/// clears it, so every filter can be turned off without hunting for "All".
class _ChipRow<T> extends StatelessWidget {
  const _ChipRow({
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
    this.colorOf,
  });

  final List<T> values;
  final T? selected;
  final String Function(T) labelOf;
  final Color Function(T)? colorOf;

  /// Null clears the filter.
  final ValueChanged<T?> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        LabeledChoiceChip(
          label: AppStrings.collectionFilterAll,
          selected: selected == null,
          selectedColor: palette.accent,
          onSelected: () => onSelected(null),
        ),
        for (final value in values)
          LabeledChoiceChip(
            label: labelOf(value),
            selected: selected == value,
            selectedColor: colorOf?.call(value) ?? palette.accent,
            onSelected: () => onSelected(selected == value ? null : value),
          ),
      ],
    );
  }
}

/// The rarity row, which needs its own widget because a null element means the
/// distinct "no rarity" option rather than "All" — see [RarityFilter].
class _RarityRow extends StatelessWidget {
  const _RarityRow({
    required this.rarities,
    required this.selected,
    required this.onSelected,
  });

  final List<String?> rarities;
  final RarityFilter? selected;
  final ValueChanged<RarityFilter?> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        LabeledChoiceChip(
          label: AppStrings.collectionFilterAll,
          selected: selected == null,
          selectedColor: palette.accent,
          onSelected: () => onSelected(null),
        ),
        for (final rarity in rarities)
          Builder(
            builder: (context) {
              final value = rarity == null
                  ? const RarityFilter.noRarity()
                  : RarityFilter.value(rarity);
              final isSelected = selected == value;
              return LabeledChoiceChip(
                label: rarity ?? AppStrings.collectionFilterNoRarity,
                selected: isSelected,
                selectedColor: palette.accent,
                onSelected: () => onSelected(isSelected ? null : value),
              );
            },
          ),
      ],
    );
  }
}

/// Min/max number fields for ATK and DEF. Either bound may be left blank, so
/// "2500 and up" and "up to 1000" are both expressible.
class _RangeRow extends StatelessWidget {
  const _RangeRow({required this.range, required this.onChanged});

  final NumericRange range;
  final ValueChanged<NumericRange> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _RangeField(
            hint: AppStrings.collectionFilterMinHint,
            value: range.min,
            onChanged: (value) =>
                onChanged(NumericRange(min: value, max: range.max)),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _RangeField(
            hint: AppStrings.collectionFilterMaxHint,
            value: range.max,
            onChanged: (value) =>
                onChanged(NumericRange(min: range.min, max: value)),
          ),
        ),
      ],
    );
  }
}

class _RangeField extends StatefulWidget {
  const _RangeField({
    required this.hint,
    required this.value,
    required this.onChanged,
  });

  final String hint;
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  State<_RangeField> createState() => _RangeFieldState();
}

class _RangeFieldState extends State<_RangeField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value?.toString() ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return TextField(
      controller: _controller,
      keyboardType: TextInputType.number,
      style: TextStyle(color: palette.onSurface),
      decoration: InputDecoration(
        isDense: true,
        hintText: widget.hint,
        hintStyle: TextStyle(color: palette.onSurfaceMuted),
        filled: true,
        fillColor: palette.surfaceRaised,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide.none,
        ),
      ),
      // A blank or unparseable field is "no bound", not zero — typing then
      // clearing must remove the filter rather than pin it to >= 0.
      onChanged: (text) => widget.onChanged(int.tryParse(text.trim())),
    );
  }
}
