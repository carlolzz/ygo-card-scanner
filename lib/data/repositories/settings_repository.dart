import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../models/app_settings.dart';
import '../../models/app_theme_mode.dart';
import '../../models/card_condition.dart';
import '../../models/card_edition.dart';
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
const _confirmBeforeDeleteKey = 'settings.confirm_before_delete';

/// Reads and writes [AppSettings] as key/value pairs in the existing `meta`
/// table. No schema change: `meta` has carried arbitrary keys since v1, and
/// four preferences don't justify a table (or a new storage dependency).
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
      confirmBeforeDelete: _parseBool(
        await _metaDao.get(_confirmBeforeDeleteKey),
        defaults.confirmBeforeDelete,
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
      _confirmBeforeDeleteKey,
      settings.confirmBeforeDelete.toString(),
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
