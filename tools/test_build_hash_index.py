"""Offline unit tests for build_hash_index's pure functions.

No network, no image files. Run: pytest tools/test_build_hash_index.py
"""

from build_hash_index import build_image_jobs, build_output


def test_build_image_jobs_indexes_alt_arts_by_own_id():
    data = [
        {
            "id": 46986414,
            "name": "Dark Magician",
            "card_images": [
                {"id": 46986414, "image_url_cropped": "https://x/46986414_c.jpg"},
                {"id": 36996508, "image_url_cropped": "https://x/36996508_c.jpg"},
            ],
        }
    ]
    jobs = build_image_jobs(data)
    assert jobs == [
        ("46986414", "https://x/46986414_c.jpg"),
        ("36996508", "https://x/36996508_c.jpg"),
    ]


def test_build_image_jobs_dedupes_and_skips_incomplete():
    data = [
        {"id": 1, "card_images": [{"id": 1, "image_url_cropped": "u1"}]},
        {"id": 2, "card_images": [{"id": 1, "image_url_cropped": "u1-dup"}]},  # dup id
        {"id": 3, "card_images": [{"id": 3}]},  # no cropped url -> skip
        {"id": 4, "card_images": [{"image_url_cropped": "u4"}]},  # no id -> skip
        {"id": 5},  # no card_images at all
    ]
    jobs = build_image_jobs(data)
    assert jobs == [("1", "u1")]


def test_build_output_shape_and_metadata():
    out = build_output({"b": "ff", "a": "00"}, hash_size=8)
    assert out["version"] == 1
    assert out["algorithm"] == "phash"
    assert out["hash_size"] == 8
    assert out["count"] == 2
    # keys sorted for stable diffs
    assert list(out["hashes"].keys()) == ["a", "b"]
    assert out["generated_at"].endswith("Z")
