"""Build the perceptual-hash art index for OCR-miss fallback matching.

Build order step 6 (see CLAUDE.md). This tool:

  1. Fetches the full card database in ONE request from YGOPRODeck's
     `cardinfo.php` (same endpoint as `lib/data/api/ygoprodeck_client.dart`).
  2. Downloads each artwork's *cropped* image (art box only, matching what the
     scan pipeline crops at runtime), caching to disk so re-runs cost nothing.
  3. Computes a perceptual hash (pHash) per artwork.
  4. Emits `assets/card_hashes.json` mapping passcode -> pHash, consumed by
     step 8's art-matching fallback (see .claude/skills/scan-pipeline.md).

Every entry in a card's `card_images` array is indexed by its OWN `id` (its
own passcode), so alternate artworks are matchable and resolve to the correct
printing.

## YGOPRODeck API policy (https://ygoprodeck.com/api-guide/)

This tool is built to respect their rules; do not defeat them:

  - Rate limit is "20 requests per 1 second" or you are blocked for 1 hour.
    The card list is a single request. Image downloads are throttled far
    below this by default.
  - "Do not continually hotlink images... download and re-host the images
    yourself. Failure to do so will result in an IP blacklist." / "if we find
    you are pulling a very high volume of images per second then your IP will
    be blacklisted." We download each image ONCE into a local cache and never
    re-fetch. The shipped `card_hashes.json` contains derived hashes, NOT
    redistributed artwork.
  - Keep `--workers` low. The default is deliberately conservative.

Run:

    pip install -r tools/requirements.txt
    python tools/build_hash_index.py            # full index (~13k cards)
    python tools/build_hash_index.py --limit 20 # fast smoke run
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

# --- Constants -------------------------------------------------------------

CARDINFO_URL = "https://db.ygoprodeck.com/api/v7/cardinfo.php"
# A descriptive User-Agent so YGOPRODeck can identify this traffic.
USER_AGENT = "ygo_scanner-build_hash_index/1.0 (+https://github.com; card art pHash indexer)"
OUTPUT_VERSION = 1
ALGORITHM = "phash"

_REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUTPUT = _REPO_ROOT / "assets" / "card_hashes.json"
DEFAULT_CACHE_DIR = _REPO_ROOT / "tools" / ".image_cache"

DEFAULT_HASH_SIZE = 8
DEFAULT_WORKERS = 4
# Per-request pause (seconds) applied inside each worker after a real network
# fetch, to stay well under the "very high volume of images per second" line.
DEFAULT_DELAY = 0.05


# --- Pure functions (unit-tested offline) ---------------------------------


def build_image_jobs(cardinfo_data: Iterable[dict]) -> list[tuple[str, str]]:
    """Flatten `cardinfo.php` `data[]` into `(image_id, cropped_url)` jobs.

    Every entry in each card's `card_images` array is included (so alternate
    artworks are indexed) and keyed by that entry's own `id`. Duplicate ids
    (an artwork appearing under multiple cards) are emitted once, first-wins.
    Entries missing an id or a cropped URL are skipped.
    """
    jobs: list[tuple[str, str]] = []
    seen: set[str] = set()
    for card in cardinfo_data:
        for image in card.get("card_images", []) or []:
            image_id = image.get("id")
            cropped_url = image.get("image_url_cropped")
            if image_id is None or not cropped_url:
                continue
            passcode = str(image_id)
            if passcode in seen:
                continue
            seen.add(passcode)
            jobs.append((passcode, cropped_url))
    return jobs


def build_output(hashes: dict[str, str], hash_size: int) -> dict:
    """Wrap the passcode -> hex-hash map with metadata step 8 can validate."""
    return {
        "version": OUTPUT_VERSION,
        "algorithm": ALGORITHM,
        "hash_size": hash_size,
        "generated_at": datetime.now(timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z"),
        "count": len(hashes),
        "hashes": dict(sorted(hashes.items())),
    }


# --- I/O (network, disk) ---------------------------------------------------


def fetch_cardinfo(url: str = CARDINFO_URL) -> list[dict]:
    """Single bulk GET of the full card database. Returns `data[]`."""
    import requests  # imported lazily so pure functions test without the dep

    resp = requests.get(url, headers={"User-Agent": USER_AGENT}, timeout=120)
    resp.raise_for_status()
    return resp.json().get("data", []) or []


def _download_one(passcode: str, url: str, cache_dir: Path, delay: float) -> Path | None:
    """Download one cropped image to `<cache_dir>/<passcode>.jpg` (skip if
    cached). Returns the path, or None on failure (logged, non-fatal)."""
    import requests

    dest = cache_dir / f"{passcode}.jpg"
    if dest.exists() and dest.stat().st_size > 0:
        return dest  # cache hit: zero CDN cost
    try:
        resp = requests.get(url, headers={"User-Agent": USER_AGENT}, timeout=60)
        resp.raise_for_status()
        dest.write_bytes(resp.content)
    except Exception as exc:  # noqa: BLE001 - one bad image must not abort the run
        print(f"  ! download failed {passcode}: {exc}", file=sys.stderr)
        return None
    time.sleep(delay)  # throttle only after a real fetch, not on cache hits
    return dest


def download_all(
    jobs: list[tuple[str, str]],
    cache_dir: Path,
    workers: int,
    delay: float,
) -> dict[str, Path]:
    """Download every job's image into the cache. Returns passcode -> path for
    successes only. Cache hits make no network request."""
    cache_dir.mkdir(parents=True, exist_ok=True)
    results: dict[str, Path] = {}
    done = 0
    total = len(jobs)
    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures = {
            pool.submit(_download_one, pc, url, cache_dir, delay): pc
            for pc, url in jobs
        }
        for future in as_completed(futures):
            passcode = futures[future]
            path = future.result()
            if path is not None:
                results[passcode] = path
            done += 1
            if done % 500 == 0 or done == total:
                print(f"  downloaded/cached {done}/{total}")
    return results


def hash_images(images: dict[str, Path], hash_size: int) -> dict[str, str]:
    """Compute a pHash (hex string) per cached image. Undecodable images are
    logged and skipped."""
    import imagehash  # lazy import
    from PIL import Image

    hashes: dict[str, str] = {}
    done = 0
    total = len(images)
    for passcode, path in images.items():
        try:
            with Image.open(path) as img:
                hashes[passcode] = str(imagehash.phash(img, hash_size=hash_size))
        except Exception as exc:  # noqa: BLE001 - skip a bad image, keep going
            print(f"  ! hash failed {passcode}: {exc}", file=sys.stderr)
        done += 1
        if done % 1000 == 0 or done == total:
            print(f"  hashed {done}/{total}")
    return hashes


def load_existing_hashes(output_path: Path) -> dict[str, str]:
    """Load prior `hashes` map from an existing output file (for --incremental)."""
    if not output_path.exists():
        return {}
    try:
        data = json.loads(output_path.read_text(encoding="utf-8"))
        return dict(data.get("hashes", {}))
    except (json.JSONDecodeError, OSError) as exc:
        print(f"  ! could not read existing {output_path}: {exc}", file=sys.stderr)
        return {}


# --- Orchestration ---------------------------------------------------------


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--cache-dir", type=Path, default=DEFAULT_CACHE_DIR)
    parser.add_argument(
        "--workers",
        type=int,
        default=DEFAULT_WORKERS,
        help="Concurrent image downloads. Keep low to respect the API policy.",
    )
    parser.add_argument(
        "--delay",
        type=float,
        default=DEFAULT_DELAY,
        help="Seconds to pause after each real (non-cached) download.",
    )
    parser.add_argument("--hash-size", type=int, default=DEFAULT_HASH_SIZE)
    parser.add_argument(
        "--limit",
        type=int,
        default=None,
        help="Only process the first N cards (fast smoke run).",
    )
    parser.add_argument(
        "--incremental",
        action="store_true",
        help="Reuse hashes already in --output; only compute the missing ones.",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)

    print(f"Fetching card database from {CARDINFO_URL} ...")
    cards = fetch_cardinfo()
    if args.limit is not None:
        cards = cards[: args.limit]
    print(f"  fetched {len(cards)} card entries")

    jobs = build_image_jobs(cards)
    print(f"  {len(jobs)} unique artworks to index (incl. alt-arts)")

    existing = load_existing_hashes(args.output) if args.incremental else {}
    if existing:
        jobs = [(pc, url) for pc, url in jobs if pc not in existing]
        print(f"  incremental: {len(existing)} already hashed, {len(jobs)} remaining")

    if jobs:
        print(f"Downloading images (workers={args.workers}, delay={args.delay}s) ...")
        images = download_all(jobs, args.cache_dir, args.workers, args.delay)
        print(f"  {len(images)}/{len(jobs)} images available locally")

        print(f"Hashing (phash, hash_size={args.hash_size}) ...")
        new_hashes = hash_images(images, args.hash_size)
    else:
        new_hashes = {}

    all_hashes = {**existing, **new_hashes}
    output = build_output(all_hashes, args.hash_size)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(output, indent=2, sort_keys=False) + "\n", encoding="utf-8"
    )
    print(
        f"Wrote {output['count']} hashes to {args.output} "
        f"(new: {len(new_hashes)}, reused: {len(existing)})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
