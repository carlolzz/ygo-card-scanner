"""Offline unit tests for build_localized_names' pure functions.

No network. Run: pytest tools/test_build_localized_names.py
"""

import json
from pathlib import Path

from build_localized_names import (
    OUTPUT_VERSION,
    SUPPORTED_LANGUAGES,
    build_names,
    build_output,
    output_path,
)

_REPO_ROOT = Path(__file__).resolve().parent.parent


def test_build_names_keys_on_unpadded_string_id():
    # `YgoProdeckClient._parseEntry` stores `json['id'].toString()`, so a
    # short passcode must NOT be zero-padded here or it joins to nothing.
    data = [{"id": 4031928, "name": "Il Guerriero Oscuro"}]
    assert build_names(data) == {"4031928": "Il Guerriero Oscuro"}


def test_build_names_skips_incomplete_and_dedupes_first_wins():
    data = [
        {"id": 1, "name": "Uno"},
        {"id": 1, "name": "Uno bis"},  # duplicate id -> first wins
        {"id": 2},  # no name -> skip
        {"name": "Senza id"},  # no id -> skip
        {"id": 3, "name": ""},  # empty name -> skip
    ]
    assert build_names(data) == {"1": "Uno"}


def test_build_names_ignores_card_images():
    # An alt art is the same card with the same name; indexing it separately
    # would make the search return the card twice.
    data = [
        {
            "id": 46986414,
            "name": "Mago Nero",
            "card_images": [{"id": 46986414}, {"id": 36996508}],
        }
    ]
    assert build_names(data) == {"46986414": "Mago Nero"}


def test_build_output_sorts_names_and_carries_metadata():
    out = build_output({"20": "Venti", "3": "Tre"}, "IT")
    assert out["version"] == OUTPUT_VERSION
    assert out["language"] == "IT"
    assert out["count"] == 2
    assert list(out["names"]) == ["20", "3"]  # sorted as strings, stable diffs
    assert out["generated_at"].endswith("Z")


def test_output_path_matches_the_asset_the_app_loads():
    assert output_path("it", Path("assets")) == Path("assets/card_names_it.json")


def test_shipped_italian_asset_is_present_and_well_formed():
    """The committed asset must stay loadable by `HashIndex`'s sibling loader.

    This is the only test that opens the real file; without it, regenerating
    the asset with a broken tool would leave `pytest` green and break only the
    app. Mirrors `test/features/scan/hash_index_asset_test.dart`.
    """
    path = _REPO_ROOT / "assets" / "card_names_it.json"
    assert path.exists(), "run: python tools/build_localized_names.py"
    data = json.loads(path.read_text(encoding="utf-8"))
    assert data["version"] == OUTPUT_VERSION
    assert data["language"] == SUPPORTED_LANGUAGES["it"]
    assert data["count"] == len(data["names"])
    assert data["count"] > 10000
    # Blue-Eyes White Dragon, the fixture card every other suite uses.
    assert data["names"]["89631139"] == "Drago Bianco Occhi Blu"
