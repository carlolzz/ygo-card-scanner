import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/money.dart';
import '../../core/routes.dart';
import '../../core/theme/tokens.dart';
import '../../data/export/collection_csv.dart';
import '../../data/export/collection_csv_parser.dart';
import '../../data/export/collection_exporter.dart';
import '../../data/export/file_share.dart';
import '../../data/import/collection_import_plan.dart';
import '../../data/import/collection_importer.dart';
import '../../data/import/csv_file_source.dart';
import '../../data/repositories/price_repository.dart';
import '../../models/card_condition.dart';
import '../../models/card_language.dart';
import '../collection/collection_providers.dart';
import '../pricing/card_prices_view.dart';
import 'stat_tile.dart';
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
      appBar: AppBar(title: Text(AppStrings.statisticsTitle)),
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
              child: StatTile(
                label: AppStrings.statisticsTotalCopiesLabel,
                value: '${stats.totalCopies}',
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: StatTile(
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
        const _CollectionValueSection(),
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
      for (final key in keys)
        _BreakdownRow(languageLabel(key), byLanguage[key]!),
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

/// What the collection is worth, on demand.
///
/// **On demand, never on open.** Valuing a collection is a burst of network
/// requests — one per 50 distinct cards — so it happens when the user asks for
/// it, which is why `CollectionValueController` starts null rather than being a
/// `FutureProvider` the screen watches into existence.
///
/// Only rendered in the populated branch: there is nothing to value in an empty
/// collection, unlike the import button beside it, which is most useful exactly
/// there.
class _CollectionValueSection extends ConsumerWidget {
  const _CollectionValueSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(collectionValueControllerProvider);
    final controller = ref.read(collectionValueControllerProvider.notifier);
    final palette = AppPalette.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppStrings.statisticsValueSection,
          style: TextStyle(
            color: palette.onSurface,
            fontWeight: FontWeight.bold,
            fontSize: CardDetailTokens.sectionFontSize,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        switch (state?.status) {
          null => SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.payments_outlined),
              label: Text(AppStrings.statisticsValueButton),
              onPressed: controller.calculate,
            ),
          ),
          CollectionValueStatus.running => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const LinearProgressIndicator(),
              const SizedBox(height: AppSpacing.xs),
              Text(
                AppStrings.statisticsValueProgress(state!.done, state.total),
                style: TextStyle(color: palette.onSurfaceMuted),
              ),
            ],
          ),
          CollectionValueStatus.failure => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppStrings.statisticsValueErrorMessage,
                style: TextStyle(color: palette.onSurfaceMuted),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton(
                onPressed: controller.calculate,
                child: Text(AppStrings.pricesRetryButton),
              ),
            ],
          ),
          CollectionValueStatus.success => _ValueResult(
            value: state!.value!,
            onRefresh: () => controller.calculate(forceRefresh: true),
          ),
        },
      ],
    );
  }
}

class _ValueResult extends StatelessWidget {
  const _ValueResult({required this.value, required this.onRefresh});

  final CollectionValue value;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Two tiles, never one sum: Cardmarket is euros and TCGplayer is
        // dollars, and this app carries no exchange rate.
        Row(
          children: [
            Expanded(
              child: StatTile(
                label: AppStrings.statisticsValueCardmarketLabel,
                value: formatEur(value.cardmarketEur),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: StatTile(
                label: AppStrings.statisticsValueTcgplayerLabel,
                value: formatUsd(value.tcgplayerUsd),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        // Hidden at zero, like the import dialog's counts: a total assembled
        // from a whole collection should not warn about a problem that does not
        // exist.
        if (value.unpricedCards > 0)
          Text(
            AppStrings.statisticsValueUnpriced(value.unpricedCards),
            style: TextStyle(
              color: palette.onSurfaceMuted,
              fontSize: PriceTokens.footnoteFontSize,
            ),
          ),
        Text(
          AppStrings.statisticsValueNote,
          style: TextStyle(
            color: palette.onSurfaceMuted,
            fontSize: PriceTokens.footnoteFontSize,
          ),
        ),
        if (value.asOf != null)
          Text(
            AppStrings.pricesFetchedAt(formatFetchedAt(value.asOf!)),
            style: TextStyle(
              color: palette.onSurfaceMuted,
              fontSize: PriceTokens.footnoteFontSize,
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        // Stacked, not in a row: three labelled buttons crowd a 360pt screen.
        // Breakdown first — reading the figures is the common next step, while
        // refreshing and exporting are things you do once you trust them.
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.receipt_long),
            label: Text(AppStrings.statisticsValueBreakdownButton),
            onPressed: () =>
                context.push(AppRoutes.collectionValue, extra: value),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.refresh),
            label: Text(AppStrings.statisticsValueRefreshButton),
            onPressed: onRefresh,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: _ValueExportButton(value: value),
        ),
      ],
    );
  }
}

/// What to tell the user once the share sheet has resolved.
///
/// Shared by both export buttons so the two formats cannot report a cancelled
/// share differently. [ShareOutcome.unknown] reads as success on purpose: the
/// file was written and the sheet was offered, and on a platform that cannot
/// report the choice, claiming a cancellation that may not have happened is the
/// worse of the two errors.
String _exportMessage(ShareOutcome outcome) => switch (outcome) {
  ShareOutcome.shared ||
  ShareOutcome.unknown => AppStrings.statisticsExportDoneMessage,
  ShareOutcome.cancelled => AppStrings.statisticsExportCancelledMessage,
};

/// The SnackBar both export buttons show once they are done.
///
/// A cancelled share is reported briefly: the user dismissed the sheet a
/// moment ago and only needs to see that nothing was sent, while every other
/// outcome keeps Material's default so a success or failure can be read in
/// full. [outcome] is null when the share sheet never opened (the write
/// failed), which is not a cancellation.
SnackBar _exportSnackBar(String message, ShareOutcome? outcome) =>
    outcome == ShareOutcome.cancelled
    ? SnackBar(
        content: Text(message),
        duration: SnackBarTokens.briefDuration,
      )
    : SnackBar(content: Text(message));

/// Writes the per-card figures behind the totals to their own CSV.
///
/// Lives here, inside the result, rather than in [_Actions] beside the
/// collection export: there is nothing to export until a calculation has
/// succeeded, and [_Actions] also renders in the empty-collection branch, where
/// this button would be live with nothing behind it. The [CollectionValue] it
/// writes is the one on screen, passed straight through.
///
/// Stateful only to disable itself while a write is in flight, exactly like
/// [_ExportButton].
class _ValueExportButton extends ConsumerStatefulWidget {
  const _ValueExportButton({required this.value});

  final CollectionValue value;

  @override
  ConsumerState<_ValueExportButton> createState() => _ValueExportButtonState();
}

class _ValueExportButtonState extends ConsumerState<_ValueExportButton> {
  bool _running = false;

  Future<void> _export() async {
    setState(() => _running = true);
    String? path;
    String message;
    try {
      final exporter = await ref.read(collectionExporterProvider.future);
      path = await exporter.exportValueToCsv(widget.value);
      message = AppStrings.statisticsExportDoneMessage;
    } catch (_) {
      message = AppStrings.statisticsExportFailedMessage;
    }
    if (!mounted) return;
    setState(() => _running = false);
    // The message is chosen *after* the sheet resolves. It used to be fixed
    // before the sheet even opened, so a cancelled share still claimed success.
    ShareOutcome? outcome;
    if (path != null) {
      outcome = await ref.read(fileShareProvider).shareFiles([
        path,
      ], subject: AppStrings.statisticsValueExportSubject);
      message = _exportMessage(outcome);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(_exportSnackBar(message, outcome));
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      icon: const Icon(Icons.download),
      onPressed: _running ? null : _export,
      label: Text(
        _running
            ? AppStrings.statisticsExportRunningMessage
            : AppStrings.statisticsValueExportButton,
      ),
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
    ShareOutcome? outcome;
    if (path != null) {
      outcome = await ref.read(fileShareProvider).shareFiles([
        path,
      ], subject: AppStrings.statisticsExportSubject);
      message = _exportMessage(outcome);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(_exportSnackBar(message, outcome));
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
        final column = error.missingColumn;
        final reason = column == null
            ? AppStrings.statisticsImportEmptyFile
            : AppStrings.statisticsImportMissingColumn(
                column,
                collectionCsvHeader.join(', '),
              );
        _say('${AppStrings.statisticsImportFailedMessage}\n\n$reason');
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
      if (result.entriesAdded > 0)
        AppStrings.statisticsImportAddedCount(result.entriesAdded),
      if (result.entriesMerged > 0)
        AppStrings.statisticsImportMergedCount(result.entriesMerged),
      if (result.skipped > 0)
        AppStrings.statisticsImportSkippedCount(result.skipped),
    ];
    if (parts.isEmpty) return AppStrings.statisticsImportDoneMessage;
    return '${AppStrings.statisticsImportDoneMessage} ${parts.join(', ')}.';
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
      title: Text(AppStrings.statisticsImportTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Count(plan.newEntries, AppStrings.statisticsImportNewLabel),
            _Count(
              plan.matchedEntries,
              AppStrings.statisticsImportMatchedLabel,
            ),
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
                        title: Text(switch (option) {
                          ImportMergeStrategy.keepExisting =>
                            AppStrings.statisticsImportKeepOption,
                          ImportMergeStrategy.sumQuantities =>
                            AppStrings.statisticsImportSumOption,
                        }, style: TextStyle(color: palette.onSurface)),
                        subtitle: Text(switch (option) {
                          ImportMergeStrategy.keepExisting =>
                            AppStrings.statisticsImportKeepDetail,
                          ImportMergeStrategy.sumQuantities =>
                            AppStrings.statisticsImportSumDetail,
                        }, style: TextStyle(color: palette.onSurfaceMuted)),
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
          child: Text(AppStrings.statisticsImportCancelButton),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_strategy),
          child: Text(AppStrings.statisticsImportConfirmButton),
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
