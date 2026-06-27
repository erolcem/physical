"""Photo aesthetic CV: pure scorers + analyzers on synthetic images + the endpoint."""
import io

import numpy as np
from PIL import Image

from app.aesthetics import photo


def _save(arr, tmp_path, name):
    p = tmp_path / name
    Image.fromarray(arr.astype("uint8")).save(str(p))
    return str(p)


def _jpeg(arr):
    buf = io.BytesIO()
    Image.fromarray(arr.astype("uint8")).save(buf, format="JPEG")
    return buf.getvalue()


def test_score_skin_anchors():
    assert photo.score_skin(0.01, 0.08, 0.005)["score"] > 90  # clear/even/smooth
    assert photo.score_skin(0.15, 0.35, 0.15)["score"] < 10  # patchy/uneven/spotty


def test_skin_uniform_tone_scores_high(tmp_path):
    arr = np.full((200, 200, 3), 0.0)
    arr[:] = [215, 170, 150]  # even, in the YCbCr skin range
    out = photo.analyze_skin(_save(arr, tmp_path, "skin.jpg"))
    assert out["score"] > 80
    assert out["region_fraction"] > 0.9  # almost all detected as skin


def test_skin_requires_skin_pixels(tmp_path):
    arr = np.full((200, 200, 3), 0.0)
    arr[:] = [20, 90, 30]  # green — not skin
    try:
        photo.analyze_skin(_save(arr, tmp_path, "green.jpg"))
        assert False, "non-skin image should raise"
    except ValueError:
        pass


def test_score_hair_coverage_endpoints():
    assert photo.score_hair(0.0)["score"] == 0.0
    assert photo.score_hair(1.0)["score"] == 100.0


def test_hair_coverage_estimate(tmp_path):
    arr = np.full((200, 200, 3), 200.0)  # light scalp
    arr[:100] = 20  # top half dark "hair"
    out = photo.analyze_hair(_save(arr, tmp_path, "hair.jpg"))
    assert 0.3 < out["coverage"] < 0.7  # ~half covered


def test_score_oral_weighting():
    assert photo.score_oral(1.0, 1.0)["score"] == 100.0
    assert photo.score_oral(0.0, 0.0)["score"] == 0.0
    # whiteness weighted 0.6
    assert photo.score_oral(1.0, 0.0)["score"] == 60.0


def test_photo_endpoint_skin(client):
    arr = np.full((200, 200, 3), 0.0)
    arr[:] = [215, 170, 150]
    r = client.post("/me/aesthetics/photo/skin",
                    files={"file": ("s.jpg", _jpeg(arr), "image/jpeg")})
    assert r.status_code == 200, r.text
    assert 0 <= r.json()["score"] <= 100


def test_photo_endpoint_unknown_metric(client):
    r = client.post("/me/aesthetics/photo/nose",
                    files={"file": ("s.jpg", _jpeg(np.full((50, 50, 3), 200.0)), "image/jpeg")})
    assert r.status_code == 404
