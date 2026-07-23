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

  AppSettings copyWith({
    CardCondition? defaultCondition,
    CardEdition? defaultEdition,
    String? language,
    AppThemeMode? themeMode,
  }) {
    return AppSettings(
      defaultCondition: defaultCondition ?? this.defaultCondition,
      defaultEdition: defaultEdition ?? this.defaultEdition,
      language: language ?? this.language,
      themeMode: themeMode ?? this.themeMode,
    );
  }
}
