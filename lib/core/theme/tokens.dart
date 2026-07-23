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

class AppColors {
  const AppColors._();

  static const Color background = Color(0xFF0B0B0D);
  static const Color surface = Color(0xFF17171B);
  static const Color surfaceRaised = Color(0xFF1F1F24);

  /// The single accent color used throughout the app.
  static const Color accent = Color(0xFFE0B341);

  static const Color onSurface = Color(0xFFF2F2F2);
  static const Color onSurfaceMuted = Color(0xFFA0A0A8);
  static const Color divider = Color(0xFF2A2A30);
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

  /// Empty frames (no card detected) required after a confirm before the same
  /// passcode may be scanned again (the spec's M). Without this, one card
  /// logs dozens of times in a couple of seconds.
  static const int debounceEmptyFrames = 5;

  /// Minimum wall-clock gap between OCR passes. The bottleneck is the human
  /// flipping cards, so we optimize for stability over raw throughput
  /// (~1 card/second) and avoid burning battery on every camera frame.
  static const Duration frameInterval = Duration(milliseconds: 300);
}

/// Geometry of the on-screen reticle that guides the user to align a card's
/// bottom-left passcode. Fractions are of the preview's shortest/longest edge.
class ScanReticleTokens {
  const ScanReticleTokens._();

  static const double widthFraction = 0.7;
  static const double heightFraction = 0.16;
  static const double borderWidth = 3;
  static const double bottomInset = AppSpacing.xl;
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
  /// headroom for handheld glare/angle/crop imprecision. Beyond it we show
  /// "no artwork match" rather than a misleading guess.
  static const int maxHammingDistance = 14;

  /// The card artwork box as normalized fractions of the *upright* card rect,
  /// approximating a standard (non-Pendulum) frame's art window — the region the
  /// index's cropped art was taken from. Applied to the captured luma before
  /// hashing. Pendulum/full-art frames crop imperfectly; acceptable for a
  /// fallback that the user still confirms.
  static const Rect artBoxRoi = Rect.fromLTRB(0.09, 0.19, 0.91, 0.68);
}
