import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/theme/tokens.dart';
import '../../data/repositories/card_repository.dart';
import '../../data/repositories/collection_repository.dart';
import '../../models/app_settings.dart';
import '../../models/card_condition.dart';
import '../../models/card_edition.dart';
import '../../models/collection_entry.dart';
import '../../models/ygo_card.dart';
import '../collection/collection_providers.dart';
import '../settings/settings_providers.dart';
import 'art_providers.dart';
import 'hash_index.dart';
import 'scan_providers.dart';
import 'scan_state.dart';

part 'scan_controller.g.dart';

/// Drives the continuous-scan state machine. Artwork recognition is the
/// automatic primary path (off [artReadings]); passcode OCR is an on-demand
/// fallback (off [passcodeReadings], live only while the user has asked for it).
///
/// Modeled on `InitialSyncController`: an immutable state class plus a notifier
/// that owns all transition logic (none of it in a `build()` method). The rules
/// still hold: N consecutive agreeing frames before a match, a debounce after a
/// confirm so one card doesn't log repeatedly, and — the non-negotiable one —
/// nothing is written until the user reviews and confirms it.
@riverpod
class ScanController extends _$ScanController {
  /// The user's configured defaults, read once when this controller is built.
  ///
  /// `ref.read`, not `watch`: a settings change must not tear down and restart
  /// a scan in progress. This controller is autoDispose, so the new value
  /// applies the next time the scan screen is opened. The fallback covers
  /// widget tests that pump the screen without a resolved settings load.
  late final AppSettings _settings =
      ref.read(settingsControllerProvider).value ?? const AppSettings();

  ScanState _initialState() => ScanState(
    status: ScanStatus.detecting,
    condition: _settings.defaultCondition,
    edition: _settings.defaultEdition,
    language: _settings.language,
  );

  @override
  ScanState build() {
    // Primary: continuous artwork ranking.
    ref.listen(artReadingsProvider, (previous, next) {
      next.when(
        data: (reading) => _onArtReading(reading.top),
        error: (error, _) => _onCameraError(error),
        loading: () {},
      );
    });
    // Fallback: on-demand passcode OCR (inert unless requested).
    ref.listen(passcodeReadingsProvider, (previous, next) {
      next.when(
        data: (reading) => _onReading(reading.passcode),
        error: (error, _) => _onCameraError(error),
        loading: () {},
      );
    });
    return _initialState();
  }

  void _onCameraError(Object error) {
    _setPaused(paused: true);
    state = state.copyWith(status: ScanStatus.error, error: error);
  }

  /// Whether [ScanState.error] is the bundled index failing to load rather than
  /// the camera failing to start.
  ///
  /// Both arrive down the same stream, so without this a [FormatException] from
  /// `HashIndex.fromJson`'s header check — the guard that fires when the
  /// committed `assets/card_hashes.json` and [ArtMatchTuning.artBoxRoi] disagree
  /// — was reported to the user as *"the camera could not be started"*. Worse,
  /// `hashIndexProvider` is `keepAlive` and caches its failure for the process
  /// lifetime while [retry] rebuilds only the camera, so the wrong message came
  /// with a button that could never fix it. The screen shows a distinct panel
  /// for this, and [retry] now invalidates the index too.
  static bool isIndexError(Object? error) => error is FormatException;

  /// Tells the artwork pipeline to stop detecting/hashing while a result is
  /// waiting on the user — the readings would be discarded anyway (see the
  /// freeze guard in [_onArtReading]), and the work is not free.
  void _setPaused({required bool paused}) =>
      ref.read(scanPausedProvider.notifier).set(paused: paused);

  /// Advances the suppression on the just-handled card by one reading that
  /// matched it, returning the cooldown left and whether the card is now free.
  ///
  /// Shared by both reading paths, because the trap it fixes was in both. A
  /// **dismissed** card (`cooldown > 0`) counts down here and is released when
  /// the count runs out — the card is sitting in the reticle, so it goes on
  /// matching every frame, and the empty-frame debounce a dismiss used to share
  /// with a confirm could therefore never advance: holding the card still, the
  /// natural thing to do, suppressed it forever. A **confirmed** card
  /// (`cooldown == 0`) is untouched here and stays suppressed until the frame
  /// actually goes empty for [ScanTuning.debounceEmptyFrames], which is the
  /// spec's non-optional guard against one card logging thirty times.
  static ({int cooldown, bool release}) _tickSuppression(int cooldown) {
    if (cooldown <= 0) return (cooldown: 0, release: false);
    final left = cooldown - 1;
    return (cooldown: left, release: left <= 0);
  }

  // ---------------------------------------------------------------------------
  // Primary path: artwork.
  // ---------------------------------------------------------------------------

  void _onArtReading(HashMatch? top) {
    final s = state;
    // Artwork is ignored outright in passcode mode: the user picked the other
    // tool, and it stays picked until they switch back (see [ScanMode]).
    if (s.mode == ScanMode.passcode) return;
    // Frozen while a result awaits the user, an OCR read is running, or after a
    // camera error. Stays active through the transient `confirmed` state so the
    // post-confirm empty-frame debounce actually advances back to detecting.
    if (s.status == ScanStatus.matched ||
        s.status == ScanStatus.unknown ||
        s.status == ScanStatus.candidates ||
        s.status == ScanStatus.readingCode ||
        s.status == ScanStatus.error) {
      return;
    }

    // No confident candidate this frame — treat as an empty frame.
    if (top == null || top.distance > ArtMatchTuning.autoMatchMaxDistance) {
      final empties = s.emptyFrameCount + 1;
      state = s.copyWith(
        status: ScanStatus.detecting,
        artAgreementBuffer: const [],
        emptyFrameCount: empties,
        clearLastConfirmedPasscode: empties >= ScanTuning.debounceEmptyFrames,
      );
      return;
    }

    // The *index* passcode, which is the namespace `lastConfirmedPasscode` is
    // kept in — see [ScanState.matchedIndexPasscode].
    final passcode = top.passcode;

    // The just-handled card is still in view: keep it rejected for its debounce
    // window. A dismissed card's window runs down right here, so it can be
    // picked up again without being taken out of the reticle first.
    if (passcode == s.lastConfirmedPasscode) {
      final tick = _tickSuppression(s.dismissCooldown);
      state = s.copyWith(
        status: ScanStatus.detecting,
        emptyFrameCount: 0,
        dismissCooldown: tick.cooldown,
        clearLastConfirmedPasscode: tick.release,
      );
      return;
    }

    // Disagreement with the run in progress: discard it and start fresh.
    if (s.artAgreementBuffer.isNotEmpty && s.artAgreementBuffer.last != passcode) {
      state = s.copyWith(
        status: ScanStatus.reading,
        artAgreementBuffer: const [],
        emptyFrameCount: 0,
      );
      return;
    }

    final buffer = [...s.artAgreementBuffer, passcode];
    state = s.copyWith(
      status: ScanStatus.reading,
      artAgreementBuffer: buffer,
      emptyFrameCount: 0,
    );
    // Resolve exactly once, on the frame that reaches N.
    if (buffer.length == ScanTuning.artAgreementFrames) {
      _resolveArtMatch();
    }
  }

  /// Resolves the agreed artwork run to actual cards (a DB read per ranked hit)
  /// and presents the nearest for review, keeping the alternatives on state for
  /// the "not the right card?" path. If nothing is resolvable (e.g. the nearest
  /// hits are all alt-art passcodes the app DB doesn't store), quietly resume
  /// scanning rather than showing a dead end.
  Future<void> _resolveArtMatch() async {
    // Freeze the pipeline *before* the awaits, not after. `match` is 1-5 serial
    // DB round trips, and while they ran the artwork stream stayed live with the
    // status still `reading` — so a single frame with no confident top (a glare
    // blink, the card shifting) took the empty-frame branch to `detecting`, and
    // the guard below then silently discarded a match the agreement gate had
    // already accepted. At two agreeing frames on a 300ms cadence that is a
    // plausible share of the "hard to lock on" reports.
    _setPaused(paused: true);
    final matcher = await ref.read(artMatcherProvider.future);
    final candidates = await matcher.match(
      viewportSize: ref.read(scanViewportSizeProvider),
    );
    // The user may have acted, or a disagreement/empty frame moved us on.
    if (state.status != ScanStatus.reading) return;

    if (candidates.isEmpty) {
      // Nothing resolvable — resume, but debounce the hash that got us here, or
      // the same unresolvable run re-agrees and re-resolves every two frames.
      _setPaused(paused: false);
      state = state.copyWith(
        status: ScanStatus.detecting,
        artAgreementBuffer: const [],
        lastConfirmedPasscode: state.artAgreementBuffer.isEmpty
            ? null
            : state.artAgreementBuffer.last,
        dismissCooldown: ScanTuning.dismissCooldownFrames,
      );
      return;
    }
    final top = candidates.first;
    state = state.copyWith(
      status: ScanStatus.matched,
      matchedCard: top.card,
      matchedIndexPasscode: top.indexPasscode,
      candidates: candidates,
      artAgreementBuffer: const [],
      condition: _settings.defaultCondition,
      edition: _settings.defaultEdition,
      language: _settings.language,
      clearPrintingId: true,
      quantity: 1,
    );
  }

  /// From a review, reveals the ranked artwork alternatives so the user can
  /// correct a wrong top guess without leaving the scan flow.
  void showCandidates() {
    if (state.status != ScanStatus.matched || state.candidates.isEmpty) return;
    state = state.copyWith(
      status: ScanStatus.candidates,
      clearMatchedCard: true,
    );
  }

  /// Promotes a picked artwork candidate back into the review gate. Keeps the
  /// candidate list so a second wrong pick is still recoverable.
  void selectCandidate(YgoCard card) {
    if (state.status != ScanStatus.candidates) return;
    // Re-key the debounce onto whichever candidate this is — the list is ranked
    // by index passcode, and picking the third entry must suppress *that* hash,
    // not the top one's.
    final picked = state.candidates
        .where((c) => c.card.passcode == card.passcode)
        .firstOrNull;
    state = state.copyWith(
      status: ScanStatus.matched,
      matchedCard: card,
      matchedIndexPasscode: picked?.indexPasscode ?? card.passcode,
      clearUnknownPasscode: true,
      condition: _settings.defaultCondition,
      edition: _settings.defaultEdition,
      language: _settings.language,
      // A different card has different printings, so any earlier pick is void.
      clearPrintingId: true,
      quantity: 1,
    );
  }

  // ---------------------------------------------------------------------------
  // The other tool: 8-digit passcode OCR — a mode, not a one-shot read.
  // ---------------------------------------------------------------------------

  /// Switches into passcode-reading mode: freezes the artwork path and turns on
  /// the ML-Kit OCR stream. Only reachable while actively scanning.
  void requestPasscodeRead() {
    if (state.status != ScanStatus.detecting &&
        state.status != ScanStatus.reading) {
      return;
    }
    _beginPasscodeRead();
  }

  /// Arms (or re-arms) an OCR pass. Called when the user switches into the mode
  /// and again after every confirm/dismiss while it is still on: the mode is
  /// sticky, so one tap covers a whole stack of cards (see [ScanMode]).
  void _beginPasscodeRead() {
    state = state.copyWith(
      status: ScanStatus.readingCode,
      mode: ScanMode.passcode,
      agreementBuffer: const [],
      artAgreementBuffer: const [],
    );
    ref.read(passcodeOcrRequestedProvider.notifier).set(requested: true);
    _setArtCapture(enabled: false);
  }

  /// Stops the camera building a luma copy of every frame while nothing reads
  /// it. `artReadings` skips its whole pass in passcode mode, so the copy was
  /// pure allocation — around a megabyte a second at this cadence.
  ///
  /// Set directly on the service rather than derived from a watched provider:
  /// `cameraServiceProvider` rebuilding would tear down and restart the camera.
  void _setArtCapture({required bool enabled}) =>
      ref.read(cameraServiceProvider).artCaptureEnabled = enabled;

  void _onReading(String? read) {
    if (state.status != ScanStatus.readingCode) return;

    final s = state;
    if (read == null) {
      // A gap breaks the run. It also advances the post-confirm debounce, so a
      // card just logged becomes readable again once it has left the frame —
      // this path replaces the artwork stream's counting, which is idle here.
      final empties = s.emptyFrameCount + 1;
      state = s.copyWith(
        agreementBuffer: const [],
        emptyFrameCount: empties,
        clearLastConfirmedPasscode: empties >= ScanTuning.debounceEmptyFrames,
      );
      return;
    }

    // The card just handled is still in view: ignore it for its debounce
    // window, so lingering on it doesn't immediately re-open the review panel.
    // As on the artwork path, a *dismissed* card's window runs down here rather
    // than waiting for the card to leave — nothing was written, so there is
    // nothing to protect and the user is trying to read it again.
    if (read == s.lastConfirmedPasscode) {
      final tick = _tickSuppression(s.dismissCooldown);
      state = s.copyWith(
        agreementBuffer: const [],
        emptyFrameCount: 0,
        dismissCooldown: tick.cooldown,
        clearLastConfirmedPasscode: tick.release,
      );
      return;
    }

    if (s.agreementBuffer.isNotEmpty && s.agreementBuffer.last != read) {
      state = s.copyWith(agreementBuffer: const [], emptyFrameCount: 0);
      return;
    }

    final buffer = [...s.agreementBuffer, read];
    state = s.copyWith(agreementBuffer: buffer, emptyFrameCount: 0);
    if (buffer.length == ScanTuning.agreementFrames) {
      _lookup(read);
    }
  }

  Future<void> _lookup(String passcode) async {
    // Stop the OCR stream the moment we commit to resolving this read.
    _stopOcr();
    final repository = await ref.read(cardRepositoryProvider.future);
    final card = await repository.getByPasscode(passcode);
    if (state.status != ScanStatus.readingCode) return;

    _setPaused(paused: true);
    if (card == null) {
      state = state.copyWith(
        status: ScanStatus.unknown,
        unknownPasscode: passcode,
        agreementBuffer: const [],
      );
    } else {
      state = state.copyWith(
        status: ScanStatus.matched,
        matchedCard: card,
        clearCandidates: true,
        agreementBuffer: const [],
        condition: _settings.defaultCondition,
        edition: _settings.defaultEdition,
        language: _settings.language,
        clearPrintingId: true,
        quantity: 1,
      );
    }
  }

  /// Leaves passcode mode for artwork recognition. Together with leaving the
  /// screen (this controller is autoDispose), the user's only way out of the
  /// sticky mode — which is the point: a confirm must not drop them out of it.
  void exitPasscodeMode() {
    if (state.mode != ScanMode.passcode) return;
    _stopOcr();
    _setPaused(paused: false);
    state = state.copyWith(
      status: ScanStatus.detecting,
      mode: ScanMode.artwork,
      agreementBuffer: const [],
      artAgreementBuffer: const [],
      emptyFrameCount: 0,
    );
  }

  void _stopOcr() {
    ref.read(passcodeOcrRequestedProvider.notifier).set(requested: false);
    _setArtCapture(enabled: true);
  }

  // ---------------------------------------------------------------------------
  // Shared: review, confirm, dismiss.
  // ---------------------------------------------------------------------------

  void setCondition(CardCondition condition) =>
      state = state.copyWith(condition: condition);

  void setEdition(CardEdition edition) =>
      state = state.copyWith(edition: edition);

  void setLanguage(String language) =>
      state = state.copyWith(language: language);

  /// Picks the printing (set/expansion) for the pending match, or null for
  /// "no specific set".
  void setPrinting(int? printingId) => state = state.copyWith(
    printingId: printingId,
    clearPrintingId: printingId == null,
  );

  void setQuantity(int quantity) {
    if (quantity < 1) return;
    state = state.copyWith(quantity: quantity);
  }

  /// Writes the reviewed match to the collection, then resumes scanning with
  /// this card debounced. `printingId` is whatever the user picked in the review
  /// gate — null (no specific set) when they left it alone, like the manual
  /// add's skip path.
  Future<void> confirm() async {
    final card = state.matchedCard;
    if (card == null || state.status != ScanStatus.matched) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final repository = await ref.read(collectionRepositoryProvider.future);
    await repository.addOrIncrement(
      CollectionEntry(
        passcode: card.passcode,
        printingId: state.printingId,
        condition: state.condition,
        edition: state.edition,
        // Picked in the review gate (seeded from the settings default). The
        // camera can't read a card's language, so it's chosen by hand here.
        language: state.language,
        quantity: state.quantity,
        createdAt: now,
        updatedAt: now,
      ),
    );
    ref.invalidate(collectionEntriesProvider);
    // A scan logged against a set can introduce a rarity the collection did not
    // hold before, which the collection filter row offers as a chip.
    ref.invalidate(collectionRarityOptionsProvider);

    _setPaused(paused: false);
    state = state.copyWith(
      status: ScanStatus.confirmed,
      clearMatchedCard: true,
      clearCandidates: true,
      clearPrintingId: true,
      // The *index* passcode, not the card's: on an alt-art match the two
      // differ, and the next frame's reading carries the index one. Comparing
      // the wrong side meant the suppression branch never fired and the review
      // panel re-opened on the card just logged.
      lastConfirmedPasscode: state.matchedIndexPasscode ?? card.passcode,
      // Zero: a confirm wrote a row, so this card stays suppressed until it has
      // actually left the lens (the empty-frame debounce). It must not be freed
      // by the dismiss cooldown, or one card left under the camera would log
      // repeatedly — the exact thing the debounce exists to prevent.
      dismissCooldown: 0,
      agreementBuffer: const [],
      artAgreementBuffer: const [],
      emptyFrameCount: 0,
    );
    // The chosen tool survives a save: in passcode mode go straight back to
    // reading codes for the next card instead of dropping into artwork
    // recognition, which would mean re-arming the mode for every card.
    if (state.mode == ScanMode.passcode) _beginPasscodeRead();
  }

  /// Discards the current match/unknown/candidates result without writing, and
  /// briefly debounces any resolved card so the panel doesn't re-open under the
  /// user's thumb. Resumes in whichever mode the user is in.
  ///
  /// The debounce is a short **countdown**, not the post-confirm empty-frame
  /// rule: nothing was written, so the card the user just declined has to become
  /// scannable again without being taken out of the reticle first. See
  /// [_tickSuppression].
  void dismiss() {
    // Whatever card the user was actually looking at. The candidate list is the
    // third case: [showCandidates] clears `matchedCard`, so without it a
    // "none of these" would suppress nothing and the same top guess would be
    // re-presented on the very next frame.
    // Index passcodes throughout, matching what a reading carries.
    final passcode =
        state.matchedIndexPasscode ??
        state.matchedCard?.passcode ??
        state.unknownPasscode ??
        (state.candidates.isEmpty ? null : state.candidates.first.indexPasscode);
    _setPaused(paused: false);
    state = state.copyWith(
      status: ScanStatus.detecting,
      clearMatchedCard: true,
      clearUnknownPasscode: true,
      clearCandidates: true,
      clearPrintingId: true,
      lastConfirmedPasscode: passcode,
      dismissCooldown: ScanTuning.dismissCooldownFrames,
      agreementBuffer: const [],
      artAgreementBuffer: const [],
      emptyFrameCount: 0,
    );
    if (state.mode == ScanMode.passcode) {
      _beginPasscodeRead();
    } else {
      _stopOcr();
    }
  }

  /// Retries after a camera error by rebuilding the camera pipeline. Starts over
  /// in artwork mode — the error tore down whatever the user was doing anyway.
  void retry() {
    _stopOcr();
    _setPaused(paused: false);
    state = _initialState();
    ref.invalidate(cameraServiceProvider);
    ref.invalidate(scanCameraProvider);
    // The index too: it is `keepAlive` and deliberately caches its parse, so a
    // load failure would otherwise survive every retry for the process
    // lifetime. Re-reading a 1MB asset is cheap next to being unrecoverable,
    // and on the overwhelmingly common camera-error path this provider is
    // already resolved, so the invalidation just re-parses once.
    ref.invalidate(hashIndexProvider);
    ref.invalidate(passcodeReadingsProvider);
    ref.invalidate(artReadingsProvider);
  }
}
