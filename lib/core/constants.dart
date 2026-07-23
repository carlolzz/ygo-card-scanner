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
  static const String collectionCardTypeLabel = 'Type';
  static const String collectionCardAttributeLabel = 'Attribute';
  // Value is the YGOPRODeck API's `race` field (Dragon/Warrior/Spellcaster/
  // etc for monsters) — labeled "Monster Type" rather than "Race" since
  // that's what players actually call it; "Type" is reserved for the API's
  // `type` field (Normal Monster/Effect Monster/Spell Card/Trap Card/etc).
  static const String collectionCardRaceLabel = 'Monster Type';
  static const String collectionCardLevelLabel = 'Level';
  static const String collectionCardAtkDefLabel = 'ATK / DEF';
  static const String collectionCardArchetypeLabel = 'Archetype';
  static const String collectionCardEffectLabel = 'Card Effect';
  static const String collectionFlavorTextLabel = 'Flavour Text';
  static const String collectionDeleteTooltip = 'Remove card';
  static const String collectionDeleteDialogTitle = 'Remove card?';
  static const String collectionDeleteDialogMessage =
      'This removes it from your collection. This cannot be undone.';
  static const String collectionDeleteDialogCancel = 'Cancel';
  static const String collectionDeleteDialogConfirm = 'Remove';

  static const String scanTitle = 'Log Cards';
  static const String scanManualTooltip = 'Search by name instead';
  static const String scanHint = 'Fit the 8-digit code inside the box';
  static const String scanDetecting = 'Point at a card';
  static const String scanReading = 'Reading…';
  static const String scanUnknownTitle = 'Not recognized';
  static const String scanUnknownMessage =
      'Couldn\'t match that passcode. Search for the card by name instead.';
  static const String scanUnknownSearchButton = 'Search by name';
  static const String scanRescanButton = 'Scan again';
  static const String scanConfirmButton = 'Add to collection';
  static const String scanSavedMessage = 'Added to your collection.';
  static const String scanPermissionTitle = 'Camera unavailable';
  static const String scanPermissionMessage =
      'Grant camera access to scan cards, or search by name instead.';
  static const String scanRetryButton = 'Retry';

  // Artwork-match fallback (step 8).
  static const String scanMatchByArtTooltip = 'Match by artwork';
  static const String scanMatchByArtButton = 'Match by artwork';
  static const String scanMatchByArtHint = 'Fit the whole card inside the box';
  static const String scanMatchingMessage = 'Matching artwork…';
  static const String scanCandidatesTitle = 'Is it one of these?';
  static const String scanCandidatesSubtitle =
      'Tap the card that matches, or search by name.';
  static const String scanNoArtMatchMessage =
      'No artwork match. Search for the card by name instead.';

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

  static const String syncFetchingMessage = 'Downloading card database…';
  static const String syncWritingMessage = 'Saving to your device…';
  static const String syncErrorMessage =
      'Could not download the card database. Check your connection and '
      'try again.';
  static const String syncRetryButton = 'Retry';
}
