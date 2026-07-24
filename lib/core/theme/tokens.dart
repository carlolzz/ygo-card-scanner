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

  /// Once the user triggers the on-demand passcode fallback, give up and return
  /// to artwork scanning if no 8-digit read agrees within this many processed
  /// frames (~12s at [frameInterval]), so a glare-blocked code doesn't spin
  /// forever.
  static const int ocrTimeoutFrames = 40;

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
  static const Rect artBoxRoi = Rect.fromLTRB(0.09, 0.19, 0.91, 0.68);
}
