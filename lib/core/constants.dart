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
  static const String homeTileCardSearch = 'Card Search';

  static const String comingSoonMessage = 'Coming soon.';

  // Card search: browsing the whole synced database, owned or not. Distinct
  // from the add-card wizard's search, which exists to log a card.
  static const String cardSearchTitle = 'Card Search';
  static const String cardSearchHint = 'Search every card by name';
  static const String cardSearchPrompt =
      'Search the card database to read a card and check its price.';
  static const String cardSearchEmptyMessage = 'No cards match that name.';

  /// Labels the language dropdown beside both search fields. It picks the
  /// language a *name is matched in*, not the language a card is printed in
  /// (that one is `collectionLanguageLabel`, chosen per logged card).
  static const String searchLanguageLabel = 'Search language';

  // The two tabs both card screens carry.
  static const String cardTabDetails = 'Details';
  static const String cardTabPrices = 'Prices';

  static const String pricesMarketSection = 'Market prices';
  static const String pricesBySetSection = 'By set';
  static const String pricesCardmarket = 'Cardmarket';
  static const String pricesTcgplayer = 'TCGplayer';

  /// Says what these figures are, because "lowest across printings" is a very
  /// different number from what a particular copy is worth, and the difference
  /// is invisible without being told. Concretely: this is the line that
  /// explains why Blue-Eyes White Dragon reads €0.02 while the "By set" table
  /// below it lists a $74.49 printing.
  ///
  /// eBay, Amazon and CoolStuffInc were listed here until step 26. They were
  /// shown and nothing else, so they were dropped along with their columns.
  static const String pricesCardLevelNote =
      'The lowest price found across every version of this card. See "By set" '
      'below for what a particular printing is worth. Cardmarket is in euros, '
      'TCGplayer in US dollars.';

  /// Per-set prices come from `card_sets[].set_price`, which is USD only —
  /// YGOPRODeck reports Cardmarket at the card level and nowhere else.
  static const String pricesBySetNote =
      'Per-set prices are in US dollars. Cardmarket does not publish a price '
      'per printing.';
  static const String pricesNoSets = 'No set prices for this card.';
  static const String pricesUnknownCard =
      'YGOPRODeck has no pricing for this card.';
  static const String pricesErrorMessage =
      'Could not load prices. Check your connection and try again.';
  static const String pricesRetryButton = 'Retry';
  static const String pricesRefreshTooltip = 'Refresh prices';
  static const String pricesEstimateLabel = 'Value';

  /// The estimate row on the Details tab, which is a link to the Prices tab
  /// rather than a fact on its own.
  static const String pricesSeeAll = 'See all prices';
  static String pricesFetchedAt(String when) => 'Prices as of $when';

  static const String collectionSearchHint = 'Search by name';
  static const String collectionEmptyMessage =
      'No cards in your collection yet.';
  static const String collectionFilterAll = 'All';
  // The rarity filter row's chip for entries whose printing carries no rarity
  // (including cards logged without a printing at all) — otherwise that group
  // would only ever be reachable under "All".
  static const String collectionFilterNoRarity = 'No rarity';

  /// The chip that expands a filter row collapsed past
  /// `CollectionFilterTokens.chipCollapseThreshold`. Carries the total so the
  /// user knows whether it is worth opening — "Show all (12)" and
  /// "Show all (240)" are different decisions.
  static String collectionFilterShowAll(int total) => 'Show all ($total)';
  static const String collectionFilterShowLess = 'Show less';

  // The fast-browse slider's bubble, which names where a drag has reached under
  // whichever sort is active.
  static const String collectionScrollSliderLabel = 'Scroll quickly';

  /// Cards whose name starts with a digit or punctuation — "7 Colored Fish",
  /// "8-Claws Scorpion" — which are common enough to need a bucket of their own.
  static const String collectionScrollLabelOther = '#';
  static const String collectionScrollLabelMonsters = 'Monsters';
  static const String collectionScrollLabelSpells = 'Spells';
  static const String collectionScrollLabelTraps = 'Traps';

  /// Month names for the date-added bubble. Hand-written because `intl` is not
  /// in the approved stack and one label does not justify adding it.
  static const List<String> monthAbbreviations = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  static const String collectionSortByName = 'Name';
  static const String collectionSortByDateAdded = 'Date added';
  static const String collectionSortByQuantity = 'Quantity';

  /// Groups the list monsters → Spells → Traps. Shares its wording with
  /// [collectionFilterCardTypeLabel] but not its meaning: the filter matches
  /// `cards.type` exactly ("Effect Monster"), while this buckets the coarse
  /// `frame_type` — which is what "card type" means when you are looking for
  /// your Traps.
  static const String collectionSortByCardType = 'Card type';
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
  static const String collectionMinifyTooltip =
      'Change how much detail is '
      'shown';

  static const String collectionFilterConditionLabel = 'Condition';
  static const String collectionFilterRarityLabel = 'Rarity';
  static const String collectionFilterSetLabel = 'Set';
  // The set filter is a search box rather than a chip row: a collection spans
  // dozens of sets whose names are long, and the user knows the one they want.
  static const String collectionFilterSetHint = 'Type a set name';
  static const String collectionFilterEditionLabel = 'Edition';
  static const String collectionFilterLanguageLabel = 'Language';
  static const String collectionFilterLevelLabel = 'Level';
  static const String collectionFilterFrameTypeLabel = 'Card frame';
  static const String collectionFilterCardTypeLabel = 'Card type';
  // One control, because YGOPRODeck stores both in `cards.race` — the monster
  // type on a monster, the Spell/Trap type on a Spell or Trap.
  static const String collectionFilterRaceLabel = 'Monster / Spell / Trap type';
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

  // Multi-select delete. The count is composed at the call site rather than
  // interpolated here — `AppStrings` is all `const` — which also sidesteps
  // pluralisation, since the exact number is already on screen in the app bar.
  static const String collectionDeleteManyDialogTitle =
      'Remove the selected cards?';
  static const String collectionDeleteManyDialogMessage =
      'entries will be removed from your collection. This can\'t be undone.';
  static const String collectionSelectedSuffix = 'selected';
  static const String collectionSelectAllTooltip = 'Select all';
  static const String collectionSelectNoneTooltip = 'Clear selection';
  static const String collectionExitSelectionTooltip = 'Done';
  static const String collectionDeleteSelectedTooltip = 'Remove selected';
  static const String collectionDeletedManyMessage = 'entries removed.';
  static const String collectionSelectHint =
      'Hold a card to select several at once';

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

  /// Shown just above the guide box. Detection crops to that box and derives
  /// Canny's thresholds from an Otsu split of it, so what the card is lying on
  /// directly decides whether its own edges survive — a patterned desk is the
  /// single biggest cause of "it won't recognise anything".
  static const String scanSurfaceHint =
      'Place the cards ideally on a monochromatic surface.';

  static const String scanDetecting = 'Point at a card';
  static const String scanReading = 'Identifying…';

  // Whether the camera is actually up. Until it is, the banner said "Point at a
  // card" over a plain dark scrim — the app claiming to be looking while nothing
  // was streaming yet, with no way to tell a slow start from a broken one. The
  // richer `cam: streaming f=124` line exists only inside the diagnostics
  // overlay, so with diagnostics off there was no signal at all.
  static const String scanCameraOpening = 'Camera: opening…';
  static const String scanCameraAvailable = 'Camera: available';

  // The readiness line doubles as a restart control, for the one camera failure
  // nothing in the app can detect: `camera_android_camerax` blacking out the
  // preview surface while frames keep arriving (flutter/flutter#27688). Until
  // now the only documented remedy was closing the app.
  //
  // No "restarting…" message goes with it: the banner *is* the feedback. A tap
  // flips this very line back to [scanCameraOpening] and puts the spinner up,
  // which is both more visible than a SnackBar and in the place the user is
  // already looking.
  static const String scanRestartCameraTooltip = 'Restart the camera';

  // The status banner used to say `scanDetecting` for every unresolved frame,
  // including ones where the card had been found, rectified and hashed and only
  // the *match* had failed — so the app told the user to point at a card that
  // was already centred in the reticle, with no way out and no explanation.
  // These four say what is actually wrong and, for the last one, what to do.
  static const String scanBlurry = 'Hold steady';
  static const String scanGlare = 'Too much glare: tilt the card';
  static const String scanIdentifying = 'Card found, identifying…';
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
  //
  // Every hit the index ranks is now presented, so the review gate has to be
  // able to say how sure it is: past `ArtMatchTuning.autoMatchMaxDistance` the
  // card is still shown, but as a guess to be checked against the artwork.
  static const String scanLowConfidence = 'Best guess: check the picture';
  static const String scanNotThisCardButton = 'Not the right card?';
  static const String scanCandidatesTitle = 'Is it one of these?';
  static const String scanCandidatesSubtitle =
      'Tap the card that matches, or search by name.';

  // The "log again" offer, shown after a confirm.
  //
  // A card just logged is debounced until it has left the lens, which is right
  // for the automatic path and wrong for a stack of duplicates: logging the
  // second copy meant pulling the card out of frame and letting detection find
  // it all over again. This is the shortcut back into its review gate.
  static const String scanJustLoggedLabel = 'Just logged';
  static const String scanLogAgainButton = 'Log again';
  static const String scanLogAgainDismissTooltip = 'Hide';

  // Bottom help panel on the scan screen — the three ways to log a card.
  static const String scanHelpTitle = 'Three ways to log a card';
  static const String scanHelpArtwork =
      'Fill the box with the card. Its artwork is recognised automatically.';
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
  /// Appended to the frame-status line rather than occupying one of their own:
  /// they describe the same frame, and the readout's height is a hard budget.
  static const String scanDiagnosticsArtBoxLockedSuffix = ' · art box: located';
  static const String scanDiagnosticsArtBoxFallbackSuffix =
      ' · art box: fixed roi';
  // Failure-sample capture. The scan-pipeline skill forbids adding image
  // preprocessing before there are real failure samples to test against, and
  // this is the only way to get one off the device — the rectified card exists
  // for a few milliseconds inside a detector isolate and is written nowhere.
  static const String scanCaptureButton = '[ save this frame ]';
  static const String scanCaptureSubject = 'YGO Scanner recognition sample';
  static const String scanCaptureDoneMessage =
      'Frame saved. Pick where to '
      'send it.';
  // Backing out of the share sheet used to report the line above, which then
  // told the user to pick a destination they had just declined to pick — for
  // files sitting where Android will not let them browse.
  static const String scanCaptureCancelledMessage = 'Sharing cancelled.';
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
  static const String addCardPrintingSkip = "Skip: I don't have this printing";
  static const String addCardConditionTitle = 'Condition & edition';
  static const String addCardSaveButton = 'Save to collection';
  static const String addCardSavedMessage = 'Added to your collection.';
  static const String addCardBackTooltip = 'Back';
  static const String addCardNoPrintingLabel = 'No printing selected';

  static const String settingsTitle = 'Settings';
  static const String settingsDefaultsSection = 'Defaults for new cards';
  static const String settingsDefaultsDescription =
      'Pre-selected when you scan or add a card. Each one can still be changed '
      'per card as you log it, unless Fast log is skipping it below.';
  static const String settingsConditionLabel = 'Condition';
  static const String settingsEditionLabel = 'Edition';
  static const String settingsLanguageLabel = 'Language';

  // Fast log: fewer questions per card. The switch lives on the Settings
  // screen; the three ticks live on their own screen, at AppRoutes.fastLog.
  static const String settingsFastLogSection = 'Fast log';
  // Not "Fast log" again: the section header above already says that, and two
  // identical lines in a row read as a rendering fault.
  static const String settingsFastLogLabel = 'Use Fast log';
  static const String settingsFastLogDescription =
      'Ask for fewer details when you log a card. Anything you are not asked '
      'about uses your default above. The set is never asked.';
  static const String settingsFastLogConfigureLabel =
      'Choose what you are still asked';
  static const String settingsFastLogSummaryOff = 'Off. Every detail is asked.';
  static const String settingsFastLogSummaryPrefix = 'Still asked: ';
  static const String settingsFastLogSummaryAsksNothing =
      'Nothing is asked. Cards are logged with your defaults.';
  // The degenerate configuration, said plainly on the row itself rather than
  // only inside the screen the user would have to open to find out.
  static const String settingsFastLogSummaryAsksEverything =
      'Every detail is still ticked, so Fast log is doing nothing.';

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
  static const String settingsKeepCameraReadyLabel = 'Keep the camera ready';
  // The benefit is obvious once you've felt it; the cost is not, and it is the
  // reason this is a switch at all. Say both.
  static const String settingsKeepCameraReadyDescription =
      'Hold the camera open after you leave Log Cards, so it does not reload '
      'when you come back. The camera stays bound while you browse, so your '
      'phone keeps showing its camera indicator.';
  static const String settingsDatabaseSection = 'Card database';
  static const String settingsLastSyncedLabel = 'Last synced';
  static const String settingsNeverSynced = 'Never';
  static const String settingsResyncButton = 'Re-sync now';
  static const String settingsResyncDialogTitle = 'Re-sync card database?';
  static const String settingsResyncDialogMessage =
      'This downloads the full card database again (several megabytes). Your '
      'collection is not affected.';
  static const String settingsResyncDialogCancel = 'Cancel';
  static const String settingsResyncDialogConfirm = 'Re-sync';
  static const String settingsResyncDoneMessage = 'Card database updated.';

  // The Fast log configuration screen, at AppRoutes.fastLog.
  static const String fastLogTitle = 'Fast log';
  static const String fastLogIntro =
      'Tick a detail to keep being asked about it when you log a card. '
      'Unticked details use your default, with no control shown.';
  static const String fastLogDisabledNote =
      'Fast log is off. These choices apply once you turn it on in Settings.';
  static const String fastLogAllTickedNote =
      'Everything is ticked, so Fast log changes nothing. Untick a detail to '
      'start skipping it.';
  static const String fastLogSetNote =
      'The set is never asked while Fast log is on. A card with only one known '
      'printing is still logged against it.';
  // What a fast log is about to write for the details it did not ask about. A
  // confirm the user cannot read is not the review the spec requires.
  static const String fastLogSilentPrefix = 'Logging as: ';

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
      'Exported. Choose where to save it.';
  // Backing out of the share sheet used to report the line above, telling the
  // user to choose a destination they had just declined to choose — for a file
  // written to the app-documents directory, which Android does not let them
  // browse to. The file is deliberately left in place: exporting again reuses
  // it, and deleting is the one irreversible option here.
  static const String statisticsExportCancelledMessage = 'Export cancelled.';
  static const String statisticsExportSubject = 'YGO collection export';
  static const String statisticsExportFailedMessage =
      'Export failed. Please try again.';

  // CSV import. The confirmation dialog is deliberately wordy: it is the only
  // point at which the user can see what a file is about to do to a collection
  // they may have spent hours building.
  static const String statisticsImportButton = 'Import collection from CSV';
  static const String statisticsImportRunningMessage = 'Reading the file…';
  static const String statisticsImportTitle = 'Import collection';
  static const String statisticsImportNewLabel = 'new entries to add';
  static const String statisticsImportMatchedLabel =
      'already in your collection';
  static const String statisticsImportSkippedLabel =
      'rows skipped (unreadable, or a card this app does not know)';
  static const String statisticsImportUnresolvedSetLabel =
      'will be imported without their set, which was not recognised';
  static const String statisticsImportMergeQuestion =
      'For the entries you already have:';
  static const String statisticsImportKeepOption = 'Keep as one entry';
  static const String statisticsImportKeepDetail =
      'Leave your copies as they are. Re-importing a backup changes nothing.';
  static const String statisticsImportSumOption = 'Add the quantities together';
  static const String statisticsImportSumDetail =
      'Your copies and the file\'s copies add up.';
  static const String statisticsImportConfirmButton = 'Import';
  static const String statisticsImportCancelButton = 'Cancel';
  static const String statisticsImportNothingMessage =
      'That file has nothing to import.';
  static const String statisticsImportFailedMessage =
      'Could not read that file. Pick a collection CSV exported from this app.';
  static const String statisticsImportDoneMessage = 'Collection updated.';

  // Collection value. Two totals, never one: Cardmarket is euros and TCGplayer
  // is dollars, and this app carries no exchange rate.
  static const String statisticsValueSection = 'Collection value';
  static const String statisticsValueButton = 'Calculate collection value';
  static const String statisticsValueRefreshButton = 'Refresh prices';

  /// Labelled asymmetrically on purpose. Since step 26 the TCGplayer total
  /// prices each copy at the set and rarity recorded, while Cardmarket has no
  /// per-printing figure to use and stays the card-level floor — so calling
  /// both of them plain vendor names would imply they are the same measurement.
  static const String statisticsValueCardmarketLabel = 'Cardmarket (floor)';
  static const String statisticsValueTcgplayerLabel = 'TCGplayer';
  static const String statisticsValueErrorMessage =
      'Could not fetch prices. Check your connection and try again.';

  /// The honesty line beside the totals. Hidden at zero, like the import
  /// dialog's counts — a total assembled from a whole collection should not
  /// warn about a problem that does not exist.
  static String statisticsValueUnpriced(int count) =>
      '$count ${count == 1 ? 'card has' : 'cards have'} no price';
  static String statisticsValueProgress(int done, int total) =>
      'Priced $done / $total cards';

  /// The breakdown behind the two totals: one row per card, with what each is
  /// worth and what the copies of it are worth together.
  static const String statisticsValueExportButton = 'Export value breakdown';
  static const String statisticsValueExportSubject = 'YGO collection value';

  /// Says what the totals are. The two halves are no longer the same kind of
  /// figure and the note has to carry that: TCGplayer prices the printing, and
  /// Cardmarket cannot, because YGOPRODeck reports it at the card level only.
  static const String statisticsValueNote =
      'TCGplayer prices each copy at the set and rarity you recorded, falling '
      'back to the card\'s lowest printing where no set is recorded. '
      'Cardmarket is always that lowest-printing floor; no euro price exists '
      'per printing. Condition and edition are ignored on both.';

  /// How much of the valuation got a real per-printing figure rather than the
  /// card floor — the measure of how far it is worth trusting.
  static String statisticsValuePrintingPriced(int priced, int total) =>
      '$priced of $total ${total == 1 ? 'line' : 'lines'} priced at their own '
      'printing';

  static const String statisticsValueBreakdownButton = 'View breakdown';
  static const String valueBreakdownTitle = 'Value breakdown';
  static const String valueBreakdownSortByValue = 'Most valuable first';
  static const String valueBreakdownSortByName = 'By name';
  static const String valueBreakdownNoSet = 'No set recorded';

  /// Marks a row that fell back to the card-level floor. A word rather than a
  /// colour, so it survives a colour-blind reader and a greyscale screenshot.
  static const String valueBreakdownCardFloorTag = 'card floor';

  static const String syncFetchingMessage = 'Downloading card database…';
  static const String syncWritingMessage = 'Saving to your device…';
  static const String syncErrorMessage =
      'Could not download the card database. Check your connection and '
      'try again.';
  static const String syncRetryButton = 'Retry';
}
