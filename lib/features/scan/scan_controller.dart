import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/theme/tokens.dart';
import '../../data/repositories/card_repository.dart';
import '../../data/repositories/collection_repository.dart';
import '../../models/card_condition.dart';
import '../../models/card_edition.dart';
import '../../models/collection_entry.dart';
import '../../models/ygo_card.dart';
import '../collection/collection_providers.dart';
import 'art_providers.dart';
import 'scan_providers.dart';
import 'scan_state.dart';

part 'scan_controller.g.dart';

/// Drives the continuous-scan state machine off the [passcodeReadings] stream.
/// Modeled on `InitialSyncController`: an immutable state class plus a notifier
/// that owns all transition logic (none of it in a `build()` method).
///
/// The rules it enforces come from `.claude/skills/scan-pipeline.md`:
/// N consecutive agreeing reads before a match, no pad/truncate, M empty
/// frames of debounce after a confirm, and — the non-negotiable one — nothing
/// is written until the user has reviewed and confirmed it.
@riverpod
class ScanController extends _$ScanController {
  @override
  ScanState build() {
    ref.listen(passcodeReadingsProvider, (previous, next) {
      next.when(
        data: (reading) => _onReading(reading.passcode),
        error: (error, _) =>
            state = state.copyWith(status: ScanStatus.error, error: error),
        loading: () {},
      );
    });
    return const ScanState(status: ScanStatus.detecting);
  }

  void _onReading(String? read) {
    final s = state;
    // Frozen while a result awaits the user, an artwork match is running or
    // awaiting a pick, or after a camera error.
    if (s.status == ScanStatus.matched ||
        s.status == ScanStatus.unknown ||
        s.status == ScanStatus.matching ||
        s.status == ScanStatus.candidates ||
        s.status == ScanStatus.error) {
      return;
    }

    if (read == null) {
      final empties = s.emptyFrameCount + 1;
      state = s.copyWith(
        status: ScanStatus.detecting,
        agreementBuffer: const [],
        emptyFrameCount: empties,
        // Once the card has been gone long enough, allow the last confirmed
        // passcode to be scanned again.
        clearLastConfirmedPasscode:
            empties >= ScanTuning.debounceEmptyFrames,
      );
      return;
    }

    // A card is in view again — reset the empty-frame debounce.
    // The just-handled passcode stays rejected until the frame goes empty.
    if (read == s.lastConfirmedPasscode) {
      state = s.copyWith(status: ScanStatus.detecting, emptyFrameCount: 0);
      return;
    }

    // Disagreement with the run in progress: discard both and keep reading.
    if (s.agreementBuffer.isNotEmpty && s.agreementBuffer.last != read) {
      state = s.copyWith(
        status: ScanStatus.reading,
        agreementBuffer: const [],
        emptyFrameCount: 0,
      );
      return;
    }

    final buffer = [...s.agreementBuffer, read];
    state = s.copyWith(
      status: ScanStatus.reading,
      agreementBuffer: buffer,
      emptyFrameCount: 0,
    );
    // Trigger the lookup exactly once, on the frame that reaches N.
    if (buffer.length == ScanTuning.agreementFrames) {
      _lookup(read);
    }
  }

  Future<void> _lookup(String passcode) async {
    final repository = await ref.read(cardRepositoryProvider.future);
    final card = await repository.getByPasscode(passcode);
    // The user may have already acted, or a disagreement moved us on.
    if (state.status != ScanStatus.reading) return;

    if (card == null) {
      state = state.copyWith(
        status: ScanStatus.unknown,
        unknownPasscode: passcode,
        agreementBuffer: const [],
        ocrFailureStreak: state.ocrFailureStreak + 1,
      );
    } else {
      state = state.copyWith(
        status: ScanStatus.matched,
        matchedCard: card,
        agreementBuffer: const [],
        condition: CardCondition.nearMint,
        edition: CardEdition.unlimited,
        quantity: 1,
        ocrFailureStreak: 0,
      );
    }
  }

  void setCondition(CardCondition condition) =>
      state = state.copyWith(condition: condition);

  void setEdition(CardEdition edition) =>
      state = state.copyWith(edition: edition);

  void setQuantity(int quantity) {
    if (quantity < 1) return;
    state = state.copyWith(quantity: quantity);
  }

  /// The step-8 fallback: hash the current frame's artwork and rank it against
  /// the pHash index, so a card whose passcode OCR can't read is still findable.
  /// Triggered by the user (the zero-digit miss never leaves [detecting], so
  /// this isn't driven off [ScanState.ocrFailureStreak]). Presents ranked
  /// candidates for the user to pick — never auto-logs, since a handheld pHash
  /// is only approximate. Falls back to [ScanStatus.unknown] (search by name)
  /// when nothing ranks close enough.
  Future<void> matchByArtwork() async {
    final s = state;
    if (s.status != ScanStatus.detecting &&
        s.status != ScanStatus.reading &&
        s.status != ScanStatus.unknown) {
      return;
    }
    state = s.copyWith(status: ScanStatus.matching, agreementBuffer: const []);

    final matcher = await ref.read(artMatcherProvider.future);
    final candidates = await matcher.match();
    // The user may have dismissed while the frame was hashing.
    if (state.status != ScanStatus.matching) return;

    state = candidates.isEmpty
        ? state.copyWith(status: ScanStatus.unknown)
        : state.copyWith(
            status: ScanStatus.candidates,
            candidates: candidates,
          );
  }

  /// Promotes a picked artwork candidate into the same review gate a scanned
  /// match uses, so it funnels through [confirm] with defaults reset.
  void selectCandidate(YgoCard card) {
    if (state.status != ScanStatus.candidates) return;
    state = state.copyWith(
      status: ScanStatus.matched,
      matchedCard: card,
      clearCandidates: true,
      clearUnknownPasscode: true,
      condition: CardCondition.nearMint,
      edition: CardEdition.unlimited,
      quantity: 1,
    );
  }

  /// Writes the reviewed match to the collection, then resumes scanning with
  /// this passcode debounced. A scanned quick-log carries no printing
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
        quantity: state.quantity,
        createdAt: now,
        updatedAt: now,
      ),
    );
    ref.invalidate(collectionEntriesProvider);

    state = state.copyWith(
      status: ScanStatus.confirmed,
      clearMatchedCard: true,
      lastConfirmedPasscode: card.passcode,
      agreementBuffer: const [],
      emptyFrameCount: 0,
    );
  }

  /// Discards the current match/unknown/candidates result without writing, and
  /// debounces any resolved passcode so it isn't immediately re-detected.
  void dismiss() {
    final passcode = state.matchedCard?.passcode ?? state.unknownPasscode;
    state = state.copyWith(
      status: ScanStatus.detecting,
      clearMatchedCard: true,
      clearUnknownPasscode: true,
      clearCandidates: true,
      lastConfirmedPasscode: passcode,
      agreementBuffer: const [],
      emptyFrameCount: 0,
    );
  }

  /// Retries after a camera error by rebuilding the camera pipeline.
  void retry() {
    state = const ScanState(status: ScanStatus.detecting);
    ref.invalidate(cameraServiceProvider);
    ref.invalidate(passcodeReadingsProvider);
  }
}
