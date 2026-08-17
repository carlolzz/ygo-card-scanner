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
  ///
  /// **Null means "fill the space the parent gives me"**, which is what a grid
  /// cell needs — the fixed [SizedBox] below cannot stretch, so before this the
  /// widget could only ever be used at a size known in advance. With
  /// [aspectRatio] set it becomes an [AspectRatio] instead, so a cell of any
  /// width renders the card at its true proportions.
  final double? size;

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
    final width = size;
    final image = path == null
        ? _placeholder(context)
        : Image.file(
            File(path),
            fit: fit,
            errorBuilder: (context, error, stackTrace) => _placeholder(context),
          );
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: width == null
          // Sized by the parent — a grid cell. An [AspectRatio] rather than a
          // [SizedBox] so the cell's width drives the height.
          ? (ratio == null ? image : AspectRatio(aspectRatio: ratio, child: image))
          : SizedBox(
              width: width,
              height: ratio == null ? width : width / ratio,
              child: image,
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
