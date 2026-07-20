/// Single source of truth for user-visible strings.
///
/// All widgets must read strings from here rather than hardcoding literals,
/// so localization later is a refactor of this file, not a rewrite of the UI.
class AppStrings {
  const AppStrings._();

  static const String appName = 'YGO Scanner';

  static const String homeTileLogCards = 'Log Cards';
  static const String homeTileMyCollection = 'My Collection';
  static const String homeTileStatistics = 'Statistics';
  static const String homeTileSettings = 'Settings';

  static const String comingSoonMessage = 'Coming soon.';
}
