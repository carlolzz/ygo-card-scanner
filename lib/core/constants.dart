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

  static const String collectionSearchHint = 'Search by name';
  static const String collectionEmptyMessage =
      'No cards in your collection yet.';
  static const String collectionFilterAll = 'All';
  static const String collectionSortByName = 'Name';
  static const String collectionSortByDateAdded = 'Date added';
  static const String collectionSortByQuantity = 'Quantity';
  static const String collectionSortDirectionTooltip = 'Toggle sort direction';
  static const String collectionQuantityLabel = 'Quantity';
  static const String collectionSetLabel = 'Set';
  static const String collectionEditionLabel = 'Edition';
  static const String collectionLanguageLabel = 'Language';
  static const String collectionByLanguageLabel = 'Copies by language';
  static const String collectionCardTypeLabel = 'Type';
  static const String collectionCardAttributeLabel = 'Attribute';
  // Value is the YGOPRODeck API's `race` field (Dragon/Warrior/Spellcaster/
  // etc for monsters) — labeled "Monster Type" rather than "Race" since
  // that's what players actually call it; "Type" is reserved for the API's
  // `type` field (Normal Monster/Effect Monster/Spell Card/Trap Card/etc).
  static const String collectionCardRaceLabel = 'Monster Type';
  // The same YGOPRODeck `race` field, but for Spell/Trap cards it holds the
  // card's property (Normal/Continuous/Quick-Play/Field/Equip/Ritual/Counter),
  // which players call the "Property" — not a Monster Type.
  static const String collectionCardPropertyLabel = 'Property';
  static const String collectionCardLevelLabel = 'Level';
  static const String collectionCardAtkDefLabel = 'ATK / DEF';
  static const String collectionCardArchetypeLabel = 'Archetype';
  static const String collectionCardEffectLabel = 'Card Effect';
  static const String collectionFlavorTextLabel = 'Flavour Text';
  static const String collectionDeleteTooltip = 'Remove card';
  static const String collectionDeleteDialogTitle = 'Remove card?';
  static const String collectionDeleteDialogMessage =
      'Are you sure you want to delete this card from your collection? '
      'This can\'t be undone.';
  static const String collectionDeleteDialogCancel = 'Cancel';
  static const String collectionDeleteDialogConfirm = 'Remove';

  // Editing an existing collection entry's details (language/set/edition/
  // condition) from the detail screen.
  static const String collectionEditTooltip = 'Edit card details';
  static const String collectionEditTitle = 'Edit card details';
  static const String collectionEditConditionLabel = 'Condition';
  static const String collectionEditEditionLabel = 'Edition';
  static const String collectionEditLanguageLabel = 'Language';
  static const String collectionEditSetLabel = 'Set';
  static const String collectionEditNoPrinting = 'No specific set';
  static const String collectionEditSaveButton = 'Save changes';
  static const String collectionEditCancelButton = 'Cancel';
  static const String collectionEditSavedMessage = 'Card details updated.';
  static const String collectionEditMergedMessage =
      'Merged with a matching entry already in your collection.';

  static const String scanTitle = 'Log Cards';
  static const String scanManualTooltip = 'Search by name instead';
  static const String scanHint = 'Fit the whole card inside the box';
  static const String scanDetecting = 'Point at a card';
  static const String scanReading = 'Identifying…';
  static const String scanUnknownTitle = 'Not recognized';
  static const String scanUnknownMessage =
      'Couldn\'t match that card. Search for it by name instead.';
  static const String scanUnknownSearchButton = 'Search by name';
  static const String scanRescanButton = 'Scan again';
  static const String scanConfirmButton = 'Add to collection';
  static const String scanSavedMessage = 'Added to your collection.';
  static const String scanPermissionTitle = 'Camera unavailable';
  static const String scanPermissionMessage =
      'Grant camera access to scan cards, or search by name instead.';
  static const String scanRetryButton = 'Retry';

  // Artwork match — the automatic primary path.
  static const String scanNotThisCardButton = 'Not the right card?';
  static const String scanCandidatesTitle = 'Is it one of these?';
  static const String scanCandidatesSubtitle =
      'Tap the card that matches, or search by name.';

  // Bottom help panel on the scan screen — the three ways to log a card.
  static const String scanHelpTitle = 'Three ways to log a card';
  static const String scanHelpArtwork =
      'Fill the box with the card — its artwork is recognised automatically.';
  static const String scanHelpCode =
      'Tap the number icon to read the printed 8-digit code instead.';
  static const String scanHelpManual =
      'Tap the keyboard icon to search for the card by name.';

  // Scan diagnostics overlay (developer aid for tuning recognition).
  static const String scanDiagnosticsTooltip = 'Toggle recognition diagnostics';
  static const String scanDiagnosticsNoFrame = 'no camera frame yet';
  static const String scanDiagnosticsNotDetected = 'no card detected';
  static const String scanDiagnosticsDetected = 'card detected';
  static const String scanDiagnosticsNoCandidates = 'detected, nothing close';

  // Passcode OCR — the on-demand fallback, and a mode that stays on until the
  // user turns it off or leaves the screen.
  static const String scanReadCodeTooltip = 'Read the 8-digit code';
  static const String scanExitCodeTooltip = 'Back to artwork recognition';
  static const String scanReadCodeButton = 'Read the 8-digit code instead';
  static const String scanReadingCodeTitle = 'Reading the code…';
  static const String scanReadingCodeMessage =
      'Center the 8-digit code in the box, about 10 cm away, and hold steady. '
      'Code reading stays on for the next card too.';
  static const String scanReadCodeCancelButton = 'Back to artwork recognition';

  // The set/expansion picker in the scan review gate.
  static const String scanSetLabel = 'Set';
  static const String scanNoSetOption = 'No specific set';

  static const String addCardTitle = 'Log Cards';
  static const String addCardSearchHint = 'Search by name';
  static const String addCardSearchEmptyMessage = 'No cards found.';
  static const String addCardPrintingTitle = 'Pick a printing';
  static const String addCardPrintingSkip = "Skip — I don't have this printing";
  static const String addCardConditionTitle = 'Condition & edition';
  static const String addCardSaveButton = 'Save to collection';
  static const String addCardSavedMessage = 'Added to your collection.';
  static const String addCardBackTooltip = 'Back';
  static const String addCardNoPrintingLabel = 'No printing selected';

  static const String settingsTitle = 'Settings';
  static const String settingsDefaultsSection = 'Defaults for new cards';
  static const String settingsDefaultsDescription =
      'Pre-selected when you scan or add a card. Language can still be changed '
      'per card as you log it.';
  static const String settingsConditionLabel = 'Condition';
  static const String settingsEditionLabel = 'Edition';
  static const String settingsLanguageLabel = 'Language';
  static const String settingsAppearanceSection = 'Appearance';
  static const String settingsThemeLabel = 'Theme';
  static const String settingsCollectionSection = 'Collection';
  static const String settingsConfirmDeleteLabel = 'Confirm before removing';
  static const String settingsConfirmDeleteDescription =
      'Ask before deleting a card or removing its last copy.';
  static const String settingsScanningSection = 'Scanning';
  static const String settingsDiagnosticsLabel = 'Show scan diagnostics';
  static const String settingsDiagnosticsDescription =
      'Overlay recognition detail (detection status and match distances) on '
      'the scan screen, for tuning. Also toggled by the bug icon while scanning.';
  static const String settingsScanHelpLabel = 'Show the how-to box';
  static const String settingsScanHelpDescription =
      'Show the "three ways to log a card" box at the bottom of the scan '
      'screen.';
  static const String settingsDatabaseSection = 'Card database';
  static const String settingsLastSyncedLabel = 'Last synced';
  static const String settingsNeverSynced = 'Never';
  static const String settingsResyncButton = 'Re-sync now';
  static const String settingsResyncDialogTitle = 'Re-sync card database?';
  static const String settingsResyncDialogMessage =
      'This downloads the full card database again — several megabytes. Your '
      'collection is not affected.';
  static const String settingsResyncDialogCancel = 'Cancel';
  static const String settingsResyncDialogConfirm = 'Re-sync';
  static const String settingsResyncDoneMessage = 'Card database updated.';

  static const String statisticsTitle = 'Statistics';
  static const String statisticsEmptyMessage =
      'No cards yet. Log some to see your stats.';
  static const String statisticsTotalCopiesLabel = 'Total copies';
  static const String statisticsDistinctCardsLabel = 'Distinct cards';
  static const String statisticsByConditionSection = 'By condition';
  static const String statisticsByLanguageSection = 'By language';
  static const String statisticsByTypeSection = 'By card type';
  static const String statisticsUnknownType = '(no type)';
  static const String statisticsExportButton = 'Export collection to CSV';
  static const String statisticsExportRunningMessage = 'Exporting…';
  static const String statisticsExportDoneMessage =
      'Exported — choose where to save it.';
  static const String statisticsExportSubject = 'YGO collection export';
  static const String statisticsExportEmptyMessage = 'Nothing to export yet.';
  static const String statisticsExportFailedMessage =
      'Export failed. Please try again.';

  static const String syncFetchingMessage = 'Downloading card database…';
  static const String syncWritingMessage = 'Saving to your device…';
  static const String syncErrorMessage =
      'Could not download the card database. Check your connection and '
      'try again.';
  static const String syncRetryButton = 'Retry';
}
