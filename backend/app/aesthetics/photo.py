"""Photo-based aesthetic measurements via classical computer vision (Pillow + numpy)
— no third-party model, runs on the server.

HONEST SCOPE: these are screening-grade estimates from a single phone photo, sensitive
to lighting and framing. They quantify real signals (skin redness/evenness/blemishes;
tooth brightness/yellowness + gum redness; scalp hair coverage) into a 0–100 you can
track over time — they are NOT clinical instruments. The pure `score_*` functions are
unit-tested; `analyze_*` decode the image and compute the raw signals.
"""
from __future__ import annotations

import numpy as np

_MAX = 512  # downscale longest side to this for speed + denoise


def _load_rgb(path: str) -> np.ndarray:
    from PIL import Image
    img = Image.open(path).convert("RGB")
    img.thumbnail((_MAX, _MAX))
    return np.asarray(img, dtype=np.float64)


def _clip01(x: float) -> float:
    return float(min(max(x, 0.0), 1.0))


def _ramp(x: float, good: float, bad: float) -> float:
    """1.0 at `good`, 0.0 at `bad`, linear between (either direction)."""
    if good == bad:
        return 0.0
    return _clip01((x - bad) / (good - bad))


# ── Skin ──────────────────────────────────────────────────────────────────
def _skin_mask(rgb: np.ndarray) -> np.ndarray:
    """Boolean mask of skin-toned pixels (classic YCbCr rule) — isolates face skin
    from background/hair/eyes so the score reflects skin, not the scene."""
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    cb = 128 - 0.168736 * r - 0.331264 * g + 0.5 * b
    cr = 128 + 0.5 * r - 0.418688 * g - 0.081312 * b
    return (cb >= 77) & (cb <= 127) & (cr >= 133) & (cr <= 173)


def score_skin(redness: float, unevenness: float, spot_density: float) -> dict:
    """Skin signals → per-component 0–100 + composite. Anchors are heuristic (no
    clinical absolute for skin) and tone-robust (variation-based): redness PATCHINESS
    good≤0.03/bad≥0.10, unevenness (lum CV) good≤0.10/bad≥0.30, blemish density
    good≤0.01/bad≥0.10."""
    clarity = _ramp(redness, 0.03, 0.10)
    evenness = _ramp(unevenness, 0.10, 0.30)
    smooth = _ramp(spot_density, 0.01, 0.10)
    score = 100 * (0.35 * clarity + 0.35 * evenness + 0.30 * smooth)
    return {
        "redness": round(redness, 4), "unevenness": round(unevenness, 4),
        "spot_density": round(spot_density, 4),
        "components": {"clarity": round(clarity * 100, 1),
                       "evenness": round(evenness * 100, 1),
                       "smoothness": round(smooth * 100, 1)},
        "score": round(score, 1),
    }


def analyze_skin(path: str) -> dict:
    rgb = _load_rgb(path)
    mask = _skin_mask(rgb)
    if mask.sum() < 0.05 * mask.size:
        raise ValueError("Couldn't find enough skin — fill the frame with a well-lit face.")
    px = rgb[mask]
    r, g, b = px[:, 0], px[:, 1], px[:, 2]
    lum = 0.299 * r + 0.587 * g + 0.114 * b
    # Redness PATCHINESS (tone-robust): spread of the red index across skin, not its
    # absolute level (all skin is reddish). Localized irritation/acne raises the spread.
    redness = float(np.std((r - g) / (r + g + 1.0)))
    unevenness = float(np.std(lum) / (np.mean(lum) + 1.0))
    # blemishes: skin pixels notably darker/redder than the local average.
    dark = lum < (np.mean(lum) - 1.5 * np.std(lum))
    spot_density = float(np.mean(dark))
    return analyze_result(score_skin(redness, unevenness, spot_density), mask.mean())


# ── Oral ──────────────────────────────────────────────────────────────────
def score_oral(whiteness: float, gum_health: float) -> dict:
    """Tooth whiteness (0–1, brighter+less-yellow) + gum health (0–1, less red) →
    composite. Whiteness weighted higher (the dominant aesthetic signal)."""
    score = 100 * (0.6 * whiteness + 0.4 * gum_health)
    return {
        "components": {"whiteness": round(whiteness * 100, 1),
                       "gum_health": round(gum_health * 100, 1)},
        "score": round(score, 1),
    }


def analyze_oral(path: str) -> dict:
    rgb = _load_rgb(path)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    lum = 0.299 * r + 0.587 * g + 0.114 * b
    # Teeth: brightest, least-saturated pixels. Gums: reddish (high r vs g) pixels.
    mx = np.max(rgb, axis=-1); mn = np.min(rgb, axis=-1)
    sat = (mx - mn) / (mx + 1.0)
    teeth = (lum > np.percentile(lum, 80)) & (sat < 0.25)
    gums = (r > g + 25) & (r > b + 25) & ~teeth
    if teeth.sum() < 0.01 * teeth.size:
        raise ValueError("Couldn't find teeth — take a clear, well-lit smile photo.")
    tooth_lum = float(np.mean(lum[teeth])) / 255.0
    tooth_yellow = float(np.mean((r[teeth] - b[teeth]) / (r[teeth] + b[teeth] + 1.0)))
    whiteness = _clip01(0.6 * tooth_lum + 0.4 * _ramp(tooth_yellow, 0.02, 0.25))
    gum_red = float(np.mean((r[gums] - g[gums]) / (r[gums] + g[gums] + 1.0))) if gums.any() else 0.0
    gum_health = _ramp(gum_red, 0.10, 0.35)
    return analyze_result(score_oral(whiteness, gum_health), float(teeth.mean()))


# ── Hair ──────────────────────────────────────────────────────────────────
def score_hair(coverage: float) -> dict:
    """Scalp hair COVERAGE (0–1 of the patch) → 0–100. A coverage proxy, not true
    hairs/cm² (that needs a macro lens + scale reference)."""
    return {"coverage": round(coverage, 4), "score": round(100 * _clip01(coverage), 1)}


def analyze_hair(path: str) -> dict:
    rgb = _load_rgb(path)
    lum = 0.299 * rgb[..., 0] + 0.587 * rgb[..., 1] + 0.114 * rgb[..., 2]
    # Hair strands are darker than scalp; coverage = fraction below the midtone split.
    thresh = (np.percentile(lum, 90) + np.percentile(lum, 10)) / 2
    coverage = float(np.mean(lum < thresh))
    return analyze_result(score_hair(coverage), None)


def analyze_result(scored: dict, region_frac) -> dict:
    if region_frac is not None:
        scored["region_fraction"] = round(float(region_frac), 3)
    return scored


ANALYZERS = {"skin": analyze_skin, "oral": analyze_oral, "hair": analyze_hair}
