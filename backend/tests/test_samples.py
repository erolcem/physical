def test_ingest_and_list(client):
    r = client.post("/me/samples", json=[
        {"metric_id": "bench", "ts": "2026-06-01T08:00:00", "value": 100, "bodyweight_at_ts": 80},
        {"metric_id": "vo2max", "ts": "2026-06-01T08:00:00", "value": 50},
    ])
    assert r.status_code == 200
    assert r.json()["ingested"] == 2
    assert len(client.get("/me/samples").json()) == 2


def test_dedup_by_source_id(client):
    payload = [{"metric_id": "steps", "ts": "2026-06-01T00:00:00", "value": 9000,
                "source": "fitbit", "source_id": "2026-06-01"}]
    assert client.post("/me/samples", json=payload).json()["ingested"] == 1
    again = client.post("/me/samples", json=payload).json()
    assert again["ingested"] == 0 and again["skipped"] == 1
    # Still only one stored.
    assert len(client.get("/me/samples", params={"metric_id": "steps"}).json()) == 1


def test_manual_logs_without_source_id_always_insert(client):
    s = {"metric_id": "vo2max", "ts": "2026-06-01T08:00:00", "value": 48}
    client.post("/me/samples", json=[s])
    client.post("/me/samples", json=[s])  # no source_id ⇒ no dedup
    assert len(client.get("/me/samples", params={"metric_id": "vo2max"}).json()) == 2


def test_est_1rm_from_raw_weight_reps(client):
    r = client.post("/me/samples", json=[
        {"metric_id": "bench", "ts": "2026-06-01T08:00:00", "bodyweight_at_ts": 80,
         "raw": {"weight": 100, "reps": 5}},
    ])
    assert r.status_code == 200
    stored = client.get("/me/samples", params={"metric_id": "bench"}).json()[0]
    assert stored["value"] > 100  # 1RM estimate from 100×5 exceeds 100


def test_isolation_uses_est_1rm_like_every_lift(client):
    # Accessory lifts now rank on estimated 1RM (reps capped at 12) too, so ranking
    # rewards strength over rep-grinding — not raw weight×reps.
    from app import engine as E
    r = client.post("/me/samples", json=[
        {"metric_id": "curl", "ts": "2026-06-01T08:00:00", "bodyweight_at_ts": 80,
         "raw": {"weight": 15, "reps": 12}},
    ])
    assert r.status_code == 200
    stored = client.get("/me/samples", params={"metric_id": "curl"}).json()[0]
    assert stored["value"] == E.strength_value("curl", 15, 12)
    assert stored["value"] != 180.0  # not raw rep-volume any more


def test_value_required_when_no_raw(client):
    r = client.post("/me/samples", json=[
        {"metric_id": "bench", "ts": "2026-06-01T08:00:00", "bodyweight_at_ts": 80},
    ])
    assert r.status_code == 422


def test_delete_samples_scoped_and_all(client):
    client.post("/me/samples", json=[
        {"metric_id": "bench", "ts": "2026-06-01T08:00:00", "value": 100,
         "bodyweight_at_ts": 80, "source": "manual", "source_id": "d1"},
        {"metric_id": "steps", "ts": "2026-06-01T00:00:00", "value": 9000,
         "source": "google_health", "source_id": "steps:2026-06-01"},
    ])
    # Scoped delete: only the google_health sample goes.
    r = client.delete("/me/samples", params={"source": "google_health"})
    assert r.status_code == 200 and r.json()["deleted"] == 1
    left = client.get("/me/samples").json()
    assert [s["metric_id"] for s in left] == ["bench"]
    # Full delete wipes the rest.
    assert client.delete("/me/samples").json()["deleted"] == 1
    assert client.get("/me/samples").json() == []
