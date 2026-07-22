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
