# tools

Host-side developer tools for YGO Scanner. Not shipped in the app.

## `build_hash_index.py`

Builds `assets/card_hashes.json`, the perceptual-hash (pHash) reference index
used by the scan pipeline's OCR-miss fallback (build order step 6 / consumed
by step 8). It fetches the full card database, downloads each artwork's
*cropped* image, computes a pHash, and writes a passcode → hash map.

Every entry in a card's `card_images` array is indexed by its own `id`, so
alternate artworks are matchable and resolve to the correct printing's
passcode.

### Run

```bash
pip install -r tools/requirements.txt

python tools/build_hash_index.py --limit 20   # fast smoke run (~20 cards)
python tools/build_hash_index.py              # full index (~13k cards + alt-arts)
python tools/build_hash_index.py --incremental  # only hash passcodes not already in the output
```

Flags: `--output` (default `assets/card_hashes.json`), `--cache-dir`
(default `tools/.image_cache/`), `--workers` (default 4), `--delay`
(post-download pause, default 0.05s), `--hash-size` (default 8),
`--limit`, `--incremental`.

Downloaded images are cached under `tools/.image_cache/` (gitignored). Re-runs
reuse the cache and make **zero** network requests for already-downloaded art.

### Tests

```bash
pytest tools/test_build_hash_index.py
```

Offline — covers the pure functions (`build_image_jobs`, `build_output`); no
network or image files required.

### Output

`assets/card_hashes.json` is a **committed, generated artifact** (bundled into
the app at runtime, so it must be present at build time and registered under
`flutter: assets:` in `pubspec.yaml`). Regenerate it when the card database
changes. Format:

```json
{
  "version": 1,
  "algorithm": "phash",
  "hash_size": 8,
  "generated_at": "2026-07-22T00:00:00Z",
  "count": 15234,
  "hashes": { "<passcode>": "<16-hex-char phash>", ... }
}
```

## YGOPRODeck API policy — read before changing this tool

Per <https://ygoprodeck.com/api-guide/>:

- **Rate limit is 20 requests/second**; exceed it and you are blocked for 1
  hour. The card list is a single request; image downloads are deliberately
  throttled (low `--workers` + `--delay`). **Do not crank `--workers` high.**
- **Do not hotlink images.** "Download and re-host the images yourself.
  Failure to do so will result in an IP blacklist." Pulling "a very high
  volume of images per second" also gets you blacklisted. This tool downloads
  each image once into the local cache and never re-fetches.
- The shipped `card_hashes.json` contains **derived hashes, not redistributed
  artwork**.
- Store pulled data locally to keep API calls to a minimum (the cache does
  this; `--incremental` avoids re-hashing).
