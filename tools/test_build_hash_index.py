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
    # Exact-integer case with the shipped ROI (0.09, 0.19, 0.91, 0.68).
    assert roi_pixel_box(100, 200, ART_BOX_ROI) == (9, 38, 91, 136)
    # Non-integer fractions round to the nearest pixel (no .5 ties):
    # 0.09*64=5.76->6, 0.19*64=12.16->12, 0.91*64=58.24->58, 0.68*64=43.52->44.
    assert roi_pixel_box(64, 64, ART_BOX_ROI) == (6, 12, 58, 44)


def test_build_output_shape_and_metadata():
    out = build_output({"b": "ff", "a": "00"}, hash_size=8)
    assert out["version"] == 2
    assert out["algorithm"] == "phash"
    assert out["hash_size"] == 8
    assert out["roi"] == list(ART_BOX_ROI)
    assert out["count"] == 2
    # keys sorted for stable diffs
    assert list(out["hashes"].keys()) == ["a", "b"]
    assert out["generated_at"].endswith("Z")
