import 'app_theme_mode.dart';
import 'card_condition.dart';
import 'card_edition.dart';
import 'card_language.dart';

/// The user's persisted preferences.
///
/// Hand-written and immutable, matching the `AddCardSelection`/`ScanState`
/// convention rather than freezed — this is not a database row, it is four
/// key/value pairs in the `meta` table (see `SettingsRepository`).
///
/// The const default constructor is load-bearing: it is the fallback wherever
/// settings haven't resolved yet, and the defaults it names are exactly the
/// values that were hardcoded across the logging flows before this existed.
class AppSettings {
  const AppSettings({
    this.defaultCondition = CardCondition.nearMint,
    this.defaultEdition = CardEdition.unlimited,
    this.language = kDefaultCardLanguage,
    // Dark-first, per the project's design direction.
    this.themeMode = AppThemeMode.dark,
    this.showScanDiagnostics = false,
    this.confirmBeforeDelete = true,
  });

  /// Pre-selected grade for a newly logged card, in both the scan review gate
  /// and the manual add wizard.
  final CardCondition defaultCondition;
  final CardEdition defaultEdition;

  /// Default language a newly logged card starts on, in both the scan review
  /// gate and the manual add wizard. It is only the default — each card's
  /// language is editable per entry at log time (the camera can't read it).
  final String language;

  final AppThemeMode themeMode;

  /// Whether the developer recognition-diagnostics overlay is shown on the scan
  /// screen. Off by default — it's a tuning aid, not a normal-use feature.
  final bool showScanDiagnostics;

  /// Whether removing a card from the collection (deleting, or decrementing the
  /// last copy) asks for confirmation first. On by default — a deletion can't
  /// be undone.
  final bool confirmBeforeDelete;

  AppSettings copyWith({
    CardCondition? defaultCondition,
    CardEdition? defaultEdition,
    String? language,
    AppThemeMode? themeMode,
    bool? showScanDiagnostics,
    bool? confirmBeforeDelete,
  }) {
    return AppSettings(
      defaultCondition: defaultCondition ?? this.defaultCondition,
      defaultEdition: defaultEdition ?? this.defaultEdition,
      language: language ?? this.language,
      themeMode: themeMode ?? this.themeMode,
      showScanDiagnostics: showScanDiagnostics ?? this.showScanDiagnostics,
      confirmBeforeDelete: confirmBeforeDelete ?? this.confirmBeforeDelete,
    );
  }
}
