"""Generate placeholder launcher icons for YGO Scanner.

A dark-and-gold stylised card, matching the app's dark palette
(background #0B0B0D, accent #E0B341). Deliberately font-free so it needs only
Pillow (already in tools/requirements.txt) and can't fail on a missing TrueType
font. Replace assets/icon/ with real art later and re-run the two commands below.

Produces:
  assets/icon/ygo_icon.png             1024x1024, full dark background
  assets/icon/ygo_icon_foreground.png  1024x1024, transparent (Android adaptive)

Usage:
  python tools/make_icon.py
  dart run flutter_launcher_icons
"""

from __future__ import annotations

import os

from PIL import Image, ImageDraw

SIZE = 1024
BG = (11, 11, 13, 255)  # #0B0B0D
GOLD = (224, 179, 65, 255)  # #E0B341
DARK_PANEL = (23, 23, 27, 255)  # #17171B
CARD_ASPECT = 59 / 86  # standard Yu-Gi-Oh card width / height

OUT_DIR = os.path.normpath(
    os.path.join(os.path.dirname(__file__), os.pardir, "assets", "icon")
)


def _draw_card(draw: "ImageDraw.ImageDraw", cx: float, cy: float, card_w: float) -> None:
    card_h = card_w / CARD_ASPECT
    left, top = cx - card_w / 2, cy - card_h / 2
    right, bottom = cx + card_w / 2, cy + card_h / 2
    radius = card_w * 0.10

    # Gold card body.
    draw.rounded_rectangle([left, top, right, bottom], radius=radius, fill=GOLD)
    # Dark inner frame line, so it reads as a card, not a plain slab.
    inset = card_w * 0.07
    draw.rounded_rectangle(
        [left + inset, top + inset, right - inset, bottom - inset],
        radius=radius * 0.7,
        outline=DARK_PANEL,
        width=max(1, int(card_w * 0.035)),
    )
    # Art window in the upper portion of the card.
    draw.rounded_rectangle(
        [
            left + inset * 1.7,
            top + card_h * 0.16,
            right - inset * 1.7,
            top + card_h * 0.58,
        ],
        radius=radius * 0.5,
        fill=DARK_PANEL,
    )


def _build(*, background: bool, card_w_frac: float, path: str) -> None:
    img = Image.new("RGBA", (SIZE, SIZE), BG if background else (0, 0, 0, 0))
    _draw_card(ImageDraw.Draw(img), SIZE / 2, SIZE / 2, SIZE * card_w_frac)
    img.save(path)
    print("wrote", path)


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    # Full icon fills more of the tile; the adaptive foreground is smaller so it
    # survives the circular/rounded mask's safe zone.
    _build(background=True, card_w_frac=0.44, path=os.path.join(OUT_DIR, "ygo_icon.png"))
    _build(
        background=False,
        card_w_frac=0.34,
        path=os.path.join(OUT_DIR, "ygo_icon_foreground.png"),
    )


if __name__ == "__main__":
    main()
