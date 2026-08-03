import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants.dart';
import '../../core/theme/tokens.dart';
import '../../data/export/collection_csv_parser.dart';
import '../../data/export/collection_exporter.dart';
import '../../data/import/collection_import_plan.dart';
import '../../data/import/collection_importer.dart';
import '../../data/import/csv_file_source.dart';
import '../../models/card_condition.dart';
import '../../models/card_language.dart';
import '../collection/collection_providers.dart';
import 'statistics_providers.dart';

/// Collection statistics: totals and breakdowns by condition, language, and
/// card type, plus a full-collection CSV export. Reads colors via
/// [AppPalette.of] — there is no `AppColors` fallback.
class StatisticsScreen extends ConsumerWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(collectionStatsProvider);
    final palette = AppPalette.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.statisticsTitle)),
      body: statsAsync.when(
        // The actions live outside the empty check on purpose: importing a CSV
        // into an empty collection is the *main* case for that button, and it
        // used to be unreachable there because the whole body was replaced by
        // the empty message.
        data: (stats) => stats.totalCopies == 0
            ? ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.lg,
                    ),
                    child: Text(
                      AppStrings.statisticsEmptyMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: palette.onSurfaceMuted),
                    ),
                  ),
                  const _Actions(),
                ],
              )
            : _StatisticsBody(stats: stats),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Text(
              '$error',
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.onSurfaceMuted),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatisticsBody extends StatelessWidget {
  const _StatisticsBody({required this.stats});

  final CollectionStats stats;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Row(
          children: [
            Expanded(
              child: _StatTile(
                label: AppStrings.statisticsTotalCopiesLabel,
                value: '${stats.totalCopies}',
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _StatTile(
                label: AppStrings.statisticsDistinctCardsLabel,
                value: '${stats.distinctCards}',
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        _BreakdownSection(
          title: AppStrings.statisticsByConditionSection,
          rows: _conditionRows(stats.byCondition),
        ),
        _BreakdownSection(
          title: AppStrings.statisticsByLanguageSection,
          rows: _languageRows(stats.byLanguage),
        ),
        _BreakdownSection(
          title: AppStrings.statisticsByTypeSection,
          rows: _typeRows(stats.byCardType),
        ),
        const SizedBox(height: AppSpacing.md),
        const _Actions(),
      ],
    );
  }

  /// Ordered best -> worst by `CardCondition` declaration order, skipping grades
  /// the user holds none of. Unknown db values (from a hand-edited row) sort
  /// last under their raw value.
  List<_BreakdownRow> _conditionRows(Map<String, int> byCondition) {
    final rows = <_BreakdownRow>[];
    final seen = <String>{};
    for (final condition in CardCondition.values) {
      final count = byCondition[condition.toDb()];
      if (count == null) continue;
      seen.add(condition.toDb());
      rows.add(_BreakdownRow(condition.label, count));
    }
    for (final entry in byCondition.entries) {
      if (seen.contains(entry.key)) continue;
      rows.add(_BreakdownRow(entry.key, entry.value));
    }
    return rows;
  }

  List<_BreakdownRow> _languageRows(Map<String, int> byLanguage) {
    final keys = byLanguage.keys.toList()..sort();
    return [
      for (final key in keys) _BreakdownRow(languageLabel(key), byLanguage[key]!),
    ];
  }

  List<_BreakdownRow> _typeRows(Map<String, int> byType) {
    final keys = byType.keys.toList()..sort();
    return [
      for (final key in keys)
        _BreakdownRow(
          key.isEmpty ? AppStrings.statisticsUnknownType : key,
          byType[key]!,
        ),
    ];
  }
}

class _BreakdownRow {
  const _BreakdownRow(this.label, this.count);

  final String label;
  final int count;
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              color: palette.accent,
              fontWeight: FontWeight.bold,
              fontSize: 28,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(label, style: TextStyle(color: palette.onSurfaceMuted)),
        ],
      ),
    );
  }
}

class _BreakdownSection extends StatelessWidget {
  const _BreakdownSection({required this.title, required this.rows});

  final String title;
  final List<_BreakdownRow> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: palette.onSurface,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    row.label,
                    style: TextStyle(color: palette.onSurface),
                  ),
                ),
                Text(
                  '${row.count}',
                  style: TextStyle(
                    color: palette.onSurfaceMuted,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }
}

/// The two file actions, kept together so the empty-collection branch and the
/// populated one can render the same pair.
class _Actions extends StatelessWidget {
  const _Actions();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        SizedBox(width: double.infinity, child: _ExportButton()),
        SizedBox(height: AppSpacing.sm),
        SizedBox(width: double.infinity, child: _ImportButton()),
      ],
    );
  }
}

/// Writes the entire collection to a CSV file and reports where it landed.
/// Stateful only to disable itself while a write is in flight.
class _ExportButton extends ConsumerStatefulWidget {
  const _ExportButton();

  @override
  ConsumerState<_ExportButton> createState() => _ExportButtonState();
}

class _ExportButtonState extends ConsumerState<_ExportButton> {
  bool _running = false;

  Future<void> _export() async {
    setState(() => _running = true);
    String? path;
    String message;
    try {
      final exporter = await ref.read(collectionExporterProvider.future);
      path = await exporter.exportToCsv();
      message = AppStrings.statisticsExportDoneMessage;
    } catch (_) {
      message = AppStrings.statisticsExportFailedMessage;
    }
    if (!mounted) return;
    setState(() => _running = false);
    // Hand the written file to the OS share sheet — the app-documents path it
    // lives at isn't browsable, so sharing is how the user saves it to
    // Downloads/Drive/Files or sends it on.
    if (path != null) {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path)],
          subject: AppStrings.statisticsExportSubject,
        ),
      );
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      icon: const Icon(Icons.download),
      onPressed: _running ? null : _export,
      label: Text(
        _running
            ? AppStrings.statisticsExportRunningMessage
            : AppStrings.statisticsExportButton,
      ),
    );
  }
}

/// Folds a CSV into the collection already on the device.
///
/// Two steps, never one: the file is read and resolved first, then the user is
/// shown what it would do and picks how duplicates are handled. A collection is
/// not something to modify on the strength of a file name.
class _ImportButton extends ConsumerStatefulWidget {
  const _ImportButton();

  @override
  ConsumerState<_ImportButton> createState() => _ImportButtonState();
}

class _ImportButtonState extends ConsumerState<_ImportButton> {
  bool _running = false;

  Future<void> _import() async {
    setState(() => _running = true);
    try {
      final picked = await ref.read(csvFileSourceProvider).pick();
      // Cancelled at the picker: no dialog, no message, nothing happened.
      if (picked == null) return;

      final importer = await ref.read(collectionImporterProvider.future);
      final CollectionImportPreview preview;
      try {
        preview = await importer.preview(picked.contents);
      } on CsvFormatException catch (error) {
        _say('${AppStrings.statisticsImportFailedMessage}\n\n$error');
        return;
      }
      if (!mounted) return;

      if (preview.rows.isEmpty) {
        _say(AppStrings.statisticsImportNothingMessage);
        return;
      }

      final strategy = await showDialog<ImportMergeStrategy>(
        context: context,
        builder: (context) => _ImportPreviewDialog(preview: preview),
      );
      if (strategy == null || !mounted) return;

      final result = await importer.apply(preview, strategy);
      // Everything downstream of the collection rows: the list, the filter
      // options (an import can bring in sets and languages that were not held
      // before) and these very statistics.
      ref
        ..invalidate(collectionEntriesProvider)
        ..invalidate(collectionFilterOptionsProvider)
        ..invalidate(collectionStatsProvider);
      _say(_describe(result));
    } catch (_) {
      _say(AppStrings.statisticsImportFailedMessage);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  String _describe(CollectionImportResult result) {
    final parts = <String>[
      if (result.entriesAdded > 0) '${result.entriesAdded} added',
      if (result.entriesMerged > 0) '${result.entriesMerged} merged',
      if (result.skipped > 0) '${result.skipped} skipped',
    ];
    if (parts.isEmpty) return AppStrings.statisticsImportDoneMessage;
    return '${AppStrings.statisticsImportDoneMessage} ${parts.join(', ')}.';
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      icon: const Icon(Icons.upload_file),
      onPressed: _running ? null : _import,
      label: Text(
        _running
            ? AppStrings.statisticsImportRunningMessage
            : AppStrings.statisticsImportButton,
      ),
    );
  }
}

/// What the file will do, and the one question only the user can answer.
///
/// The merge choice is offered *only* when something actually matches — with
/// nothing to merge there is no question, and asking one anyway invites the
/// user to think there is a decision they might be getting wrong.
class _ImportPreviewDialog extends StatefulWidget {
  const _ImportPreviewDialog({required this.preview});

  final CollectionImportPreview preview;

  @override
  State<_ImportPreviewDialog> createState() => _ImportPreviewDialogState();
}

class _ImportPreviewDialogState extends State<_ImportPreviewDialog> {
  ImportMergeStrategy _strategy = ImportMergeStrategy.keepExisting;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final preview = widget.preview;
    final plan = preview.plan;

    return AlertDialog(
      title: const Text(AppStrings.statisticsImportTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Count(plan.newEntries, AppStrings.statisticsImportNewLabel),
            _Count(plan.matchedEntries, AppStrings.statisticsImportMatchedLabel),
            _Count(preview.skipped, AppStrings.statisticsImportSkippedLabel),
            _Count(
              plan.setsUnresolved,
              AppStrings.statisticsImportUnresolvedSetLabel,
            ),
            if (plan.matchedEntries > 0) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                AppStrings.statisticsImportMergeQuestion,
                style: TextStyle(
                  color: palette.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
              // `RadioGroup` rather than the per-tile `groupValue`/`onChanged`,
              // which Flutter deprecated after 3.32.
              RadioGroup<ImportMergeStrategy>(
                groupValue: _strategy,
                onChanged: (value) => setState(
                  () => _strategy = value ?? ImportMergeStrategy.keepExisting,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final option in ImportMergeStrategy.values)
                      RadioListTile<ImportMergeStrategy>(
                        contentPadding: EdgeInsets.zero,
                        value: option,
                        activeColor: palette.accent,
                        title: Text(
                          switch (option) {
                            ImportMergeStrategy.keepExisting =>
                              AppStrings.statisticsImportKeepOption,
                            ImportMergeStrategy.sumQuantities =>
                              AppStrings.statisticsImportSumOption,
                          },
                          style: TextStyle(color: palette.onSurface),
                        ),
                        subtitle: Text(
                          switch (option) {
                            ImportMergeStrategy.keepExisting =>
                              AppStrings.statisticsImportKeepDetail,
                            ImportMergeStrategy.sumQuantities =>
                              AppStrings.statisticsImportSumDetail,
                          },
                          style: TextStyle(color: palette.onSurfaceMuted),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(AppStrings.statisticsImportCancelButton),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_strategy),
          child: const Text(AppStrings.statisticsImportConfirmButton),
        ),
      ],
    );
  }
}

/// One line of the preview, hidden when its count is zero — a dialog of "0
/// skipped, 0 unrecognised" reads as a warning about problems that do not
/// exist.
class _Count extends StatelessWidget {
  const _Count(this.count, this.label);

  final int count;
  final String label;

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: RichText(
        text: TextSpan(
          style: TextStyle(color: palette.onSurfaceMuted),
          children: [
            TextSpan(
              text: '$count ',
              style: TextStyle(
                color: palette.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
            TextSpan(text: label),
          ],
        ),
      ),
    );
  }
}
