import 'app_language.dart';
import 'app_theme_mode.dart';
import 'card_condition.dart';
import 'card_edition.dart';
import 'card_language.dart';
import 'collection_sort_by.dart';
import 'collection_view_mode.dart';
import 'fast_log_field.dart';

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
    this.appLanguage = AppLanguage.english,
    this.showScanDiagnostics = false,
    this.showScanHelp = true,
    this.keepCameraReady = true,
    this.confirmBeforeDelete = true,
    this.collectionViewMode = CollectionViewMode.minifyStandard,
    this.collectionSortBy = CollectionSortBy.name,
    this.collectionSortDescending = false,
    this.searchLanguage = kDefaultSearchLanguage,
    this.fastLogEnabled = false,
    this.fastLogFields = const <FastLogField>{},
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

  /// The language the app's own interface is written in. Not [language] (a
  /// card's printed language) and not [searchLanguage] (what names are matched
  /// in): card data stays as YGOPRODeck supplies it whichever this is.
  ///
  /// English by default, so an existing install reads exactly as before until
  /// the user picks otherwise.
  final AppLanguage appLanguage;

  /// Whether the developer recognition-diagnostics overlay is shown on the scan
  /// screen. Off by default — it's a tuning aid, not a normal-use feature.
  final bool showScanDiagnostics;

  /// Whether the "three ways to log a card" help box is shown on the scan
  /// screen. On by default — it teaches the three entry points — but it covers
  /// camera real estate a returning user no longer needs.
  final bool showScanHelp;

  /// Whether the camera is held open after leaving the scan screen, so a return
  /// to Log Cards does not pay `CameraController.initialize()` and a fresh
  /// `startImageStream` all over again (a visible second of black).
  ///
  /// On by default, because the reload is the thing the user actually reported.
  /// The cost is the other half of the trade, and it is the reason this is a
  /// switch rather than a constant: a bound camera keeps the OS privacy
  /// indicator lit while they browse the collection afterwards.
  /// `CameraService.frameProcessingEnabled` already keeps that to an idle
  /// preview rather than a running recognition pipeline.
  final bool keepCameraReady;

  /// Whether removing a card from the collection (deleting, or decrementing the
  /// last copy) asks for confirmation first. On by default — a deletion can't
  /// be undone.
  final bool confirmBeforeDelete;

  /// How densely the collection list renders. Persisted, unlike an ephemeral
  /// view toggle, because it is a browsing preference the user sets once and a
  /// reset on every app start would be a small, repeated annoyance.
  ///
  /// Deliberately has no row on the Settings screen — its control lives on the
  /// collection screen, where the effect is visible. `showScanDiagnostics` has
  /// the same shape in reverse (a Settings row *and* a scan-screen shortcut).
  ///
  /// Defaults to the captioned grid: a collection is browsed far more often
  /// than it is edited, and the full row exists for the quantity and delete
  /// controls, which are also on the detail screen. Note that this default only
  /// reaches an install that has never stored one — `SettingsRepository.save`
  /// writes every key on every call, so any device that has changed a setting
  /// keeps whatever it has.
  final CollectionViewMode collectionViewMode;

  /// How the collection list is ordered, and in which direction. Persisted for
  /// the same reason [collectionViewMode] is: it is a browsing preference the
  /// user sets deliberately, and rebuilding the collection screen — which
  /// happens every time they leave it for the home menu — used to reset it to
  /// Name/ascending.
  ///
  /// Like [collectionViewMode] these have no Settings row: the controls live in
  /// the collection screen's app bar, where the effect is visible. The rest of
  /// the collection filter is deliberately *not* persisted — a filter hides
  /// cards, and a still-narrowed collection on the next visit reads as lost
  /// data, while a sort only reorders what is already all there.
  final CollectionSortBy collectionSortBy;
  final bool collectionSortDescending;

  /// Which language the manual card search matches names in — one of
  /// [kSearchLanguages], and **not** the same thing as [language], which is the
  /// language a card in the collection is printed in.
  ///
  /// Persisted because an Italian speaker wants it every session, and with no
  /// Settings row for the same reason [collectionViewMode] has none: the
  /// dropdown sits next to the search box, where the effect is visible.
  final String searchLanguage;

  /// Whether the user has asked to be shown fewer controls when logging a card.
  ///
  /// This is the user's *intent*; [fastLogFields] is the configuration, and the
  /// two are separate fields on purpose. Folding them together (a null or empty
  /// set meaning off) would make the switch destroy the ticks, so turning Fast
  /// log off and on again would lose what was configured.
  ///
  /// Read [fastLogActive], not this, to decide whether anything is suppressed.
  final bool fastLogEnabled;

  /// The per-card details Fast log **still asks about**. Anything absent is
  /// written from its default here with no control shown.
  ///
  /// Empty by default, so the switch does its whole job at the first tap rather
  /// than needing a second trip into the configuration screen to do anything.
  final Set<FastLogField> fastLogFields;

  /// Whether Fast log is actually suppressing anything.
  ///
  /// Ticked means "still ask me", so ticking every field asks for everything and
  /// Fast log changes nothing. That degenerate configuration is treated as
  /// **off** rather than as a switch that appears to do nothing, and this getter
  /// is the only place that is decided: both logging flows and the Settings
  /// screen read it, so they cannot disagree about it.
  ///
  /// `containsAll` rather than a length comparison: the parse in
  /// `SettingsRepository` guarantees the stored set is a subset of [values], but
  /// this is correct without relying on that, and three members cost nothing.
  bool get fastLogActive =>
      fastLogEnabled && !fastLogFields.containsAll(FastLogField.values);

  /// The details a logging flow should still show a control for. Everything when
  /// Fast log is inactive, so a caller never has to ask both questions.
  ///
  /// Because "all three asked" is exactly equivalent to "Fast log inactive", a
  /// caller holding only this set can still answer whether the set/rarity picker
  /// is suppressed, without a second flag.
  Set<FastLogField> get fastLogAskedFields =>
      fastLogActive ? fastLogFields : FastLogField.values.toSet();

  AppSettings copyWith({
    CardCondition? defaultCondition,
    CardEdition? defaultEdition,
    String? language,
    AppThemeMode? themeMode,
    AppLanguage? appLanguage,
    bool? showScanDiagnostics,
    bool? showScanHelp,
    bool? keepCameraReady,
    bool? confirmBeforeDelete,
    CollectionViewMode? collectionViewMode,
    CollectionSortBy? collectionSortBy,
    bool? collectionSortDescending,
    String? searchLanguage,
    bool? fastLogEnabled,
    // No clear flag: the empty set *is* the clear.
    Set<FastLogField>? fastLogFields,
  }) {
    return AppSettings(
      defaultCondition: defaultCondition ?? this.defaultCondition,
      defaultEdition: defaultEdition ?? this.defaultEdition,
      language: language ?? this.language,
      themeMode: themeMode ?? this.themeMode,
      appLanguage: appLanguage ?? this.appLanguage,
      showScanDiagnostics: showScanDiagnostics ?? this.showScanDiagnostics,
      showScanHelp: showScanHelp ?? this.showScanHelp,
      keepCameraReady: keepCameraReady ?? this.keepCameraReady,
      confirmBeforeDelete: confirmBeforeDelete ?? this.confirmBeforeDelete,
      collectionViewMode: collectionViewMode ?? this.collectionViewMode,
      collectionSortBy: collectionSortBy ?? this.collectionSortBy,
      collectionSortDescending:
          collectionSortDescending ?? this.collectionSortDescending,
      searchLanguage: searchLanguage ?? this.searchLanguage,
      fastLogEnabled: fastLogEnabled ?? this.fastLogEnabled,
      fastLogFields: fastLogFields ?? this.fastLogFields,
    );
  }
}
