"""The backend must import the canonical engine and cover every ranked metric
the client registry expects — guards the Python↔Dart drift that this slice fixed.
"""
import pytest

from app import engine as E
from app.registry import RANKED_CATEGORY


def test_engine_loaded():
    assert len(E.STANDARDS) >= 22
    assert "sleep_score" in E.STANDARDS  # the standardised one


def test_every_registry_metric_has_a_standard():
    missing = [m for m in RANKED_CATEGORY if m not in E.STANDARDS]
    assert not missing, f"engine missing standards for: {missing}"


def test_strength_requires_bodyweight():
    with pytest.raises(ValueError):
        E.tier_of("bench", 100)  # no bodyweight-at-time


def test_direction_lower_is_better():
    assert E.percentile("resting_hr", 50) > E.percentile("resting_hr", 80)
    assert E.percentile("body_fat_pct", 10) > E.percentile("body_fat_pct", 30)
