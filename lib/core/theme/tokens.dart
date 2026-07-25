import 'package:flutter/material.dart';

/// Design direction: dark-first, high-contrast, minimal. A single accent
/// color, generous spacing, large tap targets — this app is used one-handed
/// while holding a stack of cards in the other hand.
///
/// Named constants live here so the rest of the app never scatters magic
/// numbers or colors through widget code.

class AppSpacing {
  const AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

class AppRadius {
  const AppRadius._();

  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
}

class AppTapTarget {
  const AppTapTarget._();

  /// Minimum tap target edge length. Larger than Material's 48dp default
  /// because the app is operated one-handed while holding cards.
  static const double minSize = 56;
}

/// The app's color surfaces, as a [ThemeExtension] so a single set of named
/// tokens resolves to either palette. Widgets read `AppPalette.of(context).x`
/// rather than a const — that indirection is what makes the light/dark setting
/// (step 9) possible, since otherwise the dark values are baked into widget code.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.accent,
    required this.onSurface,
    required this.onSurfaceMuted,
    required this.divider,
  });

  final Color background;
  final Color surface;
  final Color surfaceRaised;

  /// The single accent color used throughout the app.
  final Color accent;

  final Color onSurface;
  final Color onSurfaceMuted;
  final Color divider;

  static const AppPalette dark = AppPalette(
    background: Color(0xFF0B0B0D),
    surface: Color(0xFF17171B),
    surfaceRaised: Color(0xFF1F1F24),
    accent: Color(0xFFE0B341),
    onSurface: Color(0xFFF2F2F2),
    onSurfaceMuted: Color(0xFFA0A0A8),
    divider: Color(0xFF2A2A30),
  );

  /// The light counterpart. The accent is a deeper gold than the dark
  /// palette's `0xFFE0B341` — that value is tuned for contrast against near
  /// black and fails legibility as text or a border on a light surface.
  static const AppPalette light = AppPalette(
    background: Color(0xFFF6F6F8),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFEBEBEF),
    accent: Color(0xFF8A6410),
    onSurface: Color(0xFF16161A),
    onSurfaceMuted: Color(0xFF5B5B66),
    divider: Color(0xFFD7D7DE),
  );

  /// Falls back to [dark] rather than asserting: several widget tests pump a
  /// bare `MaterialApp` with no theme, and the app is dark-first anyway, so an
  /// unregistered extension should render the default look, not crash.
  static AppPalette of(BuildContext context) =>
      Theme.of(context).extension<AppPalette>() ?? dark;

  @override
  AppPalette copyWith({
    Color? background,
    Color? surface,
    Color? surfaceRaised,
    Color? accent,
    Color? onSurface,
    Color? onSurfaceMuted,
    Color? divider,
  }) {
    return AppPalette(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      accent: accent ?? this.accent,
      onSurface: onSurface ?? this.onSurface,
      onSurfaceMuted: onSurfaceMuted ?? this.onSurfaceMuted,
      divider: divider ?? this.divider,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onSurface: Color.lerp(onSurface, other.onSurface, t)!,
      onSurfaceMuted: Color.lerp(onSurfaceMuted, other.onSurfaceMuted, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
    );
  }
}

/// Colors for the compact condition chips, keyed by the short code
/// (MT/NM/EX/GD/LP/PL/PO) matching `CardCondition.shortCode`.
class ConditionChipColors {
  const ConditionChipColors._();

  static const Map<String, Color> byShortCode = {
    'MT': Color(0xFF2FBF71),
    'NM': Color(0xFF7FD858),
    'EX': Color(0xFFC7D858),
    'GD': Color(0xFFE0B341),
    'LP': Color(0xFFE08B34),
    'PL': Color(0xFFE0602F),
    'PO': Color(0xFFC13535),
  };

  /// Label ink for a *selected* chip. Fixed, not palette-derived: the fills
  /// above are mid-to-light in both themes, so the label must stay dark in
  /// light mode too — using the palette's background would put near-white text
  /// on a pale green chip.
  static const Color onSelected = Color(0xFF0B0B0D);
}

/// The home screen is four large tiles: Log Cards, My Collection,
/// Statistics, Settings.
class HomeMenuTokens {
  const HomeMenuTokens._();

  static const int tileCount = 4;
  static const double tileSpacing = AppSpacing.md;
}

/// Sizes for [CardThumbnail], keyed by where it's rendered.
class CardThumbnailSizes {
  const CardThumbnailSizes._();

  static const double list = 48;
  static const double detail = 200;
}

/// Geometry of one collection list row. The row reads left-to-right as
/// grade → art → name/set → quantity → actions, with the three action buttons
/// stacked in a single column on the right (add, remove, delete).
class CollectionTileTokens {
  const CollectionTileTokens._();

  /// Fixed width for the quantity slot, so the action column stays put as the
  /// count grows from 1 to 99 instead of shifting the row's right edge.
  static const double quantityWidth = 28;

  /// The stacked action buttons are held below the app's usual 48pt target:
  /// three of them at full size make the row twice the height of its artwork.
  /// The row itself stays well above [AppTapTarget.minSize], and each button
  /// keeps its own ripple, so they remain comfortably tappable.
  static const double actionButtonSize = 36;
  static const double actionIconSize = 22;
}

/// Geometry of the shared set/expansion search box.
class PrintingPickerTokens {
  const PrintingPickerTokens._();

  /// Cap on the results list so the box can open inside a bottom sheet or the
  /// scan review panel without pushing the confirm button off-screen. Beyond
  /// this the list scrolls.
  static const double maxListHeight = 168;
}

/// Tuning constants for the continuous-scan pipeline. See
/// `.claude/skills/scan-pipeline.md` for the rationale behind each value —
/// these are behavioural knobs, kept named here rather than as scattered
/// literals so the state machine reads declaratively.
class ScanTuning {
  const ScanTuning._();

  /// Consecutive frames that must agree on the same 8-digit read before it is
  /// accepted (the spec's N). Rejects motion blur / one-off misreads.
  static const int agreementFrames = 3;

  /// The artwork counterpart of [agreementFrames]: consecutive frames whose
  /// nearest artwork candidate must be the same card (and within
  /// [ArtMatchTuning.autoMatchMaxDistance]) before it is auto-presented for
  /// review. Guards the primary path against a one-off unstable top hit.
  ///
  /// Held to 2 (not 3): sleeved cards flicker frame-to-frame under glare, and
  /// demanding three identical top hits made real cards very hard to lock on.
  /// The non-negotiable user-confirm gate still catches a bad two-frame lock.
  static const int artAgreementFrames = 2;

  /// Empty frames (no card / no confident match) required after a confirm
  /// before the same card may be logged again (the spec's M). Without this, one
  /// card logs dozens of times in a couple of seconds. Shared by both paths.
  static const int debounceEmptyFrames = 5;

  /// Minimum wall-clock gap between OCR passes. The bottleneck is the human
  /// flipping cards, so we optimize for stability over raw throughput
  /// (~1 card/second) and avoid burning battery on every camera frame.
  static const Duration frameInterval = Duration(milliseconds: 300);
}

/// Geometry of the on-screen reticle that guides the user to frame the *whole*
/// card so its artwork fills the box (the primary, artwork-first path). The
/// height follows the standard card aspect ratio; the box is centered.
class ScanReticleTokens {
  const ScanReticleTokens._();

  /// Guide-box width as a fraction of the preview's width. Height is derived
  /// from [cardAspectRatio] so the outline matches a real card.
  static const double widthFraction = 0.78;

  /// A standard Yu-Gi-Oh card is 59 mm x 86 mm (width / height).
  static const double cardAspectRatio = 59 / 86;

  /// Never let the derived height exceed this fraction of the preview, so the
  /// guide always leaves room for the status banner and the bottom help/review
  /// panels — held below the earlier 0.7 so the reticle clears the "three ways
  /// to log a card" help box on shorter screens.
  static const double maxHeightFraction = 0.62;

  static const double borderWidth = 3;
  static const double cornerRadius = AppRadius.md;
}

/// Geometry of the small centered box for the on-demand passcode-OCR fallback.
/// Deliberately small and centered (not the big card guide): the user holds the
/// phone at a medium distance (~10 cm) and aims just the 8-digit code at the
/// screen's centre, so the lens keeps focus on the small text instead of the
/// whole card.
class ScanPasscodeReticleTokens {
  const ScanPasscodeReticleTokens._();

  /// Box size as fractions of the preview's width/height. Wide and short, the
  /// shape of a single row of eight digits. Kept tight so it frames only the
  /// passcode and not the neighbouring "1st Edition" / set-code text.
  static const double widthFraction = 0.42;
  static const double heightFraction = 0.07;

  static const double borderWidth = 3;
  static const double cornerRadius = AppRadius.sm;
}

/// Type sizes for the scan screen's "three ways to log a card" help box. Held
/// one step below the app's body text (and its icons shrunk to match) so the box
/// stays compact over the viewfinder — it is guidance, not primary content, and
/// it can be switched off entirely in Settings.
class ScanHelpTokens {
  const ScanHelpTokens._();

  static const double titleFontSize = 13;
  static const double lineFontSize = 12;
  static const double iconSize = 16;
}

/// How the on-screen guide box relates to the region the detector searches.
class ScanDetectionTokens {
  const ScanDetectionTokens._();

  /// Slack around the reticle when it is mapped into frame coordinates, as a
  /// fraction of the reticle's own size. Generous on purpose: the guide box is
  /// advice, and a card held a little large should still be found rather than
  /// silently dropped for overhanging it.
  static const double reticleRoiMargin = 0.15;
}

/// Gates and weights for choosing which quadrilateral in a frame is the card.
///
/// These live here rather than private to `opencv_card_detector.dart` because
/// the decision logic they drive was deliberately extracted into
/// `lib/features/scan/card_quad.dart` so it can be host-tested — the detector
/// itself can't be, since the OpenCV native library doesn't load off-device.
/// Anything only the native pipeline names (working resolution, kernel sizes,
/// approx epsilons) stays private in the detector.
class CardDetectionTuning {
  const CardDetectionTuning._();

  /// How far a candidate's width/height ratio may sit from a real card's, as a
  /// factor either way. Tolerates the foreshortening of a card held at a
  /// moderate angle while rejecting a square coaster or a long desk edge.
  static const double aspectTolerance = 1.35;

  /// Quad area / (mean width x mean height). 1.0 is a parallelogram; a blob
  /// whose four "corners" don't describe a rectangle scores far lower. This is
  /// what rejects merged card-plus-background contours.
  static const double minRectangularity = 0.82;

  /// Product of the two opposite-side length ratios. Guards against a quad with
  /// one wildly longer side — extreme perspective, or two objects' edges
  /// stitched into one contour.
  static const double minSideBalance = 0.72;

  /// Maximum in-plane rotation of the card. Corner ordering keys off the
  /// coordinate sum and difference, which starts mis-assigning corners past
  /// roughly this angle — and a mis-assigned corner warps the card rotated or
  /// mirrored, which looks like a perfectly good detection and hashes to
  /// nonsense. Rejecting is much better than silently mis-warping.
  static const double maxTiltDegrees = 25;

  /// Area band, as a fraction of the *search region* (not the whole frame): a
  /// card the user has framed in the guide box fills most of it.
  static const double minRoiAreaFraction = 0.20;
  static const double maxRoiAreaFraction = 1.05;

  /// The candidate area fraction that earns a full fill score.
  static const double targetRoiAreaFraction = 0.75;

  /// Slack, as a fraction of the image, allowed when testing that a candidate
  /// lies inside the search region — a card pressed right against the guide box
  /// shouldn't be thrown away over a pixel.
  static const double searchRoiSlack = 0.02;

  /// A nested quad is preferred over the one containing it only when it is at
  /// least this fraction of its area. A sleeve/card pair sits around 0.85–0.92.
  static const double innerQuadMinAreaRatio = 0.78;

  /// …and the descent runs **once**. Canny-plus-dilate turns every edge into a
  /// band, and a card carries a printed inner border at roughly 0.81 of its own
  /// area — overlapping the sleeve ratio above. An unbounded descent therefore
  /// walks sleeve → card → inner border and shrinks the warp by ~11% linear,
  /// which is a plausible-looking detection with a systematically wrong crop.
  /// One step is exactly "a sleeve may hide the card"; anything further is the
  /// card's own artwork furniture.
  static const int maxNestedDescents = 1;

  /// Two quads this close in area, with near-identical centres, are the two
  /// sides of one dilated edge band rather than two real rectangles. Collapsed
  /// to one (the outer) before the sleeve rule, so a duplicate can't consume
  /// the single permitted descent.
  static const double duplicateAreaRatio = 0.95;
  static const double duplicateCentreFraction = 0.02;

  /// Minimum overall shape score. Kept low deliberately: the hard gates above
  /// do the rejecting, and the score exists mainly to *rank* survivors. A high
  /// bar here would trade the old failure ("recognises the wrong thing") for a
  /// worse one ("scanning does nothing").
  static const double minScore = 0.35;

  /// Score weights, summing to 1.
  static const double aspectWeight = 0.35;
  static const double rectangularityWeight = 0.25;
  static const double fillWeight = 0.20;
  static const double centreWeight = 0.20;
}

/// The live outline drawn over the preview when a card is detected — the
/// feedback that tells the user the app has actually locked on, rather than
/// leaving them guessing at a static guide box.
class ScanOutlineTokens {
  const ScanOutlineTokens._();

  /// How long the outline takes to glide from one detection to the next (and to
  /// fade in or out). Detections arrive on the camera throttle
  /// ([ScanTuning.frameInterval]), so without interpolation the outline would
  /// visibly strobe between positions; matching that interval means each
  /// detection has just about arrived at its target when the next one lands.
  static const Duration transition = Duration(milliseconds: 260);

  static const double cardStrokeWidth = 2;

  /// The artwork box is drawn heavier than the card outline: it is the region
  /// actually being hashed, so it is what the user should be framing.
  static const double artStrokeWidth = 3;

  /// Alpha of the wash inside the artwork box.
  static const double artFillOpacity = 0.14;
}

/// Type for the developer diagnostics readout on the scan screen. Monospace and
/// small: it is a dense column of passcodes and distances that must line up,
/// and it sits above the status banner without crowding the reticle.
class ScanDiagnosticsTokens {
  const ScanDiagnosticsTokens._();

  static const double fontSize = 12;
  static const String fontFamily = 'monospace';
}

/// Tuning for the pHash artwork-match fallback (step 8). A runtime pHash of a
/// handheld frame is not bit-identical to the index (built from clean CDN art),
/// so matching ranks the [candidateCount] nearest cards within
/// [maxHammingDistance] and lets the user pick — never auto-logs.
class ArtMatchTuning {
  const ArtMatchTuning._();

  /// How many nearest candidates to present for the user to choose from.
  static const int candidateCount = 5;

  /// Maximum Hamming distance (of 64) still considered a plausible match. The
  /// clean-source gap measured 0 in the reproducibility spike; this budget is
  /// headroom for handheld glare/angle/crop imprecision. Governs the manual
  /// "show me the alternatives" candidate list. Beyond it we show nothing rather
  /// than a misleading guess.
  ///
  /// Widened to 18 for the sleeve case: a sleeve adds glare and a margin the
  /// perspective warp can latch onto, pushing a true match's distance up, so the
  /// manual candidate list needs the extra headroom to still surface the card.
  static const int maxHammingDistance = 18;

  /// The tight gate for the *automatic* primary path: only auto-present a single
  /// top match when it is at least this close across [ScanTuning.artAgreementFrames]
  /// frames. Deliberately tighter than [maxHammingDistance] — an automatic guess
  /// must be more confident than one the user explicitly asked to see.
  ///
  /// Raised from 10 to 13: sleeved cards' true matches commonly land at 11–13,
  /// which the old gate discarded as an empty frame (so scanning "did nothing").
  /// Still stricter than [maxHammingDistance], and every auto-present is
  /// user-confirmed before anything is written.
  static const int autoMatchMaxDistance = 13;

  /// The card artwork box as normalized fractions of the *upright* card rect,
  /// approximating a standard (non-Pendulum) frame's art window — the region the
  /// index's cropped art was taken from. Applied to the captured luma before
  /// hashing. Pendulum/full-art frames crop imperfectly; acceptable for a
  /// fallback that the user still confirms.
  ///
  /// MUST stay in sync with `ART_BOX_ROI` in `tools/build_hash_index.py`: the
  /// index hashes exactly this fractional region of a clean upright card, so
  /// the runtime has to hash the same region of the card it captured.
  static const Rect artBoxRoi = Rect.fromLTRB(0.09, 0.19, 0.91, 0.68);

  /// Where in the frame a card is looked for, as fractions of the *upright*
  /// camera frame. The user is told to put the card in the reticle, which is
  /// comfortably inside this region for every plausible preview aspect ratio
  /// (the reticle is at most 0.78 x 0.62 of the viewport, and the preview is a
  /// `BoxFit.cover` crop of the frame, never a letterbox).
  ///
  /// Candidate quads outside it are discarded, which is what stops a table
  /// edge, a keyboard or the neighbouring card in the stack from being warped
  /// as if it were the card — the failure the user hit on a non-monochromatic
  /// surface. It also excludes the frame border itself, which is otherwise a
  /// perfect, always-present rectangle.
  static const Rect cardSearchRoi = Rect.fromLTRB(0.04, 0.04, 0.96, 0.96);
}
