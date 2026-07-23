#!/usr/bin/env python3
"""Dump pHash validation fixtures for the Dart-side reproducibility spike (step 8).

Read-only sibling of ``build_hash_index.py``. Does NOT hit the network — it reuses
the already-downloaded cropped art in ``tools/.image_cache/`` and the shipped
``assets/card_hashes.json``. It emits two tiers of fixtures the Flutter tests load
to prove the Dart pHash reproduces Python ``imagehash.phash``:

* **Tier 1 — algorithm exactness.** The PIL ``convert('L').resize((32,32), LANCZOS)``
  array, so the Dart test can feed identical 32x32 pixels into its DCT -> median ->
  bit-pack path and assert an *exact* match (Hamming distance 0) against the index.
  Isolates the deterministic arithmetic from the (non-reproducible) resize.
* **Tier 2 — end-to-end gap.** The full-resolution luma (PIL ``convert('L')``),
  gzip-compressed, so the Dart test runs its *own* resize + DCT and measures the
  Hamming gap the handheld/resize differences introduce. Sets ``maxHammingDistance``.

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

HASH_SIZE = 8
IMG_SIZE = HASH_SIZE * 4  # 32, matches imagehash highfreq_factor=4

REPO = Path(__file__).resolve().parent.parent
CACHE = REPO / "tools" / ".image_cache"
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


def main() -> int:
    import imagehash
    from PIL import Image

    hashes = load_index()
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "phash_tier2").mkdir(parents=True, exist_ok=True)

    # ---- Tier 1: 32x32 'L' arrays + expected hashes ---------------------------
    tier1 = {"img_size": IMG_SIZE, "hash_size": HASH_SIZE, "samples": []}
    for pc in TIER1_PASSCODES:
        if pc not in hashes:
            raise SystemExit(f"{pc} not in index")
        with Image.open(cache_path(pc)) as img:
            expected = str(imagehash.phash(img, hash_size=HASH_SIZE))
            if expected != hashes[pc]:
                raise SystemExit(f"{pc}: recomputed {expected} != index {hashes[pc]}")
            small = img.convert("L").resize((IMG_SIZE, IMG_SIZE), Image.Resampling.LANCZOS)
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

    # ---- Tier 2: full-resolution luma, gzipped, + manifest --------------------
    manifest = {"hash_size": HASH_SIZE, "samples": []}
    for pc in TIER2_PASSCODES:
        with Image.open(cache_path(pc)) as img:
            expected = str(imagehash.phash(img, hash_size=HASH_SIZE))
            gray = img.convert("L")
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
