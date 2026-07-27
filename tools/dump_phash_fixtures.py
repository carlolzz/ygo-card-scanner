#!/usr/bin/env python3
"""Dump pHash validation fixtures for the Dart-side reproducibility spike (step 8).

Read-only sibling of ``build_hash_index.py``. Does NOT hit the network — it reuses
the already-downloaded full card renders in ``tools/.image_cache/full/`` and the
shipped ``assets/card_hashes.json``. It emits two tiers of fixtures the Flutter
tests load to prove the Dart pHash reproduces Python ``imagehash.phash``:

* **Tier 1 — algorithm exactness.** The PIL
  ``convert('L').resize((IMG_SIZE, IMG_SIZE), LANCZOS)`` array of the art-box
  crop, so the Dart test can feed identical pixels into its DCT -> median ->
  bit-pack path and assert an *exact* match (Hamming distance 0) against the
  index. Isolates the deterministic arithmetic from the (non-reproducible) resize.
* **Tier 2 — end-to-end gap.** The cropped luma (PIL ``convert('L')``),
  gzip-compressed, so the Dart test runs its *own* resize + DCT and measures the
  Hamming gap the resize difference introduces. Informs ``maxHammingDistance``.

Both tiers crop ``ART_BOX_ROI`` first, imported from ``build_hash_index`` so
there is exactly one definition of it. That is not cosmetic: this script used to
read the *v1 cropped-art* cache and hash whole files with no crop, while the
index builder cropped the ROI out of the full render — so its own cross-check
against the index failed, and the tests passed only because they compared Dart
against each fixture's self-recorded hash rather than against the shipped index.

Usage:
    py -3.13 tools/dump_phash_fixtures.py

Outputs (committed):
    test/features/scan/fixtures/phash_tier1.json
    test/features/scan/fixtures/phash_tier2/manifest.json
    test/features/scan/fixtures/phash_tier2/<passcode>.luma.gz
"""
from __future__ import annotations

import base64
import gzip
import json
import sys
from pathlib import Path

# A fixed spread of passcodes present in both the image cache and the index.
# (Verified at author time; the script errors out loudly if any is missing.)
TIER1_PASSCODES = [
    "10000", "10000000", "10000010", "10000020", "46986414", "89631139",
    "38033121", "44508094", "74677422", "5318639", "70781052", "6983839",
]
# Kept small: the Tier-2 gap measured 0 on clean source art, so a few samples
# suffice as a regression guard (each is ~300 KB of gzipped luma).
TIER2_PASSCODES = ["46986414", "89631139", "5318639"]

# One definition of both, shared with the index builder — see the module
# docstring for why importing rather than restating is load-bearing here.
from build_hash_index import (  # noqa: E402
    ART_BOX_ROI,
    DEFAULT_HASH_SIZE,
    FULL_IMAGE_SUBDIR,
    roi_pixel_box,
)

HASH_SIZE = DEFAULT_HASH_SIZE
IMG_SIZE = HASH_SIZE * 4  # matches imagehash highfreq_factor=4

REPO = Path(__file__).resolve().parent.parent
CACHE = REPO / "tools" / ".image_cache" / FULL_IMAGE_SUBDIR
INDEX = REPO / "assets" / "card_hashes.json"
OUT = REPO / "test" / "features" / "scan" / "fixtures"


def load_index() -> dict[str, str]:
    data = json.loads(INDEX.read_text(encoding="utf-8"))
    if data.get("algorithm") != "phash" or data.get("hash_size") != HASH_SIZE:
        raise SystemExit(f"unexpected index header: {data.get('algorithm')}/{data.get('hash_size')}")
    return data["hashes"]


def cache_path(passcode: str) -> Path:
    p = CACHE / f"{passcode}.jpg"
    if not p.exists():
        raise SystemExit(f"missing cached image: {p}")
    return p


def art_crop(img):
    """The ART_BOX_ROI crop of a full card render — what the index hashes."""
    return img.crop(roi_pixel_box(img.width, img.height, ART_BOX_ROI))


def main() -> int:
    import imagehash
    from PIL import Image

    hashes = load_index()
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "phash_tier2").mkdir(parents=True, exist_ok=True)

    # ---- Tier 1: resized 'L' arrays + expected hashes -------------------------
    tier1 = {
        "img_size": IMG_SIZE,
        "hash_size": HASH_SIZE,
        "roi": list(ART_BOX_ROI),
        "samples": [],
    }
    for pc in TIER1_PASSCODES:
        if pc not in hashes:
            raise SystemExit(f"{pc} not in index")
        with Image.open(cache_path(pc)) as img:
            crop = art_crop(img)
            expected = str(imagehash.phash(crop, hash_size=HASH_SIZE))
            if expected != hashes[pc]:
                raise SystemExit(f"{pc}: recomputed {expected} != index {hashes[pc]}")
            small = crop.convert("L").resize((IMG_SIZE, IMG_SIZE), Image.Resampling.LANCZOS)
        pixels = small.tobytes()  # row-major, len == IMG_SIZE*IMG_SIZE
        assert len(pixels) == IMG_SIZE * IMG_SIZE
        tier1["samples"].append({
            "passcode": pc,
            "expectedHash": expected,
            "pixels": base64.b64encode(pixels).decode("ascii"),
        })
    (OUT / "phash_tier1.json").write_text(
        json.dumps(tier1, indent=2) + "\n", encoding="utf-8"
    )
    print(f"tier1: wrote {len(tier1['samples'])} samples")

    # ---- Tier 2: cropped-resolution luma, gzipped, + manifest -----------------
    # The *crop*, not the whole render: the Dart side calls phashFromLuma with no
    # `crop:` argument, so emitting the crop is what makes the two sides measure
    # the same function of the same pixels — and it is the region the pipeline
    # actually hashes, so the number this produces is meaningful.
    manifest = {"hash_size": HASH_SIZE, "roi": list(ART_BOX_ROI), "samples": []}
    for pc in TIER2_PASSCODES:
        with Image.open(cache_path(pc)) as img:
            crop = art_crop(img)
            expected = str(imagehash.phash(crop, hash_size=HASH_SIZE))
            gray = crop.convert("L")
            w, h = gray.size
            luma = gray.tobytes()
        assert len(luma) == w * h
        (OUT / "phash_tier2" / f"{pc}.luma.gz").write_bytes(gzip.compress(luma, 9))
        manifest["samples"].append({
            "passcode": pc, "width": w, "height": h, "expectedHash": expected,
        })
    (OUT / "phash_tier2" / "manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )
    print(f"tier2: wrote {len(manifest['samples'])} luma samples")
    return 0


if __name__ == "__main__":
    sys.exit(main())
