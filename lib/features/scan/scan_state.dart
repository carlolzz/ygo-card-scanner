import '../../models/card_condition.dart';
import '../../models/card_edition.dart';
import '../../models/ygo_card.dart';
import 'art_matcher.dart';

/// The continuous-scan state machine's phases, following
/// `.claude/skills/scan-pipeline.md`:
/// `detecting → reading → matched → confirmed → detecting`, with `unknown`
/// (a read that no card matches) and `error` (camera/permission failure)
/// as terminal-until-user-acts branches. The `matching`/`candidates` pair is
/// the step-8 artwork-match fallback the user triggers from `unknown`/`detecting`.
enum ScanStatus {
  /// Camera live, nothing conclusive read yet.
  detecting,

  /// One or more 8-digit reads seen; accumulating consecutive agreement.
  reading,

  /// A read agreed across enough frames and resolved to a card. Awaiting the
  /// user's review + confirm — the camera is ignored until they act.
  matched,

  /// A read agreed but matched no card in the local database.
  unknown,

  /// An artwork match is being computed (frame captured, hashing/ranking).
  /// Camera frozen until it resolves.
  matching,

  /// Artwork ranking produced candidates; awaiting the user's pick.
  candidates,

  /// The user confirmed; the row was written. Transient before the debounce
  /// returns to [detecting].
  confirmed,

  /// The camera could not be started (permission denied / no camera).
  error,
}

/// Immutable snapshot of the scan pipeline. Hand-written (like
/// `AddCardSelection` and `InitialSyncState`) rather than freezed, matching the
/// project's controller-state convention.
class ScanState {
  const ScanState({
    required this.status,
    this.agreementBuffer = const [],
    this.matchedCard,
    this.unknownPasscode,
    this.candidates = const [],
    this.condition = CardCondition.nearMint,
    this.edition = CardEdition.unlimited,
    this.quantity = 1,
    this.emptyFrameCount = 0,
    this.lastConfirmedPasscode,
    this.ocrFailureStreak = 0,
    this.error,
  });

  final ScanStatus status;

  /// Consecutive equal 8-digit reads seen so far. Cleared on disagreement or
  /// once a match resolves.
  final List<String> agreementBuffer;

  /// The card shown for review in [ScanStatus.matched].
  final YgoCard? matchedCard;

  /// The unmatched passcode shown in [ScanStatus.unknown].
  final String? unknownPasscode;

  /// Ranked artwork-match candidates shown in [ScanStatus.candidates], nearest
  /// first. Empty outside that state.
  final List<ArtCandidate> candidates;

  /// User-editable grade for the pending match (defaults to Near Mint).
  final CardCondition condition;
  final CardEdition edition;
  final int quantity;

  /// Empty frames observed since the last card left view — drives the
  /// post-confirm debounce.
  final int emptyFrameCount;

  /// The passcode most recently confirmed (or dismissed); rejected on re-read
  /// until the frame goes empty for [ScanTuning.debounceEmptyFrames].
  final String? lastConfirmedPasscode;

  /// How many consecutive agreed reads have failed to match a card. Reserved
  /// as the hook for step 8's pHash artwork fallback.
  final int ocrFailureStreak;

  /// The camera error behind [ScanStatus.error].
  final Object? error;

  ScanState copyWith({
    ScanStatus? status,
    List<String>? agreementBuffer,
    YgoCard? matchedCard,
    bool clearMatchedCard = false,
    String? unknownPasscode,
    bool clearUnknownPasscode = false,
    List<ArtCandidate>? candidates,
    bool clearCandidates = false,
    CardCondition? condition,
    CardEdition? edition,
    int? quantity,
    int? emptyFrameCount,
    String? lastConfirmedPasscode,
    bool clearLastConfirmedPasscode = false,
    int? ocrFailureStreak,
    Object? error,
  }) {
    return ScanState(
      status: status ?? this.status,
      agreementBuffer: agreementBuffer ?? this.agreementBuffer,
      matchedCard: clearMatchedCard ? null : (matchedCard ?? this.matchedCard),
      unknownPasscode: clearUnknownPasscode
          ? null
          : (unknownPasscode ?? this.unknownPasscode),
      candidates:
          clearCandidates ? const [] : (candidates ?? this.candidates),
      condition: condition ?? this.condition,
      edition: edition ?? this.edition,
      quantity: quantity ?? this.quantity,
      emptyFrameCount: emptyFrameCount ?? this.emptyFrameCount,
      lastConfirmedPasscode: clearLastConfirmedPasscode
          ? null
          : (lastConfirmedPasscode ?? this.lastConfirmedPasscode),
      ocrFailureStreak: ocrFailureStreak ?? this.ocrFailureStreak,
      error: error ?? this.error,
    );
  }
}
