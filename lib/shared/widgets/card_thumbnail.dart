import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// Renders a card's locally-downloaded art, or a placeholder when none has
/// been downloaded yet (or the file has since gone missing).
class CardThumbnail extends StatelessWidget {
  const CardThumbnail({
    super.key,
    required this.localImagePath,
    this.size = CardThumbnailSizes.list,
    this.aspectRatio,
    this.fit = BoxFit.cover,
  });

  final String? localImagePath;

  /// The thumbnail's width. Its height is [size] when [aspectRatio] is null
  /// (a square, the default), or `size / aspectRatio` otherwise.
  final double size;

  /// Width-over-height ratio. Null keeps the historical square; pass a card's
  /// `59 / 86` together with `fit: BoxFit.contain` to show the whole card
  /// artwork uncropped.
  final double? aspectRatio;

  /// How the image fills its box. Defaults to [BoxFit.cover] (fills, cropping
  /// overflow); use [BoxFit.contain] to show the entire image.
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final path = localImagePath;
    final ratio = aspectRatio;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: SizedBox(
        width: size,
        height: ratio == null ? size : size / ratio,
        child: path == null
            ? _placeholder(context)
            : Image.file(
                File(path),
                fit: fit,
                errorBuilder: (context, error, stackTrace) =>
                    _placeholder(context),
              ),
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    final palette = AppPalette.of(context);
    return ColoredBox(
      color: palette.surfaceRaised,
      child: Icon(
        Icons.image_not_supported_outlined,
        color: palette.onSurfaceMuted,
      ),
    );
  }
}
