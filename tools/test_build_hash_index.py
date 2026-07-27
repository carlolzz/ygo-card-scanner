"""Offline unit tests for build_hash_index's pure functions.

No network, no image files. Run: pytest tools/test_build_hash_index.py
"""

from build_hash_index import (
    ART_BOX_ROI,
    build_image_jobs,
    build_output,
    roi_pixel_box,
)


def test_build_image_jobs_indexes_alt_arts_by_own_id():
    data = [
        {
            "id": 46986414,
            "name": "Dark Magician",
            "card_images": [
                {"id": 46986414, "image_url": "https://x/46986414.jpg"},
                {"id": 36996508, "image_url": "https://x/36996508.jpg"},
            ],
        }
    ]
    jobs = build_image_jobs(data)
    assert jobs == [
        ("46986414", "https://x/46986414.jpg"),
        ("36996508", "https://x/36996508.jpg"),
    ]


def test_build_image_jobs_dedupes_and_skips_incomplete():
    data = [
        {"id": 1, "card_images": [{"id": 1, "image_url": "u1"}]},
        {"id": 2, "card_images": [{"id": 1, "image_url": "u1-dup"}]},  # dup id
        {"id": 3, "card_images": [{"id": 3}]},  # no full url -> skip
        {"id": 4, "card_images": [{"image_url": "u4"}]},  # no id -> skip
        {"id": 5},  # no card_images at all
    ]
    jobs = build_image_jobs(data)
    assert jobs == [("1", "u1")]


def test_roi_pixel_box_rounds_fractions_to_pixels():
    # Fractions round to the nearest pixel, and none of these land on a .5 tie
    # (which would round bankers'-style in Python and away-from-zero in Dart's
    # `.round()`, silently disagreeing by a pixel between index and runtime).
    assert roi_pixel_box(100, 200, ART_BOX_ROI) == (12, 36, 88, 141)
    assert roi_pixel_box(64, 64, ART_BOX_ROI) == (8, 12, 57, 45)


def test_roi_is_the_measured_square_art_window():
    """On YGOPRODeck's canonical 813x1185 render the ROI must land on the
    artwork window measured from their own `image_url_cropped`: 622x622 at
    (96, 215), i.e. square and horizontally centred (96px left, 95px right).

    This is the whole point of the v3 ROI — the previous value was a 1.147-aspect
    rectangle, which the runtime's art-box correction could never accept.
    """
    left, top, right, bottom = roi_pixel_box(813, 1185, ART_BOX_ROI)
    assert (left, top, right, bottom) == (96, 215, 718, 837)
    assert right - left == 622
    assert bottom - top == 622  # square
    assert left == 96 and 813 - right == 95  # centred


def test_build_output_shape_and_metadata():
    out = build_output({"b": "ff", "a": "00"}, hash_size=16)
    assert out["version"] == 3
    assert out["algorithm"] == "phash"
    assert out["hash_size"] == 16
    assert out["roi"] == list(ART_BOX_ROI)
    assert out["count"] == 2
    # keys sorted for stable diffs
    assert list(out["hashes"].keys()) == ["a", "b"]
    assert out["generated_at"].endswith("Z")
