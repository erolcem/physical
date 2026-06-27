"""Voice quality (Aesthetics) — acoustic analysis via Praat/Parselmouth, no 3rd party.

Raw vocal-perturbation metrics are mapped to 0–100 against CLINICAL voice norms
(normal adult: jitter <1.04 %, shimmer <3.81 %, HNR >20 dB). Higher = clearer,
healthier voice. The score is what the user logs as the `voice` metric.

`score_voice` is pure (unit-tested). `analyze` reads a WAV and runs Praat.
"""
from __future__ import annotations

import math


def _ramp(x: float, good: float, bad: float) -> float:
    """1.0 at the `good` clinical anchor, 0.0 at the `bad` one, linear between.
    Works in either direction (good may be < or > bad)."""
    if good == bad:
        return 0.0
    return max(0.0, min(1.0, (x - bad) / (good - bad)))


def score_voice(jitter_pct: float, shimmer_pct: float, hnr_db: float) -> dict:
    """Map raw acoustics → per-component 0–100 + a weighted composite.

    Clinical anchors (good→100, bad→0):
      jitter   ≤0.5 % … ≥2.0 %      (normal <1.04 %)
      shimmer  ≤2.0 % … ≥6.0 %      (normal <3.81 %)
      HNR      ≥25 dB … ≤7 dB       (good   >20 dB)
    HNR is weighted highest — it's the single best overall voice-quality signal.
    """
    j = _ramp(jitter_pct, 0.5, 2.0)
    s = _ramp(shimmer_pct, 2.0, 6.0)
    h = _ramp(hnr_db, 25.0, 7.0)
    composite = 0.30 * j + 0.30 * s + 0.40 * h
    return {
        "jitter_pct": round(jitter_pct, 3),
        "shimmer_pct": round(shimmer_pct, 3),
        "hnr_db": round(hnr_db, 2),
        "components": {"jitter": round(j * 100, 1), "shimmer": round(s * 100, 1),
                       "hnr": round(h * 100, 1)},
        "score": round(composite * 100, 1),
    }


def _avqi(snd) -> tuple:
    """Acoustic Voice Quality Index v03.01 (Maryn et al.) + CPPS, from the sustained
    vowel. The validated AVQI concatenates vowel + read speech; vowel-only here is an
    approximation (flagged provisional). Lower = healthier; population norm 2.3 ± 0.8."""
    from parselmouth.praat import call
    pc = call(snd, "To PowerCepstrogram", 60, 0.002, 5000, 50)
    cpps = call(pc, "Get CPPS", False, 0.01, 0.001, 60, 330, 0.05,
                "Parabolic", 0.001, 0.05, "Straight", "Robust")
    harm = call(snd, "To Harmonicity (cc)", 0.01, 75, 0.1, 1.0)
    hnr = call(harm, "Get mean", 0, 0)
    pp = call(snd, "To PointProcess (periodic, cc)", 75, 500)
    shim = call([snd, pp], "Get shimmer (local)", 0, 0, 0.0001, 0.02, 1.3, 1.6) * 100
    shim_db = call([snd, pp], "Get shimmer (local_dB)", 0, 0, 0.0001, 0.02, 1.3, 1.6)
    ltas = call(snd, "To Ltas", 1)
    slope = call(ltas, "Get slope", 0, 1000, 1000, 10000, "energy")
    trend = call(ltas, "Compute trend line", 1, 10000)
    tilt = call(trend, "Get slope", 0, 1000, 1000, 10000, "energy")
    avqi = (4.152 - 0.177 * cpps - 0.006 * hnr - 0.037 * shim + 0.941 * shim_db
            + 0.01 * slope + 0.093 * tilt) * 2.8902
    return max(0.0, round(avqi, 2)), round(cpps, 2)


def analyze(path: str, f0min: float = 75.0, f0max: float = 500.0) -> dict:
    """Praat analysis of a WAV file → score_voice(...) plus mean pitch (Hz).

    Raises ValueError if the clip has no usable voiced signal (e.g. silence, or the
    user didn't sustain a vowel) so the app can ask for a clean re-record.
    """
    import parselmouth
    from parselmouth.praat import call

    snd = parselmouth.Sound(path)
    point_process = call(snd, "To PointProcess (periodic, cc)", f0min, f0max)
    n_points = call(point_process, "Get number of points")
    if not n_points or n_points < 3:
        raise ValueError("No steady voice detected — sustain an 'aaah' for ~3 seconds.")

    jitter = call(point_process, "Get jitter (local)", 0, 0, 0.0001, 0.02, 1.3) * 100
    shimmer = call([snd, point_process], "Get shimmer (local)",
                   0, 0, 0.0001, 0.02, 1.3, 1.6) * 100
    harmonicity = call(snd, "To Harmonicity (cc)", 0.01, f0min, 0.1, 1.0)
    hnr = call(harmonicity, "Get mean", 0, 0)
    pitch = call(snd, "To Pitch", 0.0, f0min, f0max)
    f0 = call(pitch, "Get mean", 0, 0, "Hertz")

    if any(v is None or math.isnan(v) for v in (jitter, shimmer, hnr)):
        raise ValueError("Couldn't analyze that clip — try a longer, steady 'aaah'.")

    out = score_voice(jitter, shimmer, hnr)
    out["pitch_hz"] = round(f0, 1) if (f0 is not None and not math.isnan(f0)) else None
    # AVQI is the ranked quantity (has a population norm); the /100 above is for display.
    try:
        avqi, cpps = _avqi(snd)
        if not math.isnan(avqi):
            out["avqi"] = avqi
            out["cpps"] = cpps
    except Exception:
        out["avqi"] = None  # degrade gracefully; app falls back to the /100 score
    return out
