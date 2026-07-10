"""Regenerate test/golden_vectors.json from the canonical Python engine.

The vectors pin Python⇄Dart parity: every case's INPUTS (metric, value,
bodyweight / logs) are kept exactly as they are in the existing file, and the
EXPECTED outputs are recomputed from `lib/engine/physical_rank_engine.py`. Run
this after ANY standards change, then run `flutter test test/rank_engine_test.dart`
to prove the Dart port still matches.

    python3 backend/scripts/gen_golden.py
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "lib" / "engine"))
import physical_rank_engine as E  # noqa: E402

GOLDEN = ROOT / "test" / "golden_vectors.json"


def _r(x: float) -> float:
    return round(x, 6)


def _tier_expected(metric: str, value: float, bw) -> dict:
    t = E.tier_of(metric, value, bw)
    return {
        "tier": t["tier"], "sub": t["sub"],
        "percentile": _r(t["percentile"]),
        "top_pct": _r(t["top_pct"]),
        "rank_value": _r(t["rank_value"]),
    }


def main() -> None:
    golden = json.loads(GOLDEN.read_text())

    for c in golden["metric_cases"]:
        c["expected"] = _tier_expected(c["metric"], c["value"], c.get("bodyweight"))

    for c in golden["threshold_cases"]:
        kg = _r(E.threshold(c["metric"], c["tier"], c.get("bodyweight")))
        c["expected_kg"] = kg
        c["expected"] = kg

    for c in golden["overall_cases"]:
        logs = [E.Log(l["metric"], l["value"], l.get("bodyweight")) for l in c["logs"]]
        o = E.overall(logs)
        c["expected"] = {"tier": o["tier"], "sub": o["sub"],
                         "top_pct": _r(o["top_pct"]), "rank_value": _r(o["rank_value"])}

    for c in golden["category_overall_cases"]:
        by_cat = {
            cat: [E.Log(l["metric"], l["value"], l.get("bodyweight")) for l in logs]
            for cat, logs in c["logs_by_cat"].items()
        }
        o = E.overall_by_category(by_cat)
        c["expected"] = {"tier": o["tier"], "sub": o["sub"],
                         "top_pct": _r(o["top_pct"]), "rank_value": _r(o["rank_value"])}

    GOLDEN.write_text(json.dumps(golden, indent=1) + "\n")
    n = sum(len(golden[k]) for k in
            ("metric_cases", "threshold_cases", "overall_cases", "category_overall_cases"))
    print(f"regenerated {n} golden cases -> {GOLDEN}")


if __name__ == "__main__":
    main()
