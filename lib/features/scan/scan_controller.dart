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

  void _onCameraError(Object error) =>
      state = state.copyWith(status: ScanStatus.error, error: error);

  // ---------------------------------------------------------------------------
  // Primary path: artwork.
  // ---------------------------------------------------------------------------

  void _onArtReading(HashMatch? top) {
    final s = state;
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

    final passcode = top.passcode;

    // The just-handled card is still in view: keep it rejected until the frame
    // goes empty for the debounce window.
    if (passcode == s.lastConfirmedPasscode) {
      state = s.copyWith(status: ScanStatus.detecting, emptyFrameCount: 0);
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
    final matcher = await ref.read(artMatcherProvider.future);
    final candidates = await matcher.match();
    // The user may have acted, or a disagreement/empty frame moved us on.
    if (state.status != ScanStatus.reading) return;

    if (candidates.isEmpty) {
      state = state.copyWith(
        status: ScanStatus.detecting,
        artAgreementBuffer: const [],
      );
      return;
    }
    state = state.copyWith(
      status: ScanStatus.matched,
      matchedCard: candidates.first.card,
      candidates: candidates,
      artAgreementBuffer: const [],
      condition: _settings.defaultCondition,
      edition: _settings.defaultEdition,
      language: _settings.language,
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
    state = state.copyWith(
      status: ScanStatus.matched,
      matchedCard: card,
      clearUnknownPasscode: true,
      condition: _settings.defaultCondition,
      edition: _settings.defaultEdition,
      language: _settings.language,
      quantity: 1,
    );
  }

  // ---------------------------------------------------------------------------
  // Fallback path: on-demand passcode OCR.
  // ---------------------------------------------------------------------------

  /// Starts the on-demand passcode read: freezes the artwork path and turns on
  /// the ML-Kit OCR stream. Only reachable while actively scanning.
  void requestPasscodeRead() {
    if (state.status != ScanStatus.detecting &&
        state.status != ScanStatus.reading) {
      return;
    }
    state = state.copyWith(
      status: ScanStatus.readingCode,
      agreementBuffer: const [],
      artAgreementBuffer: const [],
      ocrFramesSeen: 0,
    );
    ref.read(passcodeOcrRequestedProvider.notifier).set(requested: true);
  }

  void _onReading(String? read) {
    if (state.status != ScanStatus.readingCode) return;

    final s = state;
    final seen = s.ocrFramesSeen + 1;
    // Bounded so a glare-blocked code can't spin forever.
    if (seen > ScanTuning.ocrTimeoutFrames) {
      _stopOcr();
      state = state.copyWith(
        status: ScanStatus.detecting,
        agreementBuffer: const [],
      );
      return;
    }

    if (read == null) {
      // A gap breaks the run, but keep reading until the timeout.
      state = s.copyWith(agreementBuffer: const [], ocrFramesSeen: seen);
      return;
    }

    if (s.agreementBuffer.isNotEmpty && s.agreementBuffer.last != read) {
      state = s.copyWith(agreementBuffer: const [], ocrFramesSeen: seen);
      return;
    }

    final buffer = [...s.agreementBuffer, read];
    state = s.copyWith(agreementBuffer: buffer, ocrFramesSeen: seen);
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
        quantity: 1,
      );
    }
  }

  /// Cancels an in-progress on-demand OCR read and returns to artwork scanning.
  void cancelPasscodeRead() {
    if (state.status != ScanStatus.readingCode) return;
    _stopOcr();
    state = state.copyWith(
      status: ScanStatus.detecting,
      agreementBuffer: const [],
    );
  }

  void _stopOcr() =>
      ref.read(passcodeOcrRequestedProvider.notifier).set(requested: false);

  // ---------------------------------------------------------------------------
  // Shared: review, confirm, dismiss.
  // ---------------------------------------------------------------------------

  void setCondition(CardCondition condition) =>
      state = state.copyWith(condition: condition);

  void setEdition(CardEdition edition) =>
      state = state.copyWith(edition: edition);

  void setLanguage(String language) =>
      state = state.copyWith(language: language);

  void setQuantity(int quantity) {
    if (quantity < 1) return;
    state = state.copyWith(quantity: quantity);
  }

  /// Writes the reviewed match to the collection, then resumes scanning with
  /// this card debounced. A scanned quick-log carries no printing
  /// (`printingId` null), consistent with the manual add's skip path.
  Future<void> confirm() async {
    final card = state.matchedCard;
    if (card == null || state.status != ScanStatus.matched) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final repository = await ref.read(collectionRepositoryProvider.future);
    await repository.addOrIncrement(
      CollectionEntry(
        passcode: card.passcode,
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

    state = state.copyWith(
      status: ScanStatus.confirmed,
      clearMatchedCard: true,
      clearCandidates: true,
      lastConfirmedPasscode: card.passcode,
      agreementBuffer: const [],
      artAgreementBuffer: const [],
      emptyFrameCount: 0,
    );
  }

  /// Discards the current match/unknown/candidates result without writing, and
  /// debounces any resolved card so it isn't immediately re-detected.
  void dismiss() {
    final passcode = state.matchedCard?.passcode ?? state.unknownPasscode;
    _stopOcr();
    state = state.copyWith(
      status: ScanStatus.detecting,
      clearMatchedCard: true,
      clearUnknownPasscode: true,
      clearCandidates: true,
      lastConfirmedPasscode: passcode,
      agreementBuffer: const [],
      artAgreementBuffer: const [],
      emptyFrameCount: 0,
    );
  }

  /// Retries after a camera error by rebuilding the camera pipeline.
  void retry() {
    _stopOcr();
    state = _initialState();
    ref.invalidate(cameraServiceProvider);
    ref.invalidate(scanCameraProvider);
    ref.invalidate(passcodeReadingsProvider);
    ref.invalidate(artReadingsProvider);
  }
}
