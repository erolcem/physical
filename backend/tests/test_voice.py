"""Voice-quality aesthetic measurement: pure clinical scoring + the Praat pipeline
end-to-end on a synthesized voice-like tone + the upload endpoint."""
import io
import wave

import numpy as np

from app.aesthetics import voice


def test_score_voice_clinical_anchors():
    # Ideal acoustics (below every "good" anchor) → 100.
    assert voice.score_voice(0.3, 1.5, 28)["score"] == 100.0
    # Disordered (past every "bad" anchor) → 0.
    assert voice.score_voice(2.5, 7.0, 5.0)["score"] == 0.0
    # Midway on all three → 50 (each component at its half-point).
    mid = voice.score_voice(1.25, 4.0, 16.0)
    assert mid["score"] == 50.0
    assert mid["components"] == {"jitter": 50.0, "shimmer": 50.0, "hnr": 50.0}


def _voice_like_wav(f0=150.0, secs=3.0, sr=44100) -> bytes:
    """A steady harmonic tone (fundamental + harmonics, minimal noise) — quasi-periodic
    like a sustained vowel, so Praat finds clean pitch periods."""
    t = np.arange(int(secs * sr)) / sr
    sig = sum((1.0 / k) * np.sin(2 * np.pi * f0 * k * t) for k in range(1, 6))
    sig = sig / np.max(np.abs(sig))
    sig = sig + 0.002 * np.random.RandomState(0).standard_normal(len(t))
    pcm = np.int16(np.clip(sig, -1, 1) * 32767)
    buf = io.BytesIO()
    with wave.open(buf, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(pcm.tobytes())
    return buf.getvalue()


def test_analyze_clean_tone(tmp_path):
    p = tmp_path / "v.wav"
    p.write_bytes(_voice_like_wav(f0=150.0))
    out = voice.analyze(str(p))
    assert 0 <= out["score"] <= 100
    assert out["score"] > 70  # a clean steady tone scores high
    assert out["jitter_pct"] < 1.0 and out["shimmer_pct"] < 5.0
    assert abs(out["pitch_hz"] - 150.0) < 12  # detected fundamental ≈ 150 Hz


def test_analyze_rejects_silence(tmp_path):
    p = tmp_path / "s.wav"
    sr = 44100
    pcm = np.zeros(sr, dtype=np.int16)
    buf = io.BytesIO()
    with wave.open(buf, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(pcm.tobytes())
    p.write_bytes(buf.getvalue())
    try:
        voice.analyze(str(p))
        assert False, "silence should raise"
    except ValueError:
        pass


def test_voice_endpoint(client):
    wav = _voice_like_wav(f0=160.0)
    r = client.post("/me/aesthetics/voice",
                    files={"file": ("clip.wav", wav, "audio/wav")})
    assert r.status_code == 200, r.text
    body = r.json()
    assert 0 <= body["score"] <= 100
    assert "jitter_pct" in body and "hnr_db" in body


def test_voice_endpoint_rejects_empty(client):
    r = client.post("/me/aesthetics/voice",
                    files={"file": ("empty.wav", b"", "audio/wav")})
    assert r.status_code == 422
