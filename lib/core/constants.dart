import '../models/app_language.dart';

/// Single source of truth for user-visible strings, in every interface
/// language the app ships.
///
/// All widgets must read strings from here rather than hardcoding literals.
/// Each string is written once as `_t(english, italian)`, so the two
/// translations sit side by side and a string added without its Italian is a
/// compile error rather than a silent fallback.
///
/// **These are getters, not constants**, which is why nothing reads them in a
/// `const` context: the active language is switched at runtime by
/// [AppStrings.select] (called from `SettingsController`, before the new
/// setting is published) and `App` then rebuilds every element in place, so
/// each screen re-reads its text here.
///
/// Card data from YGOPRODeck is translated **only where the game has fixed
/// terminology**: card type, frame, monster/Spell/Trap type, attribute and the
/// common rarities, through the tables at the end of this class, read via
/// `models/card_terms.dart`. Those are display labels only. Filters, queries and
/// CSV exports keep the API's raw English values.
///
/// What is deliberately *not* translated: card names and effect text (the search
/// language handles names, and the API has no Italian type data to fetch), set
/// names and archetypes (proper names, with no Italian source), the rarities
/// that are trade names, the developer-only scan diagnostics lines, and the
/// grade names on `CardCondition`, which Cardmarket uses as-is in every language.
class AppStrings {
  const AppStrings._();

  static AppLanguage _language = AppLanguage.english;

  /// The interface language currently in force.
  static AppLanguage get language => _language;

  /// Switches every string below to [language]. Takes effect on the next
  /// build, and `App` is what forces one everywhere.
  static void select(AppLanguage language) => _language = language;

  static String _t(String english, String italian) => switch (_language) {
    AppLanguage.english => english,
    AppLanguage.italian => italian,
  };

  static String get appName => _t('YGO Scanner', 'YGO Scanner');

  static String get homeTileLogCards => _t('Log Cards', 'Registra carte');
  static String get homeTileMyCollection =>
      _t('My Collection', 'La mia collezione');
  static String get homeTileStatistics => _t('Statistics', 'Statistiche');
  static String get homeTileSettings => _t('Settings', 'Impostazioni');
  static String get homeTileCardSearch => _t('Card Search', 'Cerca carte');

  static String get comingSoonMessage => _t('Coming soon.', 'In arrivo.');

  // Card search: browsing the whole synced database, owned or not. Distinct
  // from the add-card wizard's search, which exists to log a card.
  static String get cardSearchTitle => _t('Card Search', 'Cerca carte');
  static String get cardSearchHint =>
      _t('Search every card by name', 'Cerca una carta per nome');
  static String get cardSearchPrompt => _t(
    'Search the card database to read a card and check its price.',
    'Cerca nel database per leggere una carta e vederne il prezzo.',
  );
  static String get cardSearchEmptyMessage =>
      _t('No cards match that name.', 'Nessuna carta con quel nome.');

  /// Labels the language dropdown beside both search fields. It picks the
  /// language a *name is matched in*, not the language a card is printed in
  /// (that one is `collectionLanguageLabel`, chosen per logged card).
  static String get searchLanguageLabel =>
      _t('Search language', 'Lingua di ricerca');

  // The two tabs both card screens carry.
  static String get cardTabDetails => _t('Details', 'Dettagli');
  static String get cardTabPrices => _t('Prices', 'Prezzi');

  // The third tab, on the collection's card screen only: every copy held.
  static String get cardTabCopies => _t('Copies', 'Copie');
  static String collectionCopiesTotal(int count) => _t(
    'You own $count ${count == 1 ? 'copy' : 'copies'} of this card',
    'Possiedi $count ${count == 1 ? 'copia' : 'copie'} di questa carta',
  );

  /// Marks the row the screen was opened on, which is the one the app bar's edit
  /// and delete act on. With several rows on screen that needs saying.
  static String get collectionCopiesThisEntry =>
      _t('This entry', 'Questa voce');
  static String get collectionCopiesNoSet =>
      _t('No set recorded', 'Nessun set registrato');
  static String get collectionCopiesAddedLabel => _t('Added', 'Aggiunta');
  static String get collectionCopiesNotesLabel => _t('Notes', 'Note');

  static String get pricesMarketSection =>
      _t('Market prices', 'Prezzi di mercato');
  static String get pricesBySetSection => _t('By set', 'Per set');
  static String get pricesCardmarket => _t('Cardmarket', 'Cardmarket');
  static String get pricesTcgplayer => _t('TCGplayer', 'TCGplayer');

  /// Says what these figures are, because "lowest across printings" is a very
  /// different number from what a particular copy is worth, and the difference
  /// is invisible without being told. Concretely: this is the line that
  /// explains why Blue-Eyes White Dragon reads €0.02 while the "By set" table
  /// below it lists a $74.49 printing.
  ///
  /// eBay, Amazon and CoolStuffInc were listed here until step 26. They were
  /// shown and nothing else, so they were dropped along with their columns.
  static String get pricesCardLevelNote => _t(
    'The lowest price found across every version of this card. See "By set" '
        'below for what a particular printing is worth. Cardmarket is in euros, '
        'TCGplayer in US dollars.',
    'Il prezzo più basso tra tutte le versioni di questa carta. Vedi "Per set" '
        'qui sotto per il valore di una stampa specifica. Cardmarket è in euro, '
        'TCGplayer in dollari USA.',
  );

  /// Per-set prices come from `card_sets[].set_price`, which is USD only —
  /// YGOPRODeck reports Cardmarket at the card level and nowhere else.
  static String get pricesBySetNote => _t(
    'Per-set prices are in US dollars. Cardmarket does not publish a price '
        'per printing.',
    'I prezzi per set sono in dollari USA. Cardmarket non pubblica un prezzo '
        'per singola stampa.',
  );
  static String get pricesNoSets =>
      _t('No set prices for this card.', 'Nessun prezzo per set per questa carta.');
  static String get pricesUnknownCard => _t(
    'YGOPRODeck has no pricing for this card.',
    'YGOPRODeck non ha prezzi per questa carta.',
  );
  static String get pricesErrorMessage => _t(
    'Could not load prices. Check your connection and try again.',
    'Impossibile caricare i prezzi. Controlla la connessione e riprova.',
  );
  static String get pricesRetryButton => _t('Retry', 'Riprova');
  static String get pricesRefreshTooltip =>
      _t('Refresh prices', 'Aggiorna i prezzi');
  static String get pricesEstimateLabel => _t('Value', 'Valore');

  /// The estimate row on the Details tab, which is a link to the Prices tab
  /// rather than a fact on its own.
  static String get pricesSeeAll => _t('See all prices', 'Vedi tutti i prezzi');
  static String pricesFetchedAt(String when) =>
      _t('Prices as of $when', 'Prezzi aggiornati al $when');

  static String get collectionSearchHint =>
      _t('Search by name', 'Cerca per nome');
  static String get searchClearTooltip =>
      _t('Clear search', 'Cancella ricerca');
  static String get collectionEmptyMessage => _t(
    'No cards in your collection yet.',
    'Ancora nessuna carta nella tua collezione.',
  );
  static String get collectionFilterAll => _t('All', 'Tutte');

  /// [collectionFilterAll] for the groups whose Italian name is masculine (Set,
  /// Livello, Tipo, Attributo, Archetipo). "Tutte" under "Attributo" is a
  /// grammar mistake that English cannot show.
  static String get collectionFilterAllMasculine => _t('All', 'Tutti');
  // The rarity filter row's chip for entries whose printing carries no rarity
  // (including cards logged without a printing at all) — otherwise that group
  // would only ever be reachable under "All".
  static String get collectionFilterNoRarity =>
      _t('No rarity', 'Senza rarità');

  /// The chip that expands a filter row collapsed past
  /// `CollectionFilterTokens.chipCollapseThreshold`. Carries the total so the
  /// user knows whether it is worth opening — "Show all (12)" and
  /// "Show all (240)" are different decisions. "Tutto" because this one chip
  /// serves feminine and masculine groups alike.
  static String collectionFilterShowAll(int total) =>
      _t('Show all ($total)', 'Mostra tutto ($total)');
  static String get collectionFilterShowLess => _t('Show less', 'Mostra meno');

  // The fast-browse slider's bubble, which names where a drag has reached under
  // whichever sort is active.
  static String get collectionScrollSliderLabel =>
      _t('Scroll quickly', 'Scorri velocemente');

  /// Cards whose name starts with a digit or punctuation — "7 Colored Fish",
  /// "8-Claws Scorpion" — which are common enough to need a bucket of their own.
  static String get collectionScrollLabelOther => _t('#', '#');
  static String get collectionScrollLabelMonsters => _t('Monsters', 'Mostri');
  static String get collectionScrollLabelSpells => _t('Spells', 'Magie');
  static String get collectionScrollLabelTraps => _t('Traps', 'Trappole');

  /// Month names for the date-added bubble. Hand-written because `intl` is not
  /// in the approved stack and one label does not justify adding it.
  static List<String> get monthAbbreviations => switch (_language) {
    AppLanguage.english => const [
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
    ],
    AppLanguage.italian => const [
      'gen',
      'feb',
      'mar',
      'apr',
      'mag',
      'giu',
      'lug',
      'ago',
      'set',
      'ott',
      'nov',
      'dic',
    ],
  };
  static String get collectionSortByName => _t('Name', 'Nome');
  static String get collectionSortByDateAdded =>
      _t('Date added', 'Data di aggiunta');
  static String get collectionSortByQuantity => _t('Quantity', 'Quantità');

  /// Groups the list monsters → Spells → Traps. Shares its wording with
  /// [collectionFilterCardTypeLabel] but not its meaning: the filter matches
  /// `cards.type` exactly ("Effect Monster"), while this buckets the coarse
  /// `frame_type` — which is what "card type" means when you are looking for
  /// your Traps.
  static String get collectionSortByCardType =>
      _t('Card type', 'Tipo di carta');
  static String get collectionSortTooltip => _t('Sort by', 'Ordina per');
  static String get collectionSortDirectionTooltip =>
      _t('Toggle sort direction', 'Inverti l\'ordine');

  // The filter sheet and the view-density menu, the two controls that replaced
  // the two horizontally-scrolling chip rows below the search box.
  static String get collectionFiltersButton => _t('Filters', 'Filtri');
  static String get collectionFiltersTitle =>
      _t('Filter collection', 'Filtra la collezione');
  static String get collectionFiltersApply => _t('Apply', 'Applica');
  static String get collectionFiltersReset => _t('Reset', 'Azzera');
  static String get collectionFiltersAdvanced =>
      _t('Advanced filters', 'Filtri avanzati');
  static String get collectionMinifyButton => _t('View', 'Vista');
  static String get collectionMinifyTooltip => _t(
    'Change how much detail is shown',
    'Cambia quanti dettagli mostrare',
  );

  static String get collectionFilterConditionLabel =>
      _t('Condition', 'Condizione');
  static String get collectionFilterRarityLabel => _t('Rarity', 'Rarità');
  static String get collectionFilterSetLabel => _t('Set', 'Set');
  // The set filter is a search box rather than a chip row: a collection spans
  // dozens of sets whose names are long, and the user knows the one they want.
  static String get collectionFilterSetHint =>
      _t('Type a set name', 'Scrivi il nome di un set');
  static String get collectionFilterEditionLabel => _t('Edition', 'Edizione');
  static String get collectionFilterLanguageLabel => _t('Language', 'Lingua');
  static String get collectionFilterLevelLabel => _t('Level', 'Livello');
  static String get collectionFilterFrameTypeLabel =>
      _t('Card frame', 'Cornice della carta');
  static String get collectionFilterCardTypeLabel =>
      _t('Card type', 'Tipo di carta');
  // One control, because YGOPRODeck stores both in `cards.race` — the monster
  // type on a monster, the Spell/Trap type on a Spell or Trap.
  static String get collectionFilterRaceLabel => _t(
    'Monster / Spell / Trap type',
    'Tipo di Mostro / Magia / Trappola',
  );
  static String get collectionFilterAttributeLabel =>
      _t('Attribute', 'Attributo');
  static String get collectionFilterArchetypeLabel =>
      _t('Archetype', 'Archetipo');
  static String get collectionFilterAtkLabel => _t('ATK', 'ATK');
  static String get collectionFilterDefLabel => _t('DEF', 'DEF');
  static String get collectionFilterMinHint => _t('Min', 'Min');
  static String get collectionFilterMaxHint => _t('Max', 'Max');
  static String get collectionQuantityLabel => _t('Quantity', 'Quantità');
  static String get collectionSetLabel => _t('Set', 'Set');
  // Its own detail row rather than the tail of the Set row: rarity is what
  // distinguishes two copies of the same print.
  static String get collectionRarityLabel => _t('Rarity', 'Rarità');
  static String get collectionEditionLabel => _t('Edition', 'Edizione');
  static String get collectionLanguageLabel => _t('Language', 'Lingua');
  static String get collectionByLanguageLabel =>
      _t('Copies by language', 'Copie per lingua');
  static String get collectionCardTypeLabel => _t('Type', 'Tipo');
  static String get collectionCardAttributeLabel =>
      _t('Attribute', 'Attributo');
  // Value is the YGOPRODeck API's `race` field (Dragon/Warrior/Spellcaster/
  // etc for monsters) — labeled "Monster Type" rather than "Race" since
  // that's what players actually call it; "Type" is reserved for the API's
  // `type` field (Normal Monster/Effect Monster/Spell Card/Trap Card/etc).
  static String get collectionCardRaceLabel =>
      _t('Monster Type', 'Tipo di Mostro');
  // The same YGOPRODeck `race` field, but for Spell/Trap cards it holds the
  // card's kind (Normal/Continuous/Quick-Play/Field/Equip/Ritual/Counter) —
  // which players call the Spell Type or Trap Type, naming the card's own
  // frame rather than the generic "Property".
  static String get collectionCardSpellTypeLabel =>
      _t('Spell Type', 'Tipo di Magia');
  static String get collectionCardTrapTypeLabel =>
      _t('Trap Type', 'Tipo di Trappola');
  static String get collectionCardLevelLabel => _t('Level', 'Livello');
  static String get collectionCardAtkDefLabel => _t('ATK / DEF', 'ATK / DEF');
  static String get collectionCardArchetypeLabel =>
      _t('Archetype', 'Archetipo');
  static String get collectionCardEffectLabel =>
      _t('Card Effect', 'Effetto della carta');
  static String get collectionFlavorTextLabel =>
      _t('Flavour Text', 'Testo descrittivo');
  static String get collectionDeleteTooltip =>
      _t('Remove card', 'Rimuovi carta');
  static String get collectionDeleteDialogTitle =>
      _t('Remove card?', 'Rimuovere la carta?');
  static String get collectionDeleteDialogMessage => _t(
    'Are you sure you want to delete this card from your collection? '
        'This can\'t be undone.',
    'Vuoi davvero eliminare questa carta dalla tua collezione? '
        'L\'operazione non si può annullare.',
  );
  static String get collectionDeleteDialogCancel => _t('Cancel', 'Annulla');
  static String get collectionDeleteDialogConfirm => _t('Remove', 'Rimuovi');

  // Multi-select delete. The count is composed at the call site, number
  // first, which reads correctly in both languages and sidesteps
  // pluralisation, since the exact number is already on screen in the app bar.
  static String get collectionDeleteManyDialogTitle =>
      _t('Remove the selected cards?', 'Rimuovere le carte selezionate?');
  static String get collectionDeleteManyDialogMessage => _t(
    'entries will be removed from your collection. This can\'t be undone.',
    'voci verranno rimosse dalla tua collezione. L\'operazione non si può '
        'annullare.',
  );
  static String get collectionSelectedSuffix => _t('selected', 'selezionate');
  static String get collectionSelectAllTooltip =>
      _t('Select all', 'Seleziona tutto');
  static String get collectionSelectNoneTooltip =>
      _t('Clear selection', 'Deseleziona tutto');
  static String get collectionExitSelectionTooltip => _t('Done', 'Fatto');
  static String get collectionDeleteSelectedTooltip =>
      _t('Remove selected', 'Rimuovi selezionate');
  static String get collectionDeletedManyMessage =>
      _t('entries removed.', 'voci rimosse.');
  static String get collectionSelectHint => _t(
    'Hold a card to select several at once',
    'Tieni premuta una carta per selezionarne più di una',
  );

  // Editing an existing collection entry's details (language/set/edition/
  // condition) from the detail screen.
  static String get collectionEditTooltip =>
      _t('Edit card details', 'Modifica i dettagli');
  static String get collectionEditTitle =>
      _t('Edit card details', 'Modifica i dettagli');
  static String get collectionEditConditionLabel =>
      _t('Condition', 'Condizione');
  static String get collectionEditEditionLabel => _t('Edition', 'Edizione');
  static String get collectionEditLanguageLabel => _t('Language', 'Lingua');
  static String get collectionEditSetLabel => _t('Set', 'Set');
  static String get collectionEditNoPrinting =>
      _t('No specific set', 'Nessun set specifico');
  static String get collectionEditSaveButton =>
      _t('Save changes', 'Salva modifiche');
  static String get collectionEditCancelButton => _t('Cancel', 'Annulla');
  static String get collectionEditSavedMessage =>
      _t('Card details updated.', 'Dettagli della carta aggiornati.');
  static String get collectionEditMergedMessage => _t(
    'Merged with a matching entry already in your collection.',
    'Unita a una voce identica già presente nella tua collezione.',
  );

  static String get scanTitle => _t('Log Cards', 'Registra carte');
  static String get scanManualTooltip =>
      _t('Search by name instead', 'Cerca per nome');

  /// Shown just above the guide box. Detection crops to that box and derives
  /// Canny's thresholds from an Otsu split of it, so what the card is lying on
  /// directly decides whether its own edges survive — a patterned desk is the
  /// single biggest cause of "it won't recognise anything".
  static String get scanSurfaceHint => _t(
    'Place the cards ideally on a monochromatic surface.',
    'Appoggia le carte, se possibile, su una superficie in tinta unita.',
  );

  static String get scanDetecting =>
      _t('Point at a card', 'Inquadra una carta');
  static String get scanReading => _t('Identifying…', 'Riconoscimento…');

  // Whether the camera is actually up. Until it is, the banner said "Point at a
  // card" over a plain dark scrim — the app claiming to be looking while nothing
  // was streaming yet, with no way to tell a slow start from a broken one. The
  // richer `cam: streaming f=124` line exists only inside the diagnostics
  // overlay, so with diagnostics off there was no signal at all.
  static String get scanCameraOpening =>
      _t('Camera: opening…', 'Fotocamera: avvio…');
  static String get scanCameraAvailable =>
      _t('Camera: available', 'Fotocamera: pronta');

  // The readiness line doubles as a restart control, for the one camera failure
  // nothing in the app can detect: `camera_android_camerax` blacking out the
  // preview surface while frames keep arriving (flutter/flutter#27688). Until
  // now the only documented remedy was closing the app.
  //
  // No "restarting…" message goes with it: the banner *is* the feedback. A tap
  // flips this very line back to [scanCameraOpening] and puts the spinner up,
  // which is both more visible than a SnackBar and in the place the user is
  // already looking.
  static String get scanRestartCameraTooltip =>
      _t('Restart the camera', 'Riavvia la fotocamera');

  // The status banner used to say `scanDetecting` for every unresolved frame,
  // including ones where the card had been found, rectified and hashed and only
  // the *match* had failed — so the app told the user to point at a card that
  // was already centred in the reticle, with no way out and no explanation.
  // These four say what is actually wrong and, for the last one, what to do.
  static String get scanBlurry => _t('Hold steady', 'Tieni fermo');
  static String get scanGlare => _t(
    'Too much glare: tilt the card',
    'Troppi riflessi: inclina la carta',
  );
  static String get scanIdentifying =>
      _t('Card found, identifying…', 'Carta trovata, riconoscimento…');
  static String get scanUnidentified =>
      _t('Can\'t identify this card', 'Impossibile riconoscere la carta');
  static String get scanShowGuessesButton =>
      _t('Show best guesses', 'Mostra le ipotesi migliori');
  static String get scanUnknownTitle => _t('Not recognized', 'Non riconosciuta');
  static String get scanUnknownMessage => _t(
    'Couldn\'t match that card. Search for it by name instead.',
    'Non è stato possibile riconoscere la carta. Cercala per nome.',
  );
  static String get scanUnknownSearchButton =>
      _t('Search by name', 'Cerca per nome');
  static String get scanRescanButton => _t('Scan again', 'Scansiona di nuovo');
  static String get scanConfirmButton =>
      _t('Add to collection', 'Aggiungi alla collezione');
  static String get scanSavedMessage =>
      _t('Added to your collection.', 'Aggiunta alla tua collezione.');
  static String get scanPermissionTitle =>
      _t('Camera unavailable', 'Fotocamera non disponibile');
  static String get scanPermissionMessage => _t(
    'Grant camera access to scan cards, or search by name instead.',
    'Consenti l\'accesso alla fotocamera per scansionare le carte, oppure '
        'cercale per nome.',
  );
  static String get scanRetryButton => _t('Retry', 'Riprova');
  // Distinct from the camera failure above: the artwork index failing to load
  // arrives down the same stream, and calling it a camera problem sent users
  // (and this project's own debugging) after the wrong thing entirely.
  static String get scanIndexErrorTitle =>
      _t('Artwork index unavailable', 'Indice delle illustrazioni non disponibile');
  static String get scanIndexErrorMessage => _t(
    'The bundled card artwork index could not be read, so artwork '
        'recognition is off. Reading a passcode and searching by name both '
        'still work.',
    'Non è stato possibile leggere l\'indice delle illustrazioni incluso '
        'nell\'app, quindi il riconoscimento dell\'illustrazione è disattivato. '
        'La lettura del codice e la ricerca per nome funzionano comunque.',
  );

  // Artwork match — the automatic primary path.
  //
  // Every hit the index ranks is now presented, so the review gate has to be
  // able to say how sure it is: past `ArtMatchTuning.autoMatchMaxDistance` the
  // card is still shown, but as a guess to be checked against the artwork.
  static String get scanLowConfidence => _t(
    'Best guess: check the picture',
    'Ipotesi migliore: controlla l\'immagine',
  );
  static String get scanNotThisCardButton =>
      _t('Not the right card?', 'Non è la carta giusta?');
  static String get scanCandidatesTitle =>
      _t('Is it one of these?', 'È una di queste?');
  static String get scanCandidatesSubtitle => _t(
    'Tap the card that matches, or search by name.',
    'Tocca la carta corrispondente, oppure cercala per nome.',
  );

  // The "log again" offer, shown after a confirm.
  //
  // A card just logged is debounced until it has left the lens, which is right
  // for the automatic path and wrong for a stack of duplicates: logging the
  // second copy meant pulling the card out of frame and letting detection find
  // it all over again. This is the shortcut back into its review gate.
  static String get scanJustLoggedLabel =>
      _t('Just logged', 'Appena registrata');
  static String get scanLogAgainButton => _t('Log again', 'Registra ancora');
  static String get scanLogAgainDismissTooltip => _t('Hide', 'Nascondi');

  // Bottom help panel on the scan screen — the three ways to log a card.
  static String get scanHelpTitle =>
      _t('Three ways to log a card', 'Tre modi per registrare una carta');
  static String get scanHelpArtwork => _t(
    'Fill the box with the card. Its artwork is recognised automatically.',
    'Riempi il riquadro con la carta. L\'illustrazione viene riconosciuta da '
        'sola.',
  );
  static String get scanHelpCode => _t(
    'Tap the number icon to read the printed 8-digit code instead.',
    'Tocca l\'icona dei numeri per leggere invece il codice di 8 cifre.',
  );
  static String get scanHelpManual => _t(
    'Tap the keyboard icon to search for the card by name.',
    'Tocca l\'icona della tastiera per cercare la carta per nome.',
  );

  // Scan diagnostics overlay (developer aid for tuning recognition). The
  // tooltip is translated; the readout lines themselves are a tuning tool and
  // stay in English in both languages, matching the `qual:`/`det:`/`frame:`
  // lines built outside this file.
  static String get scanDiagnosticsTooltip => _t(
    'Toggle recognition diagnostics',
    'Mostra/nascondi la diagnostica del riconoscimento',
  );
  // The camera's own state, on its own line. This exists because
  // `scanDiagnosticsNoFrame` used to be shown for four different situations —
  // the reading stream still loading, the camera released, passcode mode, and
  // the literal one — which made "no camera frame yet while pointing at a card"
  // impossible to act on. `cam:` reports the camera; the lines below report
  // recognition.
  static String get scanDiagnosticsCamOpening => 'cam: opening…';
  static String get scanDiagnosticsCamStreaming => 'cam: streaming';
  static String get scanDiagnosticsCamStalled => 'cam: STALLED';
  static String get scanDiagnosticsNoFrame => 'no camera frame yet';
  static String get scanDiagnosticsNotDetected => 'no card detected';
  static String get scanDiagnosticsDetected => 'card detected';
  // A card was found and rectified but its art crop was rejected before hashing.
  // The `qual:` line below says which gate it failed.
  static String get scanDiagnosticsLowQuality => 'card detected, frame poor';
  static String get scanDiagnosticsNoCandidates => 'detected, nothing close';
  // Whether the crop was corrected to a located artwork window, or fell back to
  // the fixed ROI — the first thing to check when a real card is detected but
  // every distance is large.
  /// Appended to the frame-status line rather than occupying one of their own:
  /// they describe the same frame, and the readout's height is a hard budget.
  static String get scanDiagnosticsArtBoxLockedSuffix => ' · art box: located';
  static String get scanDiagnosticsArtBoxFallbackSuffix =>
      ' · art box: fixed roi';
  // Failure-sample capture. The scan-pipeline skill forbids adding image
  // preprocessing before there are real failure samples to test against, and
  // this is the only way to get one off the device — the rectified card exists
  // for a few milliseconds inside a detector isolate and is written nowhere.
  static String get scanCaptureButton =>
      _t('[ save this frame ]', '[ salva questo fotogramma ]');
  static String get scanCaptureSubject => _t(
    'YGO Scanner recognition sample',
    'Campione di riconoscimento YGO Scanner',
  );
  static String get scanCaptureDoneMessage => _t(
    'Frame saved. Pick where to send it.',
    'Fotogramma salvato. Scegli dove inviarlo.',
  );
  // Backing out of the share sheet used to report the line above, which then
  // told the user to pick a destination they had just declined to pick — for
  // files sitting where Android will not let them browse.
  static String get scanCaptureCancelledMessage =>
      _t('Sharing cancelled.', 'Condivisione annullata.');
  static String get scanCaptureNothingMessage => _t(
    'No frame has been ranked yet.',
    'Nessun fotogramma è stato ancora analizzato.',
  );
  static String get scanCaptureFailedMessage => _t(
    'Could not save the frame.',
    'Impossibile salvare il fotogramma.',
  );

  // Passcode OCR — the on-demand fallback, and a mode that stays on until the
  // user turns it off or leaves the screen.
  static String get scanReadCodeTooltip =>
      _t('Read the 8-digit code', 'Leggi il codice di 8 cifre');
  static String get scanExitCodeTooltip => _t(
    'Back to artwork recognition',
    'Torna al riconoscimento dell\'illustrazione',
  );
  static String get scanReadCodeButton => _t(
    'Read the 8-digit code instead',
    'Leggi invece il codice di 8 cifre',
  );
  static String get scanReadingCodeTitle =>
      _t('Reading the code…', 'Lettura del codice…');
  static String get scanReadingCodeMessage => _t(
    'Center the 8-digit code in the box, about 10 cm away, and hold steady. '
        'Code reading stays on for the next card too.',
    'Centra il codice di 8 cifre nel riquadro, a circa 10 cm, e tieni fermo. '
        'La lettura del codice resta attiva anche per la carta successiva.',
  );
  static String get scanReadCodeCancelButton => _t(
    'Back to artwork recognition',
    'Torna al riconoscimento dell\'illustrazione',
  );

  // The set/expansion picker in the scan review gate.
  static String get scanSetLabel => _t('Set', 'Set');
  static String get scanNoSetOption =>
      _t('No specific set', 'Nessun set specifico');

  // The shared set/expansion search box (scan review gate, manual add wizard,
  // collection edit sheet).
  static String get setPickerSearchHint => _t(
    'Type a set name, code or rarity',
    'Scrivi nome, codice o rarità del set',
  );
  static String get setPickerClearTooltip => _t('Clear', 'Cancella');
  static String get setPickerNoMatches =>
      _t('No set matches that.', 'Nessun set corrisponde.');

  static String get addCardTitle => _t('Log Cards', 'Registra carte');
  static String get addCardSearchHint => _t('Search by name', 'Cerca per nome');
  static String get addCardSearchEmptyMessage =>
      _t('No cards found.', 'Nessuna carta trovata.');
  static String get addCardPrintingTitle =>
      _t('Pick a printing', 'Scegli una stampa');
  static String get addCardPrintingSkip => _t(
    "Skip: I don't have this printing",
    'Salta: non ho questa stampa',
  );
  static String get addCardConditionTitle =>
      _t('Condition & edition', 'Condizione ed edizione');
  static String get addCardSaveButton =>
      _t('Save to collection', 'Salva nella collezione');
  static String get addCardSavedMessage =>
      _t('Added to your collection.', 'Aggiunta alla tua collezione.');
  static String get addCardBackTooltip => _t('Back', 'Indietro');
  static String get addCardNoPrintingLabel =>
      _t('No printing selected', 'Nessuna stampa selezionata');

  static String get settingsTitle => _t('Settings', 'Impostazioni');
  static String get settingsDefaultsSection =>
      _t('Defaults for new cards', 'Valori predefiniti per le nuove carte');
  static String get settingsDefaultsDescription => _t(
    'Pre-selected when you scan or add a card. Each one can still be changed '
        'per card as you log it, unless Fast log is skipping it below.',
    'Preselezionati quando scansioni o aggiungi una carta. Puoi comunque '
        'cambiarli carta per carta, a meno che la Registrazione rapida qui sotto '
        'non li salti.',
  );
  static String get settingsConditionLabel => _t('Condition', 'Condizione');
  static String get settingsEditionLabel => _t('Edition', 'Edizione');
  static String get settingsLanguageLabel => _t('Language', 'Lingua');

  // Fast log: fewer questions per card. The switch lives on the Settings
  // screen; the three ticks live on their own screen, at AppRoutes.fastLog.
  static String get settingsFastLogSection =>
      _t('Fast log', 'Registrazione rapida');
  // Not "Fast log" again: the section header above already says that, and two
  // identical lines in a row read as a rendering fault.
  static String get settingsFastLogLabel =>
      _t('Use Fast log', 'Usa la registrazione rapida');
  static String get settingsFastLogDescription => _t(
    'Ask for fewer details when you log a card. Anything you are not asked '
        'about uses your default above. The set is never asked.',
    'Chiede meno dettagli quando registri una carta. Ciò che non ti viene '
        'chiesto usa il valore predefinito qui sopra. Il set non viene mai '
        'chiesto.',
  );
  static String get settingsFastLogConfigureLabel =>
      _t('Choose what you are still asked', 'Scegli cosa ti viene ancora chiesto');
  static String get settingsFastLogSummaryOff => _t(
    'Off. Every detail is asked.',
    'Disattivata. Ogni dettaglio viene chiesto.',
  );
  static String get settingsFastLogSummaryPrefix =>
      _t('Still asked: ', 'Ancora chiesti: ');
  static String get settingsFastLogSummaryAsksNothing => _t(
    'Nothing is asked. Cards are logged with your defaults.',
    'Non viene chiesto nulla. Le carte vengono registrate con i tuoi valori '
        'predefiniti.',
  );
  // The degenerate configuration, said plainly on the row itself rather than
  // only inside the screen the user would have to open to find out.
  static String get settingsFastLogSummaryAsksEverything => _t(
    'Every detail is still ticked, so Fast log is doing nothing.',
    'Tutti i dettagli sono ancora spuntati, quindi la registrazione rapida non '
        'cambia nulla.',
  );

  static String get settingsAppearanceSection => _t('Appearance', 'Aspetto');
  static String get settingsThemeLabel => _t('Theme', 'Tema');

  /// Labels the interface-language chips. The chips themselves name each
  /// language in itself ("English", "Italiano") — see `AppLanguage.label`.
  static String get settingsAppLanguageLabel =>
      _t('App language', 'Lingua dell\'app');
  static String get settingsCollectionSection => _t('Collection', 'Collezione');
  static String get settingsConfirmDeleteLabel =>
      _t('Confirm before removing', 'Conferma prima di rimuovere');
  static String get settingsConfirmDeleteDescription => _t(
    'Ask before deleting a card or removing its last copy.',
    'Chiedi conferma prima di eliminare una carta o rimuoverne l\'ultima '
        'copia.',
  );
  static String get settingsScanningSection => _t('Scanning', 'Scansione');
  static String get settingsDiagnosticsLabel =>
      _t('Show scan diagnostics', 'Mostra la diagnostica di scansione');
  static String get settingsDiagnosticsDescription => _t(
    'Overlay recognition detail (detection status and match distances) on '
        'the scan screen, for tuning. Also toggled by the bug icon while scanning.',
    'Sovrappone i dettagli del riconoscimento (stato del rilevamento e '
        'distanze) alla schermata di scansione, per la taratura. Si attiva '
        'anche con l\'icona dell\'insetto durante la scansione.',
  );
  static String get settingsScanHelpLabel =>
      _t('Show the how-to box', 'Mostra il riquadro di aiuto');
  static String get settingsScanHelpDescription => _t(
    'Show the "three ways to log a card" box at the bottom of the scan '
        'screen.',
    'Mostra il riquadro "tre modi per registrare una carta" in fondo alla '
        'schermata di scansione.',
  );
  static String get settingsKeepCameraReadyLabel =>
      _t('Keep the camera ready', 'Tieni pronta la fotocamera');
  // The benefit is obvious once you've felt it; the cost is not, and it is the
  // reason this is a switch at all. Say both.
  static String get settingsKeepCameraReadyDescription => _t(
    'Hold the camera open after you leave Log Cards, so it does not reload '
        'when you come back. The camera stays bound while you browse, so your '
        'phone keeps showing its camera indicator.',
    'Tiene aperta la fotocamera dopo che esci da Registra carte, così non si '
        'ricarica quando torni. La fotocamera resta in uso mentre navighi, '
        'quindi il telefono continua a mostrarne l\'indicatore.',
  );
  static String get settingsDatabaseSection =>
      _t('Card database', 'Database delle carte');
  static String get settingsLastSyncedLabel =>
      _t('Last synced', 'Ultima sincronizzazione');
  static String get settingsNeverSynced => _t('Never', 'Mai');
  static String get settingsResyncButton =>
      _t('Re-sync now', 'Sincronizza ora');
  static String get settingsResyncDialogTitle =>
      _t('Re-sync card database?', 'Sincronizzare di nuovo il database?');
  static String get settingsResyncDialogMessage => _t(
    'This downloads the full card database again (several megabytes). Your '
        'collection is not affected.',
    'Il database completo delle carte verrà scaricato di nuovo (diversi '
        'megabyte). La tua collezione non viene toccata.',
  );
  static String get settingsResyncDialogCancel => _t('Cancel', 'Annulla');
  static String get settingsResyncDialogConfirm =>
      _t('Re-sync', 'Sincronizza');
  static String get settingsResyncDoneMessage =>
      _t('Card database updated.', 'Database delle carte aggiornato.');

  // The Fast log configuration screen, at AppRoutes.fastLog.
  static String get fastLogTitle => _t('Fast log', 'Registrazione rapida');
  static String get fastLogIntro => _t(
    'Tick a detail to keep being asked about it when you log a card. '
        'Unticked details use your default, with no control shown.',
    'Spunta un dettaglio per continuare a sceglierlo quando registri una '
        'carta. I dettagli non spuntati usano il valore predefinito, senza '
        'mostrare alcun controllo.',
  );
  static String get fastLogDisabledNote => _t(
    'Fast log is off. These choices apply once you turn it on in Settings.',
    'La registrazione rapida è disattivata. Queste scelte valgono quando la '
        'attivi nelle Impostazioni.',
  );
  static String get fastLogAllTickedNote => _t(
    'Everything is ticked, so Fast log changes nothing. Untick a detail to '
        'start skipping it.',
    'È tutto spuntato, quindi la registrazione rapida non cambia nulla. '
        'Togli la spunta a un dettaglio per saltarlo.',
  );
  static String get fastLogSetNote => _t(
    'The set is never asked while Fast log is on. A card with only one known '
        'printing is still logged against it.',
    'Con la registrazione rapida il set non viene mai chiesto. Una carta con '
        'una sola stampa conosciuta viene comunque registrata con quella.',
  );
  // What a fast log is about to write for the details it did not ask about. A
  // confirm the user cannot read is not the review the spec requires.
  static String get fastLogSilentPrefix =>
      _t('Logging as: ', 'Registrata come: ');

  static String get statisticsTitle => _t('Statistics', 'Statistiche');
  static String get statisticsEmptyMessage => _t(
    'No cards yet. Log some to see your stats.',
    'Ancora nessuna carta. Registrane qualcuna per vedere le statistiche.',
  );
  static String get statisticsTotalCopiesLabel =>
      _t('Total copies', 'Copie totali');
  static String get statisticsDistinctCardsLabel =>
      _t('Distinct cards', 'Carte diverse');
  static String get statisticsByConditionSection =>
      _t('By condition', 'Per condizione');
  static String get statisticsByLanguageSection =>
      _t('By language', 'Per lingua');
  static String get statisticsByTypeSection =>
      _t('By card type', 'Per tipo di carta');
  static String get statisticsUnknownType => _t('(no type)', '(nessun tipo)');
  static String get statisticsExportButton =>
      _t('Export collection to CSV', 'Esporta la collezione in CSV');
  static String get statisticsExportRunningMessage =>
      _t('Exporting…', 'Esportazione…');
  static String get statisticsExportDoneMessage => _t(
    'Exported. Choose where to save it.',
    'Esportata. Scegli dove salvarla.',
  );
  // Backing out of the share sheet used to report the line above, telling the
  // user to choose a destination they had just declined to choose — for a file
  // written to the app-documents directory, which Android does not let them
  // browse to. The file is deliberately left in place: exporting again reuses
  // it, and deleting is the one irreversible option here.
  static String get statisticsExportCancelledMessage =>
      _t('Export cancelled.', 'Esportazione annullata.');
  static String get statisticsExportSubject =>
      _t('YGO collection export', 'Esportazione collezione YGO');
  static String get statisticsExportFailedMessage => _t(
    'Export failed. Please try again.',
    'Esportazione non riuscita. Riprova.',
  );

  // CSV import. The confirmation dialog is deliberately wordy: it is the only
  // point at which the user can see what a file is about to do to a collection
  // they may have spent hours building.
  static String get statisticsImportButton =>
      _t('Import collection from CSV', 'Importa la collezione da CSV');
  static String get statisticsImportRunningMessage =>
      _t('Reading the file…', 'Lettura del file…');
  static String get statisticsImportTitle =>
      _t('Import collection', 'Importa collezione');
  // The four counts below are drawn after a bold number, so each reads as the
  // rest of a sentence that starts with it — in both languages.
  static String get statisticsImportNewLabel =>
      _t('new entries to add', 'nuove voci da aggiungere');
  static String get statisticsImportMatchedLabel =>
      _t('already in your collection', 'già presenti nella tua collezione');
  static String get statisticsImportSkippedLabel => _t(
    'rows skipped (unreadable, or a card this app does not know)',
    'righe saltate (illeggibili, o carte che l\'app non conosce)',
  );
  static String get statisticsImportUnresolvedSetLabel => _t(
    'will be imported without their set, which was not recognised',
    'verranno importate senza set, perché non è stato riconosciuto',
  );
  static String get statisticsImportMergeQuestion =>
      _t('For the entries you already have:', 'Per le voci che hai già:');
  static String get statisticsImportKeepOption =>
      _t('Keep as one entry', 'Mantieni una sola voce');
  static String get statisticsImportKeepDetail => _t(
    'Leave your copies as they are. Re-importing a backup changes nothing.',
    'Lascia le tue copie come sono. Reimportare un backup non cambia nulla.',
  );
  static String get statisticsImportSumOption =>
      _t('Add the quantities together', 'Somma le quantità');
  static String get statisticsImportSumDetail => _t(
    'Your copies and the file\'s copies add up.',
    'Le tue copie e quelle del file si sommano.',
  );
  static String get statisticsImportConfirmButton => _t('Import', 'Importa');
  static String get statisticsImportCancelButton => _t('Cancel', 'Annulla');
  static String get statisticsImportNothingMessage => _t(
    'That file has nothing to import.',
    'Quel file non contiene nulla da importare.',
  );
  static String get statisticsImportFailedMessage => _t(
    'Could not read that file. Pick a collection CSV exported from this app.',
    'Impossibile leggere quel file. Scegli un CSV della collezione esportato '
        'da questa app.',
  );
  static String get statisticsImportDoneMessage =>
      _t('Collection updated.', 'Collezione aggiornata.');

  // The parts of the import result SnackBar, joined after
  // [statisticsImportDoneMessage]. Functions rather than a suffix glued to the
  // number at the call site, so each language owns its own word order.
  static String statisticsImportAddedCount(int count) =>
      _t('$count added', '$count aggiunte');
  static String statisticsImportMergedCount(int count) =>
      _t('$count merged', '$count unite');
  static String statisticsImportSkippedCount(int count) =>
      _t('$count skipped', '$count saltate');

  // The two ways a file can be refused outright. The parser reports *which*
  // (`CsvFormatException.problem`) and the screen words it here, so the data
  // layer carries no interface text.
  static String get statisticsImportEmptyFile =>
      _t('The file is empty.', 'Il file è vuoto.');
  static String statisticsImportMissingColumn(String column, String expected) =>
      _t(
        'Missing the "$column" column. Expected a collection CSV exported by '
            'this app (columns: $expected).',
        'Manca la colonna "$column". Era atteso un CSV della collezione '
            'esportato da questa app (colonne: $expected).',
      );

  // Collection value. Two totals, never one: Cardmarket is euros and TCGplayer
  // is dollars, and this app carries no exchange rate.
  static String get statisticsValueSection =>
      _t('Collection value', 'Valore della collezione');
  static String get statisticsValueButton =>
      _t('Calculate collection value', 'Calcola il valore della collezione');
  static String get statisticsValueRefreshButton =>
      _t('Refresh prices', 'Aggiorna i prezzi');

  /// Labelled asymmetrically on purpose. Since step 26 the TCGplayer total
  /// prices each copy at the set and rarity recorded, while Cardmarket has no
  /// per-printing figure to use and stays the card-level floor — so calling
  /// both of them plain vendor names would imply they are the same measurement.
  static String get statisticsValueCardmarketLabel =>
      _t('Cardmarket (floor)', 'Cardmarket (minimo)');
  static String get statisticsValueTcgplayerLabel =>
      _t('TCGplayer', 'TCGplayer');
  static String get statisticsValueErrorMessage => _t(
    'Could not fetch prices. Check your connection and try again.',
    'Impossibile scaricare i prezzi. Controlla la connessione e riprova.',
  );

  /// The honesty line beside the totals. Hidden at zero, like the import
  /// dialog's counts — a total assembled from a whole collection should not
  /// warn about a problem that does not exist.
  static String statisticsValueUnpriced(int count) => _t(
    '$count ${count == 1 ? 'card has' : 'cards have'} no price',
    '$count ${count == 1 ? 'carta non ha' : 'carte non hanno'} un prezzo',
  );
  static String statisticsValueProgress(int done, int total) =>
      _t('Priced $done / $total cards', 'Prezzate $done / $total carte');

  /// The breakdown behind the two totals: one row per card, with what each is
  /// worth and what the copies of it are worth together.
  static String get statisticsValueExportButton =>
      _t('Export value breakdown', 'Esporta il dettaglio del valore');
  static String get statisticsValueExportSubject =>
      _t('YGO collection value', 'Valore collezione YGO');

  /// Says what the totals are. The two halves are no longer the same kind of
  /// figure and the note has to carry that: TCGplayer prices the printing, and
  /// Cardmarket cannot, because YGOPRODeck reports it at the card level only.
  static String get statisticsValueNote => _t(
    'TCGplayer prices each copy at the set and rarity you recorded, falling '
        'back to the card\'s lowest printing where no set is recorded. '
        'Cardmarket is always that lowest-printing floor; no euro price exists '
        'per printing. Condition and edition are ignored on both.',
    'TCGplayer valuta ogni copia al set e alla rarità che hai registrato, '
        'ripiegando sulla stampa più economica della carta quando il set non è '
        'registrato. Cardmarket è sempre quel prezzo minimo: non esiste un '
        'prezzo in euro per singola stampa. Condizione ed edizione sono '
        'ignorate in entrambi.',
  );

  /// How much of the valuation got a real per-printing figure rather than the
  /// card floor — the measure of how far it is worth trusting.
  static String statisticsValuePrintingPriced(int priced, int total) => _t(
    '$priced of $total ${total == 1 ? 'line' : 'lines'} priced at their own '
        'printing',
    '$priced di $total ${total == 1 ? 'riga valutata' : 'righe valutate'} '
        'alla propria stampa',
  );

  static String get statisticsValueBreakdownButton =>
      _t('View breakdown', 'Vedi il dettaglio');
  static String get valueBreakdownTitle =>
      _t('Value breakdown', 'Dettaglio del valore');
  static String get valueBreakdownSortByValue =>
      _t('Most valuable first', 'Prima le più preziose');
  static String get valueBreakdownSortByName => _t('By name', 'Per nome');
  static String get valueBreakdownNoSet =>
      _t('No set recorded', 'Nessun set registrato');

  /// Marks a row that fell back to the card-level floor. A word rather than a
  /// colour, so it survives a colour-blind reader and a greyscale screenshot.
  static String get valueBreakdownCardFloorTag =>
      _t('card floor', 'prezzo minimo');

  static String get syncFetchingMessage => _t(
    'Downloading card database…',
    'Download del database delle carte…',
  );
  static String get syncWritingMessage =>
      _t('Saving to your device…', 'Salvataggio sul dispositivo…');
  static String get syncErrorMessage => _t(
    'Could not download the card database. Check your connection and '
        'try again.',
    'Impossibile scaricare il database delle carte. Controlla la connessione '
        'e riprova.',
  );
  static String get syncRetryButton => _t('Retry', 'Riprova');

  // Enum and language labels. They used to be literals on each enum member;
  // they live here now so they follow the interface language. The enums'
  // `label` getters read these.
  static String get editionFirst => _t('1st Edition', '1a Edizione');
  static String get editionUnlimited => _t('Unlimited', 'Illimitata');
  static String get editionLimited => _t('Limited Edition', 'Edizione Limitata');

  static String get themeSystem => _t('System', 'Sistema');
  static String get themeLight => _t('Light', 'Chiaro');
  static String get themeDark => _t('Dark', 'Scuro');

  static String get viewModeStandard => _t('Standard', 'Standard');
  static String get viewModeMinifyStandard =>
      _t('Artwork + name', 'Illustrazione + nome');
  static String get viewModeMinifyFull =>
      _t('Artwork only', 'Solo illustrazione');

  static String get fastLogFieldCondition => _t('Condition', 'Condizione');
  static String get fastLogFieldEdition => _t('Edition', 'Edizione');
  static String get fastLogFieldLanguage => _t('Language', 'Lingua');

  /// The printed-language names, keyed by the two-letter code a card's set
  /// code carries (`kCardLanguages`). Read through `languageLabel`, which
  /// echoes an unlisted code back unchanged.
  static Map<String, String> get cardLanguageNames => switch (_language) {
    AppLanguage.english => const {
      'EN': 'English',
      'DE': 'German',
      'FR': 'French',
      'IT': 'Italian',
      'SP': 'Spanish',
      'PT': 'Portuguese',
      'JP': 'Japanese',
      'KR': 'Korean',
      'AE': 'Asian-English',
    },
    AppLanguage.italian => const {
      'EN': 'Inglese',
      'DE': 'Tedesco',
      'FR': 'Francese',
      'IT': 'Italiano',
      'SP': 'Spagnolo',
      'PT': 'Portoghese',
      'JP': 'Giapponese',
      'KR': 'Coreano',
      'AE': 'Inglese asiatico',
    },
  };

  // Card terminology, keyed by the raw value YGOPRODeck sends. The API's
  // `language=it` response translates only `name` and `desc`, so these tables
  // are hand-written. The wording is Konami's, from its Italian card database,
  // except where noted. Read through `models/card_terms.dart`, which echoes any
  // value missing here unchanged, so an English map can simply be empty.

  /// `cards.type`. Each phrase is composed from the parts Konami prints on a
  /// card's type line ("Drago / Synchro / Effetto").
  static Map<String, String> get cardTypeNames => switch (_language) {
    AppLanguage.english => const {},
    AppLanguage.italian => const {
      'Effect Monster': 'Mostro con Effetto',
      'Flip Effect Monster': 'Mostro Scoperta con Effetto',
      'Flip Tuner Effect Monster': 'Mostro Scoperta Tuner con Effetto',
      'Fusion Monster': 'Mostro Fusione',
      'Gemini Monster': 'Mostro Gemello',
      'Link Monster': 'Mostro Link',
      'Normal Monster': 'Mostro Normale',
      'Normal Tuner Monster': 'Mostro Normale Tuner',
      'Pendulum Effect Fusion Monster': 'Mostro Pendulum Fusione con Effetto',
      'Pendulum Effect Monster': 'Mostro Pendulum con Effetto',
      'Pendulum Effect Ritual Monster': 'Mostro Pendulum Rituale con Effetto',
      'Pendulum Flip Effect Monster': 'Mostro Pendulum Scoperta con Effetto',
      'Pendulum Normal Monster': 'Mostro Pendulum Normale',
      'Pendulum Tuner Effect Monster': 'Mostro Pendulum Tuner con Effetto',
      'Ritual Effect Monster': 'Mostro Rituale con Effetto',
      'Ritual Monster': 'Mostro Rituale',
      'Skill Card': 'Carta Abilità',
      'Spell Card': 'Carta Magia',
      'Spirit Monster': 'Mostro Spirito',
      'Synchro Monster': 'Mostro Synchro',
      'Synchro Pendulum Effect Monster': 'Mostro Synchro Pendulum con Effetto',
      'Synchro Tuner Monster': 'Mostro Synchro Tuner',
      'Token': 'Segna-Mostro',
      'Toon Monster': 'Mostro Toon',
      'Trap Card': 'Carta Trappola',
      'Tuner Monster': 'Mostro Tuner',
      'Union Effect Monster': 'Mostro Unione con Effetto',
      'XYZ Monster': 'Mostro Xyz',
      'XYZ Pendulum Effect Monster': 'Mostro Xyz Pendulum con Effetto',
    },
  };

  /// `cards.frame_type`. The one table with English entries too: the raw values
  /// are lowercase identifiers (`effect_pendulum`), not words anyone should read
  /// in either language.
  static Map<String, String> get cardFrameNames => switch (_language) {
    AppLanguage.english => const {
      'effect': 'Effect',
      'effect_pendulum': 'Effect Pendulum',
      'fusion': 'Fusion',
      'fusion_pendulum': 'Fusion Pendulum',
      'link': 'Link',
      'normal': 'Normal',
      'normal_pendulum': 'Normal Pendulum',
      'ritual': 'Ritual',
      'ritual_pendulum': 'Ritual Pendulum',
      'skill': 'Skill',
      'spell': 'Spell',
      'synchro': 'Synchro',
      'synchro_pendulum': 'Synchro Pendulum',
      'token': 'Token',
      'trap': 'Trap',
      'xyz': 'Xyz',
      'xyz_pendulum': 'Xyz Pendulum',
    },
    AppLanguage.italian => const {
      'effect': 'Effetto',
      'effect_pendulum': 'Effetto Pendulum',
      'fusion': 'Fusione',
      'fusion_pendulum': 'Fusione Pendulum',
      'link': 'Link',
      'normal': 'Normale',
      'normal_pendulum': 'Normale Pendulum',
      'ritual': 'Rituale',
      'ritual_pendulum': 'Rituale Pendulum',
      'skill': 'Abilità',
      'spell': 'Magia',
      'synchro': 'Synchro',
      'synchro_pendulum': 'Synchro Pendulum',
      'token': 'Segna-Mostro',
      'trap': 'Trappola',
      'xyz': 'Xyz',
      'xyz_pendulum': 'Xyz Pendulum',
    },
  };

  /// `cards.race`, which YGOPRODeck overloads: the monster type on a monster,
  /// the icon on a Spell or Trap, and the character's name on a Skill card
  /// ("Joey", "Kaiba"). Those names are absent here on purpose and pass through.
  ///
  /// `Creator God` is the one guess: Konami's search form does not list it (it
  /// belongs to a single card), so this follows "Divinità-Bestia" by analogy.
  static Map<String, String> get cardRaceNames => switch (_language) {
    AppLanguage.english => const {},
    AppLanguage.italian => const {
      'Aqua': 'Acqua',
      'Beast': 'Bestia',
      'Beast-Warrior': 'Guerriero-Bestia',
      'Creator God': 'Divinità Creatrice',
      'Cyberse': 'Cyberso',
      'Dinosaur': 'Dinosauro',
      'Divine-Beast': 'Divinità-Bestia',
      'Dragon': 'Drago',
      'Fairy': 'Fata',
      'Fiend': 'Demone',
      'Fish': 'Pesce',
      'Illusion': 'Illusione',
      'Insect': 'Insetto',
      'Machine': 'Macchina',
      'Plant': 'Pianta',
      'Psychic': 'Psichico',
      'Pyro': 'Pyro',
      'Reptile': 'Rettile',
      'Rock': 'Roccia',
      'Sea Serpent': 'Serpente Marino',
      'Spellcaster': 'Incantatore',
      'Thunder': 'Tuono',
      'Warrior': 'Guerriero',
      'Winged Beast': 'Bestia Alata',
      'Wyrm': 'Wyrm',
      'Zombie': 'Zombie',
      // Spell and Trap icons.
      'Continuous': 'Continua',
      'Counter': 'Contro',
      'Equip': 'Equipaggiamento',
      'Field': 'Terreno',
      'Normal': 'Normale',
      'Quick-Play': 'Rapida',
      'Ritual': 'Rituale',
    },
  };

  /// `cards.attribute`, in capitals as Konami prints them.
  static Map<String, String> get cardAttributeNames => switch (_language) {
    AppLanguage.english => const {},
    AppLanguage.italian => const {
      'DARK': 'OSCURITÀ',
      'DIVINE': 'DIVINO',
      'EARTH': 'TERRA',
      'FIRE': 'FUOCO',
      'LIGHT': 'LUCE',
      'SPELL': 'MAGIA',
      'TRAP': 'TRAPPOLA',
      'WATER': 'ACQUA',
      'WIND': 'VENTO',
    },
  };

  /// `printings.rarity`, for the rarities with established Italian usage. Konami
  /// publishes only codes (C, SR, UR, SE), so this follows how Italian shops
  /// write them. Everything else the API sends is either a trade name
  /// ("Starlight Rare", "Quarter Century Secret Rare") or junk ("2", "force-SMW"),
  /// and stays as it is rather than getting a name nobody uses.
  static Map<String, String> get cardRarityNames => switch (_language) {
    AppLanguage.english => const {},
    AppLanguage.italian => const {
      'Common': 'Comune',
      'Ghost Rare': 'Ghost Rara',
      'Gold Rare': 'Gold Rara',
      'Rare': 'Rara',
      'Secret Rare': 'Rara Segreta',
      'Super Rare': 'Super Rara',
      'Ultimate Rare': 'Ultimate Rara',
      'Ultra Rare': 'Ultra Rara',
    },
  };
}
