import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/theme/tokens.dart';
import '../../data/export/collection_exporter.dart';
import '../../models/card_condition.dart';
import '../../models/card_language.dart';
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
        data: (stats) => stats.totalCopies == 0
            ? Center(
                child: Text(
                  AppStrings.statisticsEmptyMessage,
                  style: TextStyle(color: palette.onSurfaceMuted),
                ),
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
        const _ExportButton(),
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
    String message;
    try {
      final exporter = await ref.read(collectionExporterProvider.future);
      final path = await exporter.exportToCsv();
      message = AppStrings.statisticsExportDoneMessage(path);
    } catch (_) {
      message = AppStrings.statisticsExportFailedMessage;
    }
    if (!mounted) return;
    setState(() => _running = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        icon: const Icon(Icons.download),
        onPressed: _running ? null : _export,
        label: Text(
          _running
              ? AppStrings.statisticsExportRunningMessage
              : AppStrings.statisticsExportButton,
        ),
      ),
    );
  }
}
