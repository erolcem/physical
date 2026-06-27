from app import engine as E


def _seed(client):
    client.post("/me/samples", json=[
        {"metric_id": "bench", "ts": "2026-06-01T08:00:00", "value": 100, "bodyweight_at_ts": 80},
        {"metric_id": "squat", "ts": "2026-06-01T08:00:00", "value": 140, "bodyweight_at_ts": 80},
        {"metric_id": "vo2max", "ts": "2026-06-01T08:00:00", "value": 52},
        {"metric_id": "resting_hr", "ts": "2026-06-01T08:00:00", "value": 55},
        {"metric_id": "sleep_score", "ts": "2026-06-01T08:00:00", "value": 88},
        {"metric_id": "skin", "ts": "2026-06-01T08:00:00", "value": 90},  # ranked aesthetic
    ])


def test_ranks_overall_categories_metrics(client):
    _seed(client)
    r = client.get("/me/ranks").json()

    assert r["overall"]["tier"] in E.TIERS
    for cat in ("strength", "performance", "recovery"):
        assert cat in r["categories"], f"missing category {cat}"
        assert r["categories"][cat]["tier"] in E.TIERS
    # Aesthetics now rank individually + as a category…
    assert r["metrics"]["skin"]["tier"] in E.TIERS
    assert "aesthetics" in r["categories"]
    assert r["metrics"]["bench"]["tier"] in E.TIERS
    assert 0 <= r["metrics"]["sleep_score"]["percentile"] <= 100


def test_overall_is_category_equal_not_strength_heavy(client):
    # Many weak strength lifts + one elite aesthetic. Because overall averages the four
    # CATEGORIES equally (not per-metric), the single aesthetic pulls the overall up
    # between the two category ranks — strength's metric count doesn't dominate.
    client.post("/me/samples", json=[
        {"metric_id": "bench", "ts": "2026-06-01T08:00:00", "value": 40, "bodyweight_at_ts": 80},
        {"metric_id": "squat", "ts": "2026-06-01T08:00:00", "value": 50, "bodyweight_at_ts": 80},
        {"metric_id": "ohp", "ts": "2026-06-01T08:00:00", "value": 25, "bodyweight_at_ts": 80},
        {"metric_id": "pullup", "ts": "2026-06-01T08:00:00", "value": 5, "bodyweight_at_ts": 80},
        {"metric_id": "eye", "ts": "2026-06-01T08:00:00", "value": -0.25},  # elite vision
    ])
    r = client.get("/me/ranks").json()
    ov = r["overall"]["rank_value"]
    assert "aesthetics" in r["categories"]
    lo = r["categories"]["strength"]["rank_value"]
    hi = r["categories"]["aesthetics"]["rank_value"]
    assert lo < ov < hi  # overall sits between the two categories, not pinned to strength


def test_latest_value_is_used(client):
    client.post("/me/samples", json=[
        {"metric_id": "bench", "ts": "2026-05-01T08:00:00", "value": 60, "bodyweight_at_ts": 80},
        {"metric_id": "bench", "ts": "2026-06-01T08:00:00", "value": 120, "bodyweight_at_ts": 80},
    ])
    r = client.get("/me/ranks").json()
    assert r["metrics"]["bench"]["value"] == 120


def test_empty_user_is_wood(client):
    # A different signed-in user with no data of their own → empty ranks.
    nobody = client.post("/auth/dev", json={"user_id": "nobody"}).json()["access_token"]
    r = client.get("/me/ranks", headers={"Authorization": f"Bearer {nobody}"}).json()
    assert r["overall"]["tier"] == "Wood"
    assert r["metrics"] == {}
