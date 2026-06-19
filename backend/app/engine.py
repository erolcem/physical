"""Loads the canonical rank engine directly from the repo's single source of
truth (`lib/engine/physical_rank_engine.py`) — no copy, no drift. The Flutter
app ports the same file to Dart; this backend imports it as-is.
"""
import importlib.util
import sys
from pathlib import Path

_ENGINE_PATH = (
    Path(__file__).resolve().parents[2] / "lib" / "engine" / "physical_rank_engine.py"
)
if not _ENGINE_PATH.exists():  # pragma: no cover
    raise RuntimeError(f"Rank engine not found at {_ENGINE_PATH}")

_spec = importlib.util.spec_from_file_location("physical_rank_engine", _ENGINE_PATH)
rank_engine = importlib.util.module_from_spec(_spec)
# Register before exec: the engine uses `from __future__ import annotations` +
# dataclasses, which resolve annotations via sys.modules[cls.__module__].
sys.modules["physical_rank_engine"] = rank_engine
_spec.loader.exec_module(rank_engine)

# Re-export the bits the backend uses.
STANDARDS = rank_engine.STANDARDS
TIERS = rank_engine.TIERS
Log = rank_engine.Log
tier_of = rank_engine.tier_of
percentile = rank_engine.percentile
overall = rank_engine.overall
threshold = rank_engine.threshold
est_1rm = rank_engine.est_1rm
