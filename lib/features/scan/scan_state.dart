import '../../models/card_condition.dart';
import '../../models/card_edition.dart';
import '../../models/card_language.dart';
import '../../models/ygo_card.dart';
import 'art_matcher.dart';

/// The continuous-scan state machine's phases. Artwork recognition is the
/// automatic primary path; passcode OCR is an on-demand fallback:
/// `detecting → reading → matched → confirmed → detecting`, where `reading` now
/// means "the same card is agreeing across frames". `candidates` shows ranked
/// artwork alternatives (from the automatic match's "not the right card?" or an
/// OCR miss); `readingCode` is the on-demand OCR pass; `unknown` is an OCR read
/// that matched no card; `error` is a camera/permission failure.
enum ScanStatus {
  /// Camera live, hashing artwork, nothing agreeing yet.
  detecting,

  /// The same card has been the nearest artwork match for one or more frames;
  /// accumulating consecutive agreement.
  reading,

  /// A card agreed across enough frames (or a candidate/OCR read resolved) and
  /// awaits the user's review + confirm — the camera is ignored until they act.
  matched,

  /// A read agreed but matched no card in the local database (OCR fallback).
  unknown,

  /// The on-demand 8-digit passcode OCR pass is running (user asked to "read
  /// the code"). The artwork path is frozen while it runs.
  readingCode,

  /// Ranked artwork alternatives are shown; awaiting the user's pick.
  candidates,

  /// The user confirmed; the row was written. Transient before the debounce
  /// returns to [detecting].
  confirmed,

  /// The camera could not be started (permission denied / no camera).
  error,
}

/// Which recognition tool the user has selected. Artwork is the primary path
/// and the state every fresh visit to the scan screen starts in; picking
/// [passcode] switches the screen into 8-digit-code reading and **stays** there
/// across confirms, until the user switches back or leaves the screen (the
/// controller is autoDispose, so leaving resets it).
enum ScanMode { artwork, passcode }

/// Immutable snapshot of the scan pipeline. Hand-written (like
/// `AddCardSelection` and `InitialSyncState`) rather than freezed, matching the
/// project's controller-state convention.
class ScanState {
  const ScanState({
    required this.status,
    this.mode = ScanMode.artwork,
    this.agreementBuffer = const [],
    this.artAgreementBuffer = const [],
    this.matchedCard,
    this.matchedIndexPasscode,
    this.unknownPasscode,
    this.candidates = const [],
    this.condition = CardCondition.nearMint,
    this.edition = CardEdition.unlimited,
    this.language = kDefaultCardLanguage,
    this.printingId,
    this.quantity = 1,
    this.emptyFrameCount = 0,
    this.lastConfirmedPasscode,
    this.dismissCooldown = 0,
    this.error,
  });

  final ScanStatus status;

  /// The recognition tool in use. Sticky across confirms — see [ScanMode].
  final ScanMode mode;

  /// Consecutive equal 8-digit OCR reads seen so far (fallback path). Cleared on
  /// disagreement or once a match resolves.
  final List<String> agreementBuffer;

  /// Consecutive equal nearest-artwork passcodes seen so far (primary path).
  /// Cleared on disagreement, an empty frame, or once a match resolves.
  final List<String> artAgreementBuffer;

  /// The card shown for review in [ScanStatus.matched].
  final YgoCard? matchedCard;

  /// The **index** passcode the artwork match resolved through, when it came
  /// from artwork rather than OCR.
  ///
  /// It exists because the two namespaces genuinely differ. `assets/
  /// card_hashes.json` keys every `card_images[i].id` (14.6k entries, alt-arts
  /// included), while the app DB stores only `card_images[0]` — and
  /// `PHashArtMatcher.match` skips index passcodes the `cards` table doesn't
  /// hold. So whenever the nearest hash is an alt-art id, the resolved card's
  /// passcode is *not* the passcode arriving on the next frame's reading, and a
  /// debounce comparing them never fires: the review panel re-opened on the card
  /// just logged, which is the exact failure the debounce exists to prevent.
  /// [ScanController] suppresses on this when set, falling back to the card's
  /// own passcode for the OCR path, where the two are the same value.
  final String? matchedIndexPasscode;

  /// The unmatched passcode shown in [ScanStatus.unknown].
  final String? unknownPasscode;

  /// Ranked artwork candidates, nearest first. Set when an automatic match
  /// resolves (so "not the right card?" can surface the alternatives) and when
  /// the user asks to see candidates. Empty otherwise.
  final List<ArtCandidate> candidates;

  /// User-editable grade for the pending match (defaults to Near Mint).
  final CardCondition condition;
  final CardEdition edition;

  /// User-editable language for the pending match. Seeded from the settings
  /// default when a match resolves, then overridable in the review gate — the
  /// camera can't read a card's language, so this is picked by hand.
  final String language;

  /// The printing (set/expansion) chosen for the pending match, or null for
  /// "no specific set". Like language, the camera can't tell which reprint is in
  /// hand, so it is picked in the review gate from the card's known printings.
  final int? printingId;

  final int quantity;

  /// Empty frames (no card / no confident match) observed since the last card
  /// left view — drives the post-confirm debounce.
  final int emptyFrameCount;

  /// The passcode most recently confirmed or dismissed; rejected on re-read
  /// until whichever of the two debounces [dismissCooldown] selects has expired.
  final String? lastConfirmedPasscode;

  /// Readings still to elapse before a **dismissed** [lastConfirmedPasscode]
  /// becomes eligible again. Zero means the suppression came from a *confirm*
  /// instead, which clears only after [ScanTuning.debounceEmptyFrames] empty
  /// frames — i.e. once the card has actually left the lens.
  ///
  /// The two rules differ because the situations do. A confirm wrote a row, so
  /// the card must leave before it can write another. A dismiss wrote nothing
  /// and the user is still scanning, so this counts down on *every* reading —
  /// including ones that match the dismissed card — and the card can be picked
  /// up again without moving it.
  final int dismissCooldown;

  /// The camera error behind [ScanStatus.error].
  final Object? error;

  ScanState copyWith({
    ScanStatus? status,
    ScanMode? mode,
    List<String>? agreementBuffer,
    List<String>? artAgreementBuffer,
    YgoCard? matchedCard,
    bool clearMatchedCard = false,
    String? matchedIndexPasscode,
    String? unknownPasscode,
    bool clearUnknownPasscode = false,
    List<ArtCandidate>? candidates,
    bool clearCandidates = false,
    CardCondition? condition,
    CardEdition? edition,
    String? language,
    int? printingId,
    bool clearPrintingId = false,
    int? quantity,
    int? emptyFrameCount,
    String? lastConfirmedPasscode,
    bool clearLastConfirmedPasscode = false,
    int? dismissCooldown,
    Object? error,
    bool clearError = false,
  }) {
    return ScanState(
      status: status ?? this.status,
      mode: mode ?? this.mode,
      agreementBuffer: agreementBuffer ?? this.agreementBuffer,
      artAgreementBuffer: artAgreementBuffer ?? this.artAgreementBuffer,
      matchedCard: clearMatchedCard ? null : (matchedCard ?? this.matchedCard),
      // Cleared with the card it qualifies: they describe one match, and a
      // leftover index passcode would debounce the *next* card.
      matchedIndexPasscode: clearMatchedCard
          ? null
          : (matchedIndexPasscode ?? this.matchedIndexPasscode),
      unknownPasscode: clearUnknownPasscode
          ? null
          : (unknownPasscode ?? this.unknownPasscode),
      candidates:
          clearCandidates ? const [] : (candidates ?? this.candidates),
      condition: condition ?? this.condition,
      edition: edition ?? this.edition,
      language: language ?? this.language,
      printingId: clearPrintingId ? null : (printingId ?? this.printingId),
      quantity: quantity ?? this.quantity,
      emptyFrameCount: emptyFrameCount ?? this.emptyFrameCount,
      lastConfirmedPasscode: clearLastConfirmedPasscode
          ? null
          : (lastConfirmedPasscode ?? this.lastConfirmedPasscode),
      // Cleared alongside the passcode it qualifies, so the two can never
      // disagree about why (or whether) a card is suppressed.
      dismissCooldown: clearLastConfirmedPasscode
          ? 0
          : (dismissCooldown ?? this.dismissCooldown),
      // `error ?? this.error` alone makes an error write-once-sticky, so every
      // later transition drags it along and only a full reset can drop it.
      error: clearError ? null : (error ?? this.error),
    );
  }
}
