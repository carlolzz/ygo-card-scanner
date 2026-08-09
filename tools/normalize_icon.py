"""Normalize hand-drawn launcher art into the two square PNGs the build wants.

`flutter_launcher_icons` resizes its inputs to square targets, so a non-square
source is *stretched*, not letterboxed. And the two inputs have different
requirements, which is why this does not simply resize both the same way:

  ygo_icon.png            the legacy / iOS icon. Must be full-bleed and opaque:
                          `remove_alpha_ios: true` flattens transparency to
                          white, so a transparent surround becomes a white
                          border around the art.
  ygo_icon_foreground.png the Android adaptive foreground. Must be transparent,
                          and its subject must sit inside the central safe zone
                          — the launcher mask crops the outer third, and the
                          icon is animated within it on some launchers.

Both are trimmed to their own content bounding box first, so the amount of
empty canvas the artwork was drawn on stops mattering.

Usage:
  py -3 tools/normalize_icon.py path/to/icon.png path/to/foreground.png
"""

from __future__ import annotations

import argparse
import os

from PIL import Image

SIZE = 1024

# The app's dark background (`AppPalette.dark.background`). Used to pad the
# opaque icon to square, so the fill matches the artwork's own field rather
# than introducing a third colour.
BG = (11, 11, 13, 255)  # #0B0B0D

# Fraction of the adaptive canvas the foreground subject may occupy. Android
# guarantees only the central 66% of the 108dp canvas is visible on every
# launcher mask; anything outside is decoration at best.
SAFE_ZONE = 0.66


def _trim(image: Image.Image) -> Image.Image:
    """Crop away fully transparent margins."""
    bbox = image.getchannel("A").getbbox()
    return image if bbox is None else image.crop(bbox)


def _square(image: Image.Image, fill: tuple[int, int, int, int]) -> Image.Image:
    """Pad the shorter axis so the artwork keeps its aspect when resized."""
    side = max(image.size)
    canvas = Image.new("RGBA", (side, side), fill)
    canvas.alpha_composite(
        image,
        ((side - image.width) // 2, (side - image.height) // 2),
    )
    return canvas


def build_opaque_icon(source: str, destination: str) -> None:
    art = _square(_trim(Image.open(source).convert("RGBA")), BG)
    art = art.resize((SIZE, SIZE), Image.LANCZOS)
    # Flatten: any residual alpha inside the artwork would be composited
    # against white on iOS, not against the dark field it was drawn on.
    flat = Image.new("RGBA", (SIZE, SIZE), BG)
    flat.alpha_composite(art)
    flat.convert("RGB").save(destination)


def build_adaptive_foreground(source: str, destination: str) -> None:
    art = _square(_trim(Image.open(source).convert("RGBA")), (0, 0, 0, 0))
    inner = max(1, int(SIZE * SAFE_ZONE))
    art = art.resize((inner, inner), Image.LANCZOS)
    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    offset = (SIZE - inner) // 2
    canvas.alpha_composite(art, (offset, offset))
    canvas.save(destination)


def main() -> None:
    out_dir = os.path.normpath(
        os.path.join(os.path.dirname(__file__), os.pardir, "assets", "icon")
    )
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("icon", help="source art for the opaque launcher icon")
    parser.add_argument("foreground", help="source art for the adaptive foreground")
    args = parser.parse_args()

    build_opaque_icon(args.icon, os.path.join(out_dir, "ygo_icon.png"))
    build_adaptive_foreground(
        args.foreground, os.path.join(out_dir, "ygo_icon_foreground.png")
    )
    print(f"wrote {SIZE}x{SIZE} icons to {out_dir}")
    print("next: dart run flutter_launcher_icons")


if __name__ == "__main__":
    main()
