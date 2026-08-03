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

/// Geometry of the compact grade chip on a collection row.
///
/// Its own tokens because the chip previously had none: it was an inline
/// `Container` sized entirely by generic [AppSpacing] values and the inherited
/// body text size, so "make it a bit smaller" had nowhere to live. Only the
/// list row uses these — the detail screen's larger chip is unchanged.
class ConditionChipTokens {
  const ConditionChipTokens._();

  static const double horizontalPadding = 6;
  static const double verticalPadding = 2;

  /// One step below the default body size: the chip is a two-letter code read at
  /// a glance down a column, not prose.
  static const double fontSize = 12;

  static const double radius = 6;
}

/// Geometry of the small language flag shown on every collection surface.
///
/// Sized a step above [ConditionChipTokens.fontSize]: a regional-indicator pair
/// is drawn by the system emoji font at roughly the em box, so at the chip's
/// own size it reads noticeably smaller than the two-letter grade beside it.
class LanguageFlagTokens {
  const LanguageFlagTokens._();

  static const double fontSize = 14;

  /// The gap between the grade chip and the flag under it on a collection row.
  /// Small on purpose: the two are one block about the row's midline, not two
  /// separate columns of information.
  static const double stackGap = 4;

  /// The fallback badge, drawn for a language code that names no country
  /// (`AE`, or anything a CSV import brought in). Geometry follows the grade
  /// chip so the two read as siblings; only the ink and the outline differ.
  static const double fallbackFontSize = 11;
  static const double fallbackBorderWidth = 1;
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

  /// The collection row's artwork: 20% larger than [list]. Deliberately its own
  /// token rather than a bump to [list] — the scan review and candidate panels
  /// keep the smaller size.
  ///
  /// **The ceiling is 61.7, and it is worth knowing why.** The row's height is
  /// set by its tallest child, which is the three-button action column at
  /// `3 * CollectionTileTokens.actionButtonSize = 90`. The artwork is drawn at
  /// the 59/86 card aspect, so it reaches 90pt tall at a width of ~61.7 — below
  /// that the row's height is unchanged, above it every row in the list grows.
  /// At 57.6 (84pt tall) this is comfortably inside that budget.
  static const double collectionTile = list * 1.2;

  static const double detail = 200;
}

/// Geometry of one collection list row. The row reads left-to-right as
/// grade → art → name/set/rarity → quantity → actions, with the three action
/// buttons stacked in a single column on the right (add, remove, delete).
class CollectionTileTokens {
  const CollectionTileTokens._();

  /// The row's vertical inset, trimmed well below the horizontal
  /// [AppSpacing.md] so the row is shorter without becoming narrower.
  static const double verticalPadding = 6;

  /// Fixed width for the quantity slot, so the action column stays put as the
  /// count grows from 1 to 99 instead of shifting the row's right edge.
  static const double quantityWidth = 28;

  /// The stacked action buttons are held below the app's usual 48pt target:
  /// three of them at full size make the row twice the height of its artwork.
  /// The row itself stays well above [AppTapTarget.minSize], and each button
  /// keeps its own ripple, so they remain comfortably tappable.
  ///
  /// The button column is what sets the row's height, so this is also the knob
  /// that shortens the row: with [verticalPadding], `2*16 + 3*36 = 140` became
  /// `2*6 + 3*30 = 102` — about 19pt off the top and 19pt off the bottom.
  static const double actionButtonSize = 30;
  static const double actionIconSize = 20;
}

/// Geometry of the shared set/expansion search box.
/// Geometry of the minified collection grids.
///
/// Both modes are grids because the point of minifying is cards per screen, and
/// a row holds one card however little it says about it. The two differ only in
/// density and whether a name is captioned.
class CollectionGridTokens {
  const CollectionGridTokens._();

  /// Target cell width; the grid fits as many whole columns as this allows, so
  /// the layout adapts to the viewport instead of pinning a column count that is
  /// right on one device and wrong on the next.
  static const double artworkAndNameExtent = 116;
  static const double artworkOnlyExtent = 84;

  static const double spacing = AppSpacing.sm;

  /// Vertical room for the captioned name, on top of the artwork's own height.
  /// Two lines at the caption size plus its padding — cards with long names are
  /// the norm, not the exception ("Elemental HERO Shining Flare Wingman").
  static const double nameCaptionHeight = 34;

  static const double nameFontSize = 11;

  /// The multi-select check over a cell's artwork, and the outline of a selected
  /// cell. Both are needed in `minifyFull`, where the cell has no text at all
  /// and a corner badge alone is thin evidence that a card scrolled two rows up
  /// is still part of what Remove will take.
  static const double selectionCheckSize = 16;
  static const double selectedBorderWidth = 2;
}

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

  /// Readings a *dismissed* card stays suppressed for — counted down on every
  /// frame, empty or not.
  ///
  /// Deliberately **not** [debounceEmptyFrames], and that distinction is the
  /// whole point. The post-confirm debounce only advances on frames with no
  /// confident match, which is right after a confirm: the card must physically
  /// leave the lens before it can be logged a second time. Reusing it after a
  /// *dismiss* was a trap — the dismissed card sitting in the reticle matches
  /// every frame, so the empty-frame counter was pinned at zero and the card
  /// could never become eligible again while the user held it still. Nothing was
  /// written by a dismiss, and the user is trying to scan, so all that is needed
  /// here is enough of a gap that the review panel doesn't re-open under their
  /// thumb. Three readings is roughly a second at the camera's throttle.
  static const int dismissCooldownFrames = 3;

  /// Minimum wall-clock gap between OCR passes, in passcode mode. The
  /// bottleneck is the human flipping cards, so we optimize for stability over
  /// raw throughput (~1 card/second) and avoid burning battery on every camera
  /// frame.
  static const Duration ocrFrameInterval = Duration(milliseconds: 300);

  /// Minimum wall-clock gap between artwork-recognition passes — the primary
  /// path's cadence, and half [ocrFrameInterval].
  ///
  /// Latency, not throughput, is what this buys. A match needs
  /// [artAgreementFrames] agreeing frames, so the *wait* before anything can
  /// appear on screen is at least that many intervals; at 300ms most of the
  /// 1-2s it took to identify a card was spent with nothing computing.
  ///
  /// Three things had to be true before this could safely drop, and all three
  /// are now:
  ///  * detection runs on a worker isolate, so a faster cadence no longer
  ///    competes with Flutter painting the preview;
  ///  * [ScanPaused] genuinely pauses (it was `autoDispose` and therefore
  ///    inert), so a faster cadence isn't wasted work behind a review panel;
  ///  * `artReadings` polls [CameraService.frameSequence] rather than
  ///    subscribing to a broadcast stream, so it **cannot** build a backlog —
  ///    a pass slower than this interval simply skips frames.
  ///
  /// That last point makes this a ceiling on latency rather than a promise of
  /// throughput: the loop self-paces at `max(artFrameInterval, D)` where `D` is
  /// one detect+hash+rank pass (the diagnostics overlay's `det:` line). If `D`
  /// exceeds this, lowering it further buys nothing and detection cost is the
  /// thing to attack instead.
  static const Duration artFrameInterval = Duration(milliseconds: 150);

  /// How often the artwork pipeline looks for a fresh camera frame. Shorter than
  /// [artFrameInterval] on purpose — though only by 1.5x now, where it used to
  /// be 3x: the pipeline is self-paced (it only ranks when the camera's frame
  /// sequence has actually advanced), so a tighter poll just means a new frame
  /// is picked up promptly rather than up to a full interval late.
  static const Duration artPollInterval = Duration(milliseconds: 100);

  /// How often the camera is checked for a stalled image stream.
  static const Duration cameraWatchdogInterval = Duration(seconds: 2);

  /// No camera frame for this long, while the controller reports itself
  /// initialized, means the stream has died and the camera needs restarting.
  ///
  /// This is a mitigation for an upstream bug, not a tuning knob: the Android
  /// implementation is `camera_android_camerax`, whose image stream is known to
  /// stop delivering frames at random (flutter/flutter#152763 — an NPE in
  /// `ImageProxyHostApiImpl.close()` halts the analyzer), and whose preview can
  /// black out under `startImageStream` (flutter/flutter#27688). Neither is
  /// fixable from Dart; noticing and restarting is.
  ///
  /// Generous relative to the frame cadence (20x [artFrameInterval], 10x
  /// [ocrFrameInterval]) so a slow first frame after `initialize()`, or a device
  /// throttling under heat, is never mistaken for a stall — a needless restart
  /// costs the user a visible preview blink.
  static const Duration cameraFrameTimeout = Duration(seconds: 3);

  /// The watchdog's restart backoff doubles from [cameraWatchdogInterval] up to
  /// this, so a camera that is permanently dead (rather than merely stalled)
  /// stops churning through restarts.
  static const Duration cameraRestartMaxBackoff = Duration(seconds: 20);
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
  /// guide always leaves room for the bottom help/review panels — held below
  /// the earlier 0.7 so the reticle clears the "three ways to log a card" help
  /// box on shorter screens.
  static const double maxHeightFraction = 0.62;

  /// How far below the viewport's vertical centre the guide box sits, as a
  /// fraction of viewport height.
  ///
  /// Everything that grows down from the app bar is budgeted against
  /// `reticle.top`, and the diagnostics readout did not fit in the ~91pt a
  /// centred box left on a 393x851 phone — so its most useful lines were always
  /// the ones scrolled out of sight. Dropping the box buys that band directly.
  ///
  /// Because [reticleRectInViewport] is the single source of truth for both the
  /// drawn box and `detectionRoiInFrame`, the region actually searched follows
  /// it — which is the point, and is what the user saw as "move the white
  /// rectangle slightly lower".
  ///
  /// Deliberately **not** conditional on the diagnostics setting: the detector
  /// maps this rect on a worker isolate from the viewport size alone, so a
  /// settings-dependent reticle would have to thread that flag across the
  /// isolate boundary and would desync the drawn box from the searched region
  /// the moment it didn't. It is also better that what you watch while
  /// debugging is exactly what normal scanning does.
  ///
  /// **Capped by the bottom panels, not by taste.** `_HelpPanel` grows up from
  /// the bottom and step 11 dropped [maxHeightFraction] 0.7 -> 0.62 precisely to
  /// clear it; this spends part of that clearance. At 0.03 a 393x851 phone keeps
  /// ~12pt between the reticle and the help box; 0.043 and above overlaps.
  static const double verticalOffsetFraction = 0.03;

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
  /// fraction of the reticle's own size, so a card held a little large is still
  /// found rather than silently dropped for overhanging the guide box.
  ///
  /// Held to 0.08 rather than the earlier 0.15, for two reasons that both point
  /// the same way. The margin inflates each axis by `1 + 2m`, so area by
  /// `(1 + 2m)^2`: at 0.15 the search region was **1.69x** the reticle, which
  /// (a) re-admitted the surrounding desk into the Otsu split that sets Canny's
  /// thresholds — the very thing cropping to the guide box exists to prevent —
  /// and (b) left a card that perfectly fills the reticle at only 0.59 of the
  /// search region, below [CardDetectionTuning.targetRoiAreaFraction] (0.75), so
  /// a perfectly framed card could never earn a full fill score. At 0.08 the
  /// region is 1.35x and a filled reticle is 0.74 of it, which makes that
  /// existing target correct as written.
  ///
  /// A card framed *smaller* than the guide box is still admitted down to
  /// [CardDetectionTuning.minRoiAreaFraction] (0.20 of the region, i.e. about
  /// half the guide box's linear size).
  static const double reticleRoiMargin = 0.08;
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
  /// fade in or out). Detections arrive on the artwork throttle
  /// ([ScanTuning.artFrameInterval]), so without interpolation the outline would
  /// visibly strobe between positions; matching that interval means each
  /// detection has just about arrived at its target when the next one lands.
  ///
  /// Follows [ScanTuning.artFrameInterval] whenever that changes: a glide longer
  /// than the cadence never reaches its target before being retargeted, so the
  /// outline would trail the card permanently instead of tracking it.
  static const Duration transition = Duration(milliseconds: 160);

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

  /// Deliberately small. The readout runs to eight lines and the space it may
  /// occupy is fixed by geometry (see [reticleGap]), so the only free variables
  /// are the type size and how many of the lines are visible at once — and the
  /// whole point of a diagnostics overlay is that all of them are.
  static const double fontSize = 9;

  /// Line box as a multiple of [fontSize] — tight, since these are single-line
  /// monospace records with no descender-heavy prose.
  static const double lineHeight = 1.3;
  static const String fontFamily = 'monospace';

  /// How often the readout re-reads the camera's health. It has to tick on its
  /// own clock: a stalled camera stops the reading stream, which is exactly when
  /// the camera line must keep updating.
  static const Duration refreshInterval = Duration(milliseconds: 500);

  /// Clearance kept between the bottom of the top overlays and the top of the
  /// reticle.
  ///
  /// Load-bearing rather than cosmetic: the reticle is the one thing on screen
  /// the user has to aim through, and an unbounded column of diagnostics text
  /// grew straight down over it. The overlays are capped to the band between the
  /// app bar and this gap instead, so the guide box can never be covered.
  static const double reticleGap = AppSpacing.sm;

  /// Floor under that band, for viewports where the app bar and the reticle
  /// leave almost nothing between them (short screens, landscape, large text).
  /// Better to intrude slightly than to overflow a zero-height column.
  static const double minBandHeight = 96;

  /// Stroke for the diagnostics-only outline of the region the detector actually
  /// searches — thinner than the card outline, since it is a reference frame
  /// rather than a detection.
  static const double searchRoiStrokeWidth = 1.5;
}

/// Tuning for the pHash artwork-match fallback (step 8). A runtime pHash of a
/// handheld frame is not bit-identical to the index (built from clean CDN art),
/// so matching ranks the [candidateCount] nearest cards within
/// [maxHammingDistance] and lets the user pick — never auto-logs.
class ArtMatchTuning {
  const ArtMatchTuning._();

  /// How many nearest candidates to present for the user to choose from.
  static const int candidateCount = 5;

  /// How many unthresholded nearest hits the diagnostics overlay lists.
  static const int diagnosticsNearestCount = 3;

  /// Maximum Hamming distance (of **256**) still considered a plausible match —
  /// the budget for handheld glare, angle and crop imprecision. **The one
  /// threshold that decides whether a card is presented at all**: everything the
  /// index ranks within it is offered for review, and beyond it we show nothing
  /// rather than a misleading guess (though the user can still ask for the
  /// nearest few regardless — see `ArtMatcher.bestGuesses`).
  ///
  /// **Both thresholds here are even on purpose.** A pHash thresholds each
  /// coefficient against the *median* of the block, so exactly half the bits are
  /// set in every hash — and two equal-weight vectors always differ in an even
  /// number of positions (`|A^B| = 256 - 2|A&B|`). Verified over the shipped
  /// index: the popcount histogram is `{128: 14641}`, no exceptions. An odd
  /// threshold is therefore bit-for-bit identical to the even one below it, and
  /// the previous 64-bit pair (13/18) really behaved as 12/18.
  ///
  /// **Measured over the whole shipped index**, P(a card has *any* other card
  /// within r):
  ///
  /// | r | % of bits | P(>=1 nbr) | mean nbrs |
  /// |---|---|---|---|
  /// | 48 | 18.8% | 1.20% | 0.014 |
  /// | 72 | 28.1% | 1.37% | 0.017 |
  /// | 84 | 32.8% | 1.81% | 0.023 |
  /// | 88 | 34.4% | 4.04% | 0.047 |
  /// | 96 | 37.5% | 76.4% | 1.65 |
  ///
  /// The curve is flat to ~84 and falls off a cliff by 96, so precision in the
  /// middle does not matter; 72 sits with a wide margin on both sides. For
  /// contrast, the old 64-bit index at the *same fraction of the width* (18/64)
  /// had **100%** of cards carrying a neighbour, mean 26.3 — which is not a
  /// threshold at all, it is the whole neighbourhood, and it is why the top-5
  /// list could be five arbitrary cards.
  static const int maxHammingDistance = 72;

  /// The confidence boundary: at or inside this, an automatic match is presented
  /// as a **match**; past it, the same card is presented as a **guess**, hedged
  /// in the review gate so the user knows to check the picture.
  ///
  /// It does **not** gate whether a card is shown — [maxHammingDistance] does.
  /// It used to, and that was the defect: a card ranking 48-72 was routed into
  /// the empty-frame branch and reported as "can't identify this card", even
  /// though tapping through to the alternatives then showed the right card at
  /// the top essentially every time. Hiding a correct answer to avoid hedging
  /// about it is the wrong trade when nothing is written without a confirm.
  ///
  /// 48/256 is 18.8% of the bits, the same fraction the 64-bit index's effective
  /// gate used. Preserving the *fraction* is measured rather than assumed: the
  /// perturbations that actually matter here (an area-average resize standing in
  /// for PIL's LANCZOS, and the ~622px reference vs ~322px warp resolution gap)
  /// flip the same or a smaller share of bits at 256 as at 64. That measurement
  /// is what makes it a meaningful boundary between "clean read" and "usable but
  /// degraded", which is exactly the distinction the wording now carries.
  static const int autoMatchMaxDistance = 48;

  /// The card artwork box as normalized fractions of the *upright* card rect —
  /// the region the index hashes. Applied to the captured luma before hashing.
  /// Pendulum/full-art frames crop imperfectly; acceptable for a path the user
  /// still confirms.
  ///
  /// **Measured, not estimated.** YGOPRODeck publishes its own art crop
  /// (`image_url_cropped`, 624x624) beside the full render (`image_url`,
  /// 813x1185); aligning one inside the other by normalized cross-correlation
  /// locates the window directly, and across a random sample it converges at NCC
  /// 0.996-0.999 on (96, 215) size **622x622** — square, with 96px of left margin
  /// and 95px of right, i.e. horizontally centred as a real card's art window
  /// must be.
  ///
  /// The previous value, `(0.09, 0.19, 0.91, 0.68)`, has aspect 1.147. That is
  /// what made `OpenCvCardDetector._findArtBox` dead code: it rejects candidates
  /// whose aspect errs by more than `_artBoxAspectTolerance` (1.12), and the true
  /// window's error against it is 1.147 — so the art-box correction could never
  /// fire on a standard card, on any device.
  ///
  /// MUST stay in sync with `ART_BOX_ROI` in `tools/build_hash_index.py`: the
  /// index hashes exactly this fractional region of a clean upright card, so the
  /// runtime has to hash the same region of the card it captured. `HashIndex`
  /// enforces it at startup from the `roi` header the index carries, and
  /// `hash_index_asset_test.dart` enforces it at build time.
  static const Rect artBoxRoi = Rect.fromLTRB(0.1181, 0.1814, 0.8831, 0.7063);

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

/// Thresholds for the per-frame image-quality gate (`frame_quality.dart`).
///
/// The gate exists because a blurred or glare-blown crop hashes to something
/// genuinely far from the indexed art, and the pipeline previously reported that
/// identically to "there is no card here" — so the user was told to point at a
/// card that was already centred, rectified and hashed.
///
/// This is a **rejection gate, not preprocessing**, which is the distinction
/// `.claude/skills/scan-pipeline.md` draws when it says not to add aggressive
/// image preprocessing before there are real failure samples to test against.
/// Discarding a frame we cannot judge is the conservative half of that rule;
/// transforming pixels to make them match is the half still deferred.
class FrameQualityTuning {
  const FrameQualityTuning._();

  /// Minimum variance of the 3x3 Laplacian over the art crop.
  ///
  /// Deliberately low. The measure is scene-dependent in absolute terms — a busy
  /// artwork out-scores a plain one at identical focus — so this is set to catch
  /// only frames that are *obviously* smeared, not to grade sharpness. Being too
  /// strict here stops recognition working at all, which is why
  /// [maxConsecutiveSkips] exists as a floor under it. Re-tune from the
  /// diagnostics overlay's `qual:` line on real cards.
  static const double minSharpness = 40;

  /// Maximum fraction of the art crop allowed to sit at [glareLevel] or above.
  ///
  /// Artwork legitimately contains small bright areas (a white border detail, a
  /// light background, Blue-Eyes), so this is not "any clipping" — it is "enough
  /// of the window is blown that the structure under it is gone". 8% of a
  /// 622x622-equivalent window is a substantial patch.
  static const double maxGlareFraction = 0.08;

  /// Glare must fall back to this before exposure compensation reverses. Strictly
  /// below [maxGlareFraction] so the two form a hysteresis band — equal
  /// thresholds would oscillate on the boundary and re-meter the camera every
  /// frame, on the least reliable part of the stack.
  static const double glareRecoveryFraction = 0.04;

  /// Luma at or above which a pixel counts as a clipped highlight.
  static const int glareLevel = 250;

  /// Sample every Nth **row** (all columns within it). Halves the work for a
  /// measurement that only has to be right to within a threshold.
  ///
  /// Rows rather than a strided grid on purpose — see `assessCrop`. A lattice
  /// that strides both axes aliases against periodic detail and can score the
  /// sharpest possible frame as perfectly blurred.
  static const int sampleStride = 2;

  /// After this many frames rejected in a row, the gate stops rejecting and the
  /// frame is processed normally.
  ///
  /// **Not optional.** [minSharpness] and [maxGlareFraction] are absolute
  /// thresholds on a scene-dependent measure, and if they are wrong for some
  /// device or some lighting the failure mode without this is *recognition never
  /// works again* with every on-screen signal green — precisely the class of
  /// silent wedge the detector-isolate watchdog exists to prevent. With it, a
  /// miscalibrated threshold degrades to the old behaviour at a small throughput
  /// cost instead.
  static const int maxConsecutiveSkips = 6;

  /// Consecutive frames where a card is detected but nothing ranks close enough
  /// before the banner offers the best guesses. Roughly a second at
  /// [ScanTuning.artFrameInterval] — long enough not to fire while the user is
  /// still bringing the card into frame, short enough to beat giving up.
  static const int unmatchedStreakForHint = 6;

  /// One step of exposure compensation, in EV.
  static const double exposureStep = 0.3;

  /// How far down exposure compensation may go. Bounded because the descriptor
  /// tolerates darkening but not *underexposure*: past this the artwork's own
  /// midtones start quantising away, which costs the same structure the glare
  /// was destroying.
  static const double exposureFloor = -1.5;

  /// Minimum wall-clock gap between exposure changes. Each one is a platform
  /// round trip that re-meters the camera; at the artwork cadence an ungated
  /// loop would issue several per second.
  static const Duration exposureInterval = Duration(milliseconds: 700);
}
