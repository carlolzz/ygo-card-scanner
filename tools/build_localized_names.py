"""Build the bundled localized card-name index used by manual search.

Build order step 30 (see CLAUDE.md). The app's sync fetches `cardinfo.php` with
no `language` parameter, so `cards.name` is always English and the manual search
can only ever match English. This tool fetches the *localized* dump once on the
host and emits a small `assets/card_names_<lang>.json` that ships with the app
and is loaded into the `card_names` table on first use.

Why a bundled asset rather than a second request during sync: the Italian dump
is ~18 MB over the wire (on top of the English sync's ~21 MB) but only ~450 KB
once reduced to id -> name. Downloading 18 MB on every sync to keep 450 KB of
data that changes about as often as the card database itself is a poor trade,
and it would break the app's offline-first promise the moment it failed. This is
the same shape as `assets/card_hashes.json`: derived data, built on the host,
committed, regenerated when it goes stale.

The passcode key is `str(entry["id"])` with **no zero padding**, because that is
exactly what `YgoProdeckClient._parseEntry` stores in `cards.passcode`
(`json['id'].toString()`). A padded key would join to nothing.

## YGOPRODeck API policy (https://ygoprodeck.com/api-guide/)

  - Rate limit is "20 requests per 1 second". This tool makes exactly ONE
    request per run.
  - No images are fetched, hotlinked or redistributed — names only, and only
    those the API itself publishes for the requested language.
  - Supported languages are fr, de, it, pt (English is the default dump and
    needs no file: it is already in `cards.name`).

Run:

    pip install -r tools/requirements.txt
    python tools/build_localized_names.py            # Italian (default)
    python tools/build_localized_names.py --language fr
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

# --- Constants -------------------------------------------------------------

CARDINFO_URL = "https://db.ygoprodeck.com/api/v7/cardinfo.php"
# A descriptive User-Agent so YGOPRODeck can identify this traffic.
USER_AGENT = (
    "ygo_scanner-build_localized_names/1.0 "
    "(+https://github.com; localized card-name index)"
)
OUTPUT_VERSION = 1

# The API's language codes, mapped to the two-letter codes this app stores in
# `collection_entries.language` / `card_names.language` (see `kCardLanguages`
# in `lib/models/card_language.dart`). English is deliberately absent: it is
# already `cards.name`, so shipping it again would be a second copy to keep in
# sync with the sync itself.
SUPPORTED_LANGUAGES = {"it": "IT", "fr": "FR", "de": "DE", "pt": "PT"}
DEFAULT_LANGUAGE = "it"

_REPO_ROOT = Path(__file__).resolve().parent.parent
ASSETS_DIR = _REPO_ROOT / "assets"


# --- Pure functions (unit-tested offline) ---------------------------------


def output_path(api_language: str, assets_dir: Path = ASSETS_DIR) -> Path:
    """Where the asset for `api_language` lives. Must match the path
    `CardRepository.ensureLocalizedNames` loads from `rootBundle`."""
    return assets_dir / f"card_names_{api_language}.json"


def build_names(cardinfo_data: Iterable[dict]) -> dict[str, str]:
    """Flatten `cardinfo.php` `data[]` into a passcode -> localized-name map.

    One entry per card, keyed exactly as `cards.passcode` is written by
    `YgoProdeckClient._parseEntry`: `str(id)`, unpadded. Entries with no id or
    no name are skipped; duplicate ids are first-wins.

    `card_images` is *not* read here, unlike `build_hash_index.py`: an alternate
    artwork is the same card with the same name, so indexing it separately would
    only add duplicate rows for the search to return twice.
    """
    names: dict[str, str] = {}
    for card in cardinfo_data:
        card_id = card.get("id")
        name = card.get("name")
        if card_id is None or not name:
            continue
        passcode = str(card_id)
        names.setdefault(passcode, name)
    return names


def build_output(names: dict[str, str], language: str) -> dict:
    """Wrap the passcode -> name map with metadata the app validates.

    `language` is the app's two-letter code (`IT`), not the API's (`it`), since
    that is what lands in the `card_names.language` column.
    """
    return {
        "version": OUTPUT_VERSION,
        "language": language,
        "generated_at": datetime.now(timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z"),
        "count": len(names),
        # Sorted for stable diffs, exactly like `card_hashes.json`: a
        # regenerated asset should show only the entries that really changed.
        "names": dict(sorted(names.items())),
    }


# --- I/O (network, disk) ---------------------------------------------------


def fetch_cardinfo(api_language: str, url: str = CARDINFO_URL) -> list[dict]:
    """Single bulk GET of the localized card database. Returns `data[]`."""
    import requests  # imported lazily so pure functions test without the dep

    resp = requests.get(
        url,
        params={"language": api_language},
        headers={"User-Agent": USER_AGENT},
        timeout=180,
    )
    resp.raise_for_status()
    return resp.json().get("data", []) or []


# --- Orchestration ---------------------------------------------------------


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--language",
        default=DEFAULT_LANGUAGE,
        choices=sorted(SUPPORTED_LANGUAGES),
        help="YGOPRODeck language code to fetch.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=None,
        help="Override the asset path (defaults to assets/card_names_<lang>.json).",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    api_language = args.language
    app_language = SUPPORTED_LANGUAGES[api_language]
    destination = args.output or output_path(api_language)

    print(f"Fetching {api_language} card database from {CARDINFO_URL} ...")
    cards = fetch_cardinfo(api_language)
    print(f"  fetched {len(cards)} card entries")

    names = build_names(cards)
    if not names:
        print("  ! no names parsed; refusing to write an empty asset", file=sys.stderr)
        return 1
    print(f"  {len(names)} unique passcodes named")

    payload = build_output(names, app_language)
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(
        json.dumps(payload, ensure_ascii=False, indent=0, sort_keys=False),
        encoding="utf-8",
    )
    size_kb = destination.stat().st_size / 1024
    print(f"Wrote {destination} ({size_kb:.0f} KB, {payload['count']} names)")
    return 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
