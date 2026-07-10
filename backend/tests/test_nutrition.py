"""Nutrition inference: the defensive parser must extract clean numbers from messy
model output and reject junk — it never raises."""
from app.nutrition import MICRO_UNITS, parse_nutrition


def test_parses_plain_json():
    out = parse_nutrition(
        '{"calories": 312, "protein": 24, "carbs": 30, "fat": 11, "fibre": 4, '
        '"sodium_mg": 480, "vitamin_c_mg": 2, "vitamin_d_ug": 1.1}')
    assert out["calories"] == 312 and out["protein"] == 24
    assert out["fibre"] == 4
    assert out["micros"]["sodium_mg"] == 480
    assert out["micros"]["vitamin_d_ug"] == 1.1


def test_extracts_json_from_fences_and_prose():
    reply = "Here is the estimate:\n```json\n{\"calories\": 95, \"protein\": 0.5, " \
            "\"carbs\": 25, \"fat\": 0.3, \"fibre\": 4.4, \"potassium_mg\": 422}\n```\nEnjoy!"
    out = parse_nutrition(reply)
    assert out["calories"] == 95 and out["micros"]["potassium_mg"] == 422


def test_accepts_nested_micros_object():
    out = parse_nutrition(
        '{"calories": 200, "protein": 10, "carbs": 5, "fat": 14, "fibre": 0, '
        '"micros": {"calcium_mg": 120, "iron_mg": 1.2}}')
    assert out["micros"] == {"calcium_mg": 120.0, "iron_mg": 1.2}


def test_health_densities_scale_by_portion_calories():
    # Densities are portion-independent; points = density × (kcal / 2000-kcal day).
    out = parse_nutrition(
        '{"calories": 500, "protein": 20, "carbs": 50, "fat": 20, "fibre": 6, '
        '"health": {"fibre": 40, "gut_health": 40, "antioxidants": 120, "whole_food": 80}}')
    h = out["health"]
    assert h["fibre"] == 10.0 and h["gut_health"] == 10.0  # 40 × 500/2000
    assert h["antioxidants"] == 25.0  # density capped at 100 first, then scaled
    assert h["whole_food"] == 20.0
    assert "micronutrients" not in h  # omitted axes simply absent


def test_health_points_never_exceed_density_even_for_huge_portions():
    # A 3000-kcal portion caps the day-fraction at 1.0 → points == density.
    out = parse_nutrition(
        '{"calories": 3000, "protein": 100, "carbs": 300, "fat": 100, "fibre": 30, '
        '"health": {"whole_food": 70}}')
    assert out["health"]["whole_food"] == 70.0


def test_coerces_strings_clamps_negatives_drops_unknown_and_nonfinite():
    out = parse_nutrition(
        '{"calories": "250", "protein": -3, "carbs": 20, "fat": 8, "fibre": 2, '
        '"sodium_mg": "300", "made_up_vitamin": 99, "zinc_mg": "NaN"}')
    assert out["calories"] == 250.0       # string coerced
    assert out["protein"] == 0.0          # negative clamped
    assert out["micros"]["sodium_mg"] == 300.0
    assert "made_up_vitamin" not in out["micros"]  # unknown key dropped
    assert "zinc_mg" not in out["micros"]          # NaN dropped


def test_rejects_junk_and_all_zero():
    assert parse_nutrition("sorry, I can't help with that") is None
    assert parse_nutrition("") is None
    assert parse_nutrition("[1, 2, 3]") is None
    assert parse_nutrition('{"calories": 0, "protein": 0, "carbs": 0, "fat": 0}') is None


def test_micro_units_are_unit_suffixed_keys():
    # Keys must encode their unit so values sum cleanly across foods.
    assert all(k.endswith(("_mg", "_ug")) for k in MICRO_UNITS)


def test_endpoint_requires_auth():
    from fastapi.testclient import TestClient
    from app.main import app
    with TestClient(app) as c:
        assert c.post("/me/nutrition", json={"description": "eggs"}).status_code == 401


def test_endpoint_503_when_unconfigured(client):
    # No GEMINI_API_KEY in tests → graceful 503; the app falls back to manual entry.
    r = client.post("/me/nutrition", json={"description": "eggs"})
    assert r.status_code == 503
    assert client.get("/me/nutrition/status").json()["configured"] is False


def test_endpoint_infers_via_model(client, monkeypatch):
    from app.integrations.gemini import client as gem
    monkeypatch.setattr(gem, "configured", lambda: True)
    monkeypatch.setattr(gem, "generate", lambda *a, **k:
        '{"calories": 155, "protein": 13, "carbs": 1, "fat": 11, "fibre": 0, "sodium_mg": 124}')
    r = client.post("/me/nutrition", json={"description": "2 boiled eggs"})
    assert r.status_code == 200
    body = r.json()
    assert body["calories"] == 155 and body["protein"] == 13
    assert body["micros"]["sodium_mg"] == 124


def test_endpoint_photo_supplements_text(client, monkeypatch):
    # Text + photo: the image rides the turn and the prompt gains the photo
    # guidance ("text is authoritative, photo refines portion").
    from app.integrations.gemini import client as gem
    captured = {}

    def fake_generate(system, turns, **k):
        captured["system"] = system
        captured["turns"] = turns
        return '{"calories": 640, "protein": 32, "carbs": 70, "fat": 24, "fibre": 5}'

    monkeypatch.setattr(gem, "configured", lambda: True)
    monkeypatch.setattr(gem, "generate", fake_generate)
    r = client.post("/me/nutrition", json={
        "description": "chicken burrito bowl",
        "image_b64": "aGVsbG8=",  # any base64 — passthrough, not decoded here
        "image_mime": "image/png",
    })
    assert r.status_code == 200
    assert r.json()["calories"] == 640
    turn = captured["turns"][0]
    assert turn["text"] == "chicken burrito bowl"
    assert turn["image_b64"] == "aGVsbG8=" and turn["image_mime"] == "image/png"
    assert "PORTION" in captured["system"]  # photo guidance appended
    # Without a photo the guidance is absent and no image keys ride the turn.
    r2 = client.post("/me/nutrition", json={"description": "chicken burrito bowl"})
    assert r2.status_code == 200
    assert "image_b64" not in captured["turns"][0]
    assert "PORTION" not in captured["system"]


def test_endpoint_never_accepts_photo_alone(client, monkeypatch):
    # Photo without a description is rejected — visual-only food ID is too
    # error-prone; the text is always the source of truth.
    from app.integrations.gemini import client as gem
    monkeypatch.setattr(gem, "configured", lambda: True)
    r = client.post("/me/nutrition", json={"description": "  ", "image_b64": "aGVsbG8="})
    assert r.status_code == 422


def test_endpoint_rejects_oversized_photo_and_strips_data_url(client, monkeypatch):
    from app.integrations.gemini import client as gem
    captured = {}
    monkeypatch.setattr(gem, "configured", lambda: True)
    monkeypatch.setattr(gem, "generate", lambda s, t, **k: (
        captured.update(turns=t),
        '{"calories": 100, "protein": 5, "carbs": 10, "fat": 4, "fibre": 1}')[-1])
    r = client.post("/me/nutrition", json={
        "description": "an apple", "image_b64": "x" * 6_000_001})
    assert r.status_code == 413
    r2 = client.post("/me/nutrition", json={
        "description": "an apple", "image_b64": "data:image/jpeg;base64,QUJD"})
    assert r2.status_code == 200
    assert captured["turns"][0]["image_b64"] == "QUJD"  # data-URL prefix stripped
