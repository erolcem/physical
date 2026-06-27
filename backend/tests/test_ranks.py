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


def test_aesthetics_excluded_from_overall(client):
    # Two users: one with only strength, one with the same strength PLUS a great skin
    # score. The aesthetic must not change the overall (it's excluded).
    base = [{"metric_id": "bench", "ts": "2026-06-01T08:00:00", "value": 100, "bodyweight_at_ts": 80}]
    client.post("/me/samples", json=base)
    overall_a = client.get("/me/ranks").json()["overall"]["rank_value"]
    client.post("/me/samples", json=[
        {"metric_id": "skin", "ts": "2026-06-02T08:00:00", "value": 99}])
    overall_b = client.get("/me/ranks").json()["overall"]["rank_value"]
    assert overall_a == overall_b  # skin did not move the headline


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
