import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../models/app_settings.dart';
import '../../models/app_theme_mode.dart';
import '../../models/card_condition.dart';
import '../../models/card_edition.dart';
import '../../models/card_language.dart';
import '../../models/collection_sort_by.dart';
import '../../models/collection_view_mode.dart';
import '../../models/fast_log_field.dart';
import '../db/dao/meta_dao.dart';
import '../db/database.dart';

part 'settings_repository.g.dart';

/// Meta keys. Namespaced so they can't collide with the existing
/// `last_sync` / `schema_version` entries.
const _conditionKey = 'settings.default_condition';
const _editionKey = 'settings.default_edition';
const _languageKey = 'settings.language';
const _themeModeKey = 'settings.theme_mode';
const _showScanDiagnosticsKey = 'settings.show_scan_diagnostics';
const _showScanHelpKey = 'settings.show_scan_help';
const _keepCameraReadyKey = 'settings.keep_camera_ready';
const _confirmBeforeDeleteKey = 'settings.confirm_before_delete';
const _collectionViewModeKey = 'settings.collection_view_mode';
const _collectionSortByKey = 'settings.collection_sort_by';
const _collectionSortDescendingKey = 'settings.collection_sort_descending';
const _searchLanguageKey = 'settings.search_language';
const _fastLogEnabledKey = 'settings.fast_log_enabled';
const _fastLogFieldsKey = 'settings.fast_log_fields';

/// Reads and writes [AppSettings] as key/value pairs in the existing `meta`
/// table. No schema change: `meta` has carried arbitrary keys since v1, and a
/// handful of preferences don't justify a table (or a new storage dependency).
class SettingsRepository {
  const SettingsRepository(this._metaDao);

  final MetaDao _metaDao;

  Future<AppSettings> load() async {
    const defaults = AppSettings();
    return AppSettings(
      defaultCondition: _parse(
        await _metaDao.get(_conditionKey),
        CardCondition.fromDb,
        defaults.defaultCondition,
      ),
      defaultEdition: _parse(
        await _metaDao.get(_editionKey),
        CardEdition.fromDb,
        defaults.defaultEdition,
      ),
      language: await _metaDao.get(_languageKey) ?? defaults.language,
      themeMode: _parse(
        await _metaDao.get(_themeModeKey),
        AppThemeMode.fromDb,
        defaults.themeMode,
      ),
      showScanDiagnostics: _parseBool(
        await _metaDao.get(_showScanDiagnosticsKey),
        defaults.showScanDiagnostics,
      ),
      showScanHelp: _parseBool(
        await _metaDao.get(_showScanHelpKey),
        defaults.showScanHelp,
      ),
      keepCameraReady: _parseBool(
        await _metaDao.get(_keepCameraReadyKey),
        defaults.keepCameraReady,
      ),
      confirmBeforeDelete: _parseBool(
        await _metaDao.get(_confirmBeforeDeleteKey),
        defaults.confirmBeforeDelete,
      ),
      collectionViewMode: _parse(
        await _metaDao.get(_collectionViewModeKey),
        CollectionViewMode.fromDb,
        defaults.collectionViewMode,
      ),
      collectionSortBy: _parse(
        await _metaDao.get(_collectionSortByKey),
        CollectionSortBy.fromDb,
        defaults.collectionSortBy,
      ),
      collectionSortDescending: _parseBool(
        await _metaDao.get(_collectionSortDescendingKey),
        defaults.collectionSortDescending,
      ),
      searchLanguage: _parseChoice(
        await _metaDao.get(_searchLanguageKey),
        kSearchLanguages,
        defaults.searchLanguage,
      ),
      fastLogEnabled: _parseBool(
        await _metaDao.get(_fastLogEnabledKey),
        defaults.fastLogEnabled,
      ),
      fastLogFields: _parseFields(
        await _metaDao.get(_fastLogFieldsKey),
        defaults.fastLogFields,
      ),
    );
  }

  Future<void> save(AppSettings settings) async {
    await _metaDao.set(_conditionKey, settings.defaultCondition.toDb());
    await _metaDao.set(_editionKey, settings.defaultEdition.toDb());
    await _metaDao.set(_languageKey, settings.language);
    await _metaDao.set(_themeModeKey, settings.themeMode.toDb());
    await _metaDao.set(
      _showScanDiagnosticsKey,
      settings.showScanDiagnostics.toString(),
    );
    await _metaDao.set(_showScanHelpKey, settings.showScanHelp.toString());
    await _metaDao.set(
      _keepCameraReadyKey,
      settings.keepCameraReady.toString(),
    );
    await _metaDao.set(
      _confirmBeforeDeleteKey,
      settings.confirmBeforeDelete.toString(),
    );
    await _metaDao.set(
      _collectionViewModeKey,
      settings.collectionViewMode.toDb(),
    );
    await _metaDao.set(_collectionSortByKey, settings.collectionSortBy.toDb());
    await _metaDao.set(
      _collectionSortDescendingKey,
      settings.collectionSortDescending.toString(),
    );
    await _metaDao.set(_searchLanguageKey, settings.searchLanguage);
    await _metaDao.set(_fastLogEnabledKey, settings.fastLogEnabled.toString());
    // Written in declaration order, not the set's own iteration order: a
    // `{...set, field}` literal preserves insertion order, so ticking Edition
    // then Condition would otherwise store a different value than ticking them
    // the other way round for the identical configuration.
    await _metaDao.set(
      _fastLogFieldsKey,
      FastLogField.values
          .where(settings.fastLogFields.contains)
          .map((field) => field.toDb())
          .join(','),
    );
  }

  /// Every `fromDb` throws on an unrecognized value. A stored value can be
  /// unrecognized for reasons that are not bugs — a downgrade after a future
  /// version added an enum member, or a hand-edited database — and settings
  /// are read during app start, so a bad value must degrade to the default
  /// rather than take the whole app down.
  static T _parse<T>(String? stored, T Function(String) fromDb, T fallback) {
    if (stored == null) return fallback;
    try {
      return fromDb(stored);
    } on ArgumentError {
      return fallback;
    }
  }

  /// A free-text value that must be one of a known set — the string equivalent
  /// of [_parse]'s guard, for a preference whose vocabulary is a plain const
  /// list rather than an enum. A code outside [allowed] means the build that
  /// wrote it shipped an asset this one does not, so falling back is the only
  /// safe reading.
  static String _parseChoice(
    String? stored,
    List<String> allowed,
    String fallback,
  ) => stored != null && allowed.contains(stored) ? stored : fallback;

  /// A set of enum members, stored as a comma-separated list of
  /// [FastLogField.toDb] names in one `meta` value.
  ///
  /// Four cases, and they are deliberately not all "fall back":
  ///
  /// - **Missing key** -> [fallback]. Never configured.
  /// - **Present but empty** -> the empty set. "Ask about nothing" is a
  ///   legitimate, reachable configuration (it is the maximal Fast log), so it
  ///   has to round-trip rather than being read as "never configured".
  /// - **Present with at least one readable member** -> those members, with
  ///   unreadable ones dropped individually. An unknown name is a field this
  ///   build does not have, and it could not be rendered anyway.
  /// - **Present, non-empty, and nothing in it readable** -> [fallback], *not*
  ///   the empty set. This is the one direction that matters: a value we cannot
  ///   read at all must degrade toward asking *more*, because the other
  ///   direction silently logs cards with details the user was never shown.
  ///
  /// Note that `save` writes every key on every call, so a member added by a
  /// future build is dropped here and then erased from the database by the next
  /// unrelated preference change. Same class of loss [_parse] already accepts,
  /// and not worth engineering around for three members.
  static Set<FastLogField> _parseFields(
    String? stored,
    Set<FastLogField> fallback,
  ) {
    if (stored == null) return fallback;
    if (stored.trim().isEmpty) return const <FastLogField>{};
    final parsed = <FastLogField>{};
    for (final part in stored.split(',')) {
      final name = part.trim();
      if (name.isEmpty) continue;
      try {
        parsed.add(FastLogField.fromDb(name));
      } on ArgumentError {
        // Drop the member, keep the rest.
      }
    }
    return parsed.isEmpty ? fallback : Set.unmodifiable(parsed);
  }

  /// Booleans are stored as `bool.toString()` (`'true'`/`'false'`). Anything
  /// else — a missing key or a hand-edited value — falls back to [fallback].
  static bool _parseBool(String? stored, bool fallback) => switch (stored) {
    'true' => true,
    'false' => false,
    _ => fallback,
  };
}

@riverpod
Future<SettingsRepository> settingsRepository(Ref ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return SettingsRepository(MetaDao(db));
}
