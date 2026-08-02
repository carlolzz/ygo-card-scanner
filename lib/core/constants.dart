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
  // The rarity filter row's chip for entries whose printing carries no rarity
  // (including cards logged without a printing at all) — otherwise that group
  // would only ever be reachable under "All".
  static const String collectionFilterNoRarity = 'No rarity';
  static const String collectionSortByName = 'Name';
  static const String collectionSortByDateAdded = 'Date added';
  static const String collectionSortByQuantity = 'Quantity';
  static const String collectionSortTooltip = 'Sort by';
  static const String collectionSortDirectionTooltip = 'Toggle sort direction';

  // The filter sheet and the view-density menu, the two controls that replaced
  // the two horizontally-scrolling chip rows below the search box.
  static const String collectionFiltersButton = 'Filters';
  static const String collectionFiltersTitle = 'Filter collection';
  static const String collectionFiltersApply = 'Apply';
  static const String collectionFiltersReset = 'Reset';
  static const String collectionFiltersAdvanced = 'Advanced filters';
  static const String collectionMinifyButton = 'View';
  static const String collectionMinifyTooltip = 'Change how much detail is '
      'shown';

  static const String collectionFilterConditionLabel = 'Condition';
  static const String collectionFilterRarityLabel = 'Rarity';
  static const String collectionFilterSetLabel = 'Set';
  static const String collectionFilterEditionLabel = 'Edition';
  static const String collectionFilterLanguageLabel = 'Language';
  static const String collectionFilterLevelLabel = 'Level';
  static const String collectionFilterFrameTypeLabel = 'Card frame';
  static const String collectionFilterCardTypeLabel = 'Card type';
  // One control, because YGOPRODeck stores both in `cards.race` — the monster
  // type on a monster, the Spell/Trap type on a Spell or Trap.
  static const String collectionFilterRaceLabel =
      'Monster / Spell / Trap type';
  static const String collectionFilterAttributeLabel = 'Attribute';
  static const String collectionFilterArchetypeLabel = 'Archetype';
  static const String collectionFilterAtkLabel = 'ATK';
  static const String collectionFilterDefLabel = 'DEF';
  static const String collectionFilterMinHint = 'Min';
  static const String collectionFilterMaxHint = 'Max';
  static const String collectionQuantityLabel = 'Quantity';
  static const String collectionSetLabel = 'Set';
  // Its own detail row rather than the tail of the Set row: rarity is what
  // distinguishes two copies of the same print.
  static const String collectionRarityLabel = 'Rarity';
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
  // card's kind (Normal/Continuous/Quick-Play/Field/Equip/Ritual/Counter) —
  // which players call the Spell Type or Trap Type, naming the card's own
  // frame rather than the generic "Property".
  static const String collectionCardSpellTypeLabel = 'Spell Type';
  static const String collectionCardTrapTypeLabel = 'Trap Type';
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

  /// Shown just above the guide box. Detection crops to that box and derives
  /// Canny's thresholds from an Otsu split of it, so what the card is lying on
  /// directly decides whether its own edges survive — a patterned desk is the
  /// single biggest cause of "it won't recognise anything".
  static const String scanSurfaceHint =
      'Place the cards ideally on a monochromatic surface, preferably black';

  static const String scanDetecting = 'Point at a card';
  static const String scanReading = 'Identifying…';

  // The status banner used to say `scanDetecting` for every unresolved frame,
  // including ones where the card had been found, rectified and hashed and only
  // the *match* had failed — so the app told the user to point at a card that
  // was already centred in the reticle, with no way out and no explanation.
  // These four say what is actually wrong and, for the last one, what to do.
  static const String scanBlurry = 'Hold steady';
  static const String scanGlare = 'Too much glare — tilt the card';
  static const String scanIdentifying = 'Card found — identifying…';
  static const String scanUnidentified = 'Can\'t identify this card';
  static const String scanShowGuessesButton = 'Show best guesses';
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
  // Distinct from the camera failure above: the artwork index failing to load
  // arrives down the same stream, and calling it a camera problem sent users
  // (and this project's own debugging) after the wrong thing entirely.
  static const String scanIndexErrorTitle = 'Artwork index unavailable';
  static const String scanIndexErrorMessage =
      'The bundled card artwork index could not be read, so artwork '
      'recognition is off. Reading a passcode and searching by name both '
      'still work.';

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
  // The camera's own state, on its own line. This exists because
  // `scanDiagnosticsNoFrame` used to be shown for four different situations —
  // the reading stream still loading, the camera released, passcode mode, and
  // the literal one — which made "no camera frame yet while pointing at a card"
  // impossible to act on. `cam:` reports the camera; the lines below report
  // recognition.
  static const String scanDiagnosticsCamOpening = 'cam: opening…';
  static const String scanDiagnosticsCamStreaming = 'cam: streaming';
  static const String scanDiagnosticsCamStalled = 'cam: STALLED';
  static const String scanDiagnosticsNoFrame = 'no camera frame yet';
  static const String scanDiagnosticsNotDetected = 'no card detected';
  static const String scanDiagnosticsDetected = 'card detected';
  // A card was found and rectified but its art crop was rejected before hashing.
  // The `qual:` line below says which gate it failed.
  static const String scanDiagnosticsLowQuality = 'card detected, frame poor';
  static const String scanDiagnosticsNoCandidates = 'detected, nothing close';
  // Whether the crop was corrected to a located artwork window, or fell back to
  // the fixed ROI — the first thing to check when a real card is detected but
  // every distance is large.
  static const String scanDiagnosticsArtBoxLocked = 'art box: located';
  static const String scanDiagnosticsArtBoxFallback = 'art box: fixed roi';
  // Failure-sample capture. The scan-pipeline skill forbids adding image
  // preprocessing before there are real failure samples to test against, and
  // this is the only way to get one off the device — the rectified card exists
  // for a few milliseconds inside a detector isolate and is written nowhere.
  static const String scanCaptureButton = '[ save this frame ]';
  static const String scanCaptureSubject = 'YGO Scanner recognition sample';
  static const String scanCaptureDoneMessage = 'Frame saved — pick where to '
      'send it.';
  static const String scanCaptureNothingMessage =
      'No frame has been ranked yet.';
  static const String scanCaptureFailedMessage = 'Could not save the frame.';

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

  // The shared set/expansion search box (scan review gate, manual add wizard,
  // collection edit sheet).
  static const String setPickerSearchHint = 'Type a set name, code or rarity';
  static const String setPickerClearTooltip = 'Clear';
  static const String setPickerNoMatches = 'No set matches that.';

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
