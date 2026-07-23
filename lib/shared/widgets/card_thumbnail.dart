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
  });

  final String? localImagePath;
  final double size;

  @override
  Widget build(BuildContext context) {
    final path = localImagePath;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: SizedBox(
        width: size,
        height: size,
        child: path == null
            ? _placeholder(context)
            : Image.file(
                File(path),
                fit: BoxFit.cover,
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
