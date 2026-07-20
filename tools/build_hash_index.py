"""Build the perceptual-hash art index for OCR-miss fallback matching.

Not implemented yet — this is build order step 6 (see CLAUDE.md). When
built, this script will:
  1. Download all card art referenced by `cards.image_url` in the synced
     database.
  2. Compute a perceptual hash (pHash) for each image.
  3. Emit `assets/card_hashes.json` mapping passcode -> pHash, consumed by
     the scan pipeline's art-matching fallback (see
     .claude/skills/scan-pipeline.md).
"""

if __name__ == "__main__":
    raise NotImplementedError("build_hash_index.py lands in a later session")
