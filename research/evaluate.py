"""Nested leave-one-subject-out (LOSO) evaluation of the FoG detector on Daphnet.

Outer loop: hold out one patient. Inner loop (on the remaining patients only): train the model
with a further patient held out to get out-of-fold probabilities, and choose detector settings
for each false-alarm budget. Then train on all remaining patients and score the held-out one.
The held-out patient never influences either the model or the thresholds, so the numbers
estimate performance on a brand-new patient.

Usage:
    python evaluate.py                     # thigh sensor (phone-in-pocket proxy), full grid
    python evaluate.py --sensor trunk --quick
Writes results/<sensor>_report.{json,md}. For the thigh sensor it also exports the final model and
profile settings to ../Packages/FoGCore/Sources/FoGCore/Resources/detector_profiles.json.
"""

from __future__ import annotations

import argparse
import itertools
import json
import pickle
from pathlib import Path

import numpy as np

from fogdetect.calibration import calibrate
from fogdetect.data import Recording, load_all
from fogdetect.detector import DetectorConfig, run
from fogdetect.features import WindowFeatures, sliding_features
from fogdetect.metrics import EvalResult, evaluate
from fogdetect.model import LogisticModel, context_matrix, fit

ROOT = Path(__file__).resolve().parent
CACHE = ROOT / ".cache"
RESULTS = ROOT / "results"
EXPORT = ROOT.parent / "Packages" / "FoGCore" / "Sources" / "FoGCore" / "Resources" / "detector_profiles.json"

WINDOW_SEC = 3.0
HOP_SEC = 0.5
PROFILES = {"conservative": 0.5, "balanced": 1.0, "responsive": 2.0}
# Daphnet contains only supervised walking tasks, so it cannot measure false alarms from sitting,
# eating or gesturing. The prior-walking gate is the main protection against those in daily
# life, so it is a product rule for these profiles rather than a tunable.
FORCE_PRIOR_WALKING = {"conservative", "balanced"}
CALIBRATION_SEC = 120.0


def features_for(rec: Recording, sensor: str) -> list[WindowFeatures]:
    CACHE.mkdir(exist_ok=True)
    path = CACHE / f"{rec.name}_{sensor}_{WINDOW_SEC}_{HOP_SEC}.pkl"
    if path.exists():
        return pickle.loads(path.read_bytes())
    feats = sliding_features(rec.acc_g[sensor], rec.fs, WINDOW_SEC, HOP_SEC)
    path.write_bytes(pickle.dumps(feats))
    return feats


def window_labels(rec: Recording, feats: list[WindowFeatures]) -> np.ndarray:
    idx = np.clip((np.array([f.t_end for f in feats]) * rec.fs).astype(int) - 1, 0, len(rec.label) - 1)
    return rec.label[idx]


class Data:
    def __init__(self, recs: list[Recording], sensor: str):
        self.recs = recs
        self.subjects = sorted({r.subject for r in recs})
        self.feats, self.X, self.y = {}, {}, {}
        for r in recs:
            feats = features_for(r, sensor)
            lab = window_labels(r, feats)
            keep = lab != 0
            feats = [f for f, k in zip(feats, keep) if k]
            self.feats[r.name] = feats
            self.X[r.name] = context_matrix(feats)
            self.y[r.name] = (lab[keep] == 2).astype(int)

    def of(self, subjects) -> list[Recording]:
        return [r for r in self.recs if r.subject in set(subjects)]

    def train(self, subjects) -> LogisticModel:
        rs = self.of(subjects)
        return fit(np.vstack([self.X[r.name] for r in rs]), np.concatenate([self.y[r.name] for r in rs]))

    def calibration_walk(self, subject: str) -> list[WindowFeatures]:
        out: list[WindowFeatures] = []
        for r in self.of([subject]):
            lab = window_labels(r, self.feats[r.name])
            for f, l in zip(self.feats[r.name], lab):
                if l == 1:
                    out.append(f)
                if len(out) * HOP_SEC >= CALIBRATION_SEC:
                    return out
        return out


def probs(data: Data, model: LogisticModel, recs: list[Recording]) -> dict[str, np.ndarray]:
    out = {}
    for r in recs:
        z = ((data.X[r.name] - model.mean) / model.std) @ model.weights + model.bias
        out[r.name] = 1.0 / (1.0 + np.exp(-z))
    return out


def score(data: Data, recs: list[Recording], cfg: DetectorConfig, p: dict[str, np.ndarray],
          model: LogisticModel | None = None, personalize: bool = False) -> EvalResult:
    total = EvalResult()
    for r in recs:
        c = cfg
        if personalize and model is not None:
            c = calibrate(data.calibration_walk(r.subject), cfg, model)[0]
        events = run(data.feats[r.name], c, scores=p[r.name])
        total = total.add(evaluate(events, r.episodes(), r.valid_seconds(exclude_fog=True) / 3600.0))
    return total


def grid(quick: bool) -> list[DetectorConfig]:
    if quick:
        space = dict(prob_threshold=[0.6, 0.8], confirm_sec=[1.5, 2.5], require_prior_walking=[True, False],
                     stand_power_min=[1e-3])
    else:
        space = dict(prob_threshold=[0.5, 0.6, 0.7, 0.8, 0.9, 0.95], confirm_sec=[1.0, 1.5, 2.0, 3.0, 4.0],
                     require_prior_walking=[True, False], stand_power_min=[3e-4, 1e-3, 3e-3])
    keys = list(space)
    return [DetectorConfig(window_sec=WINDOW_SEC, hop_sec=HOP_SEC, **dict(zip(keys, v)))
            for v in itertools.product(*space.values())]


def pick(results: list[tuple[DetectorConfig, EvalResult]], budget: float, force_walk: bool = False) -> DetectorConfig:
    if force_walk:
        results = [(c, r) for c, r in results if c.require_prior_walking]
    ok = [(c, r) for c, r in results if r.fa_per_hour <= budget]
    if not ok:
        return min(results, key=lambda cr: (cr[1].fa_per_hour, -cr[1].sensitivity))[0]
    return max(ok, key=lambda cr: (round(cr[1].sensitivity, 3), -cr[1].fa_per_hour, cr[0].confirm_sec))[0]


def select_configs(data: Data, subjects: list[str], configs: list[DetectorConfig]) -> dict[str, DetectorConfig]:
    """Choose one config per profile using out-of-fold probabilities over `subjects`."""
    oof: dict[str, np.ndarray] = {}
    for u in subjects:
        m = data.train([s for s in subjects if s != u])
        oof.update(probs(data, m, data.of([u])))
    recs = data.of(subjects)
    results = [(c, score(data, recs, c, oof)) for c in configs]
    return {name: pick(results, budget, name in FORCE_PRIOR_WALKING) for name, budget in PROFILES.items()}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--sensor", default="thigh", choices=["ankle", "thigh", "trunk"])
    ap.add_argument("--quick", action="store_true")
    ap.add_argument("--no-export", action="store_true")
    args = ap.parse_args()

    data = Data(load_all(), args.sensor)
    configs = grid(args.quick)
    print(f"{len(data.recs)} recordings, {len(data.subjects)} subjects, {len(configs)} configs, sensor={args.sensor}")

    loso = {n: EvalResult() for n in PROFILES}
    loso_cal = {n: EvalResult() for n in PROFILES}
    chosen: dict[str, list[dict]] = {n: [] for n in PROFILES}
    for s in data.subjects:
        rest = [u for u in data.subjects if u != s]
        cfgs = select_configs(data, rest, configs)
        model = data.train(rest)
        held = data.of([s])
        p = probs(data, model, held)
        for name, cfg in cfgs.items():
            loso[name] = loso[name].add(score(data, held, cfg, p))
            loso_cal[name] = loso_cal[name].add(score(data, held, cfg, p, model=model, personalize=True))
            chosen[name].append({"held_out": s, "prob_threshold": cfg.prob_threshold, "confirm_sec": cfg.confirm_sec,
                                 "require_prior_walking": cfg.require_prior_walking,
                                 "stand_power_min": cfg.stand_power_min})
        print(f"  outer fold {s} done")

    final_cfgs = select_configs(data, data.subjects, configs)
    final_model = data.train(data.subjects)

    report = {"sensor": args.sensor, "dataset": "Daphnet Freezing of Gait (UCI #245)",
              "protocol": "nested leave-one-subject-out; model and thresholds never see the evaluated patient",
              "window_sec": WINDOW_SEC, "hop_sec": HOP_SEC, "profiles": {}}
    for name, budget in PROFILES.items():
        report["profiles"][name] = {
            "false_alarm_budget_per_hour": budget,
            "loso_population": loso[name].summary(),
            "loso_with_personal_calibration": loso_cal[name].summary(),
            "per_fold_choices": chosen[name],
            "final_config": final_cfgs[name].to_dict(),
        }
        print(f"[{name}] LOSO: {loso[name].summary()}")
        print(f"[{name}] LOSO+calibration: {loso_cal[name].summary()}")

    RESULTS.mkdir(exist_ok=True)
    (RESULTS / f"{args.sensor}_report.json").write_text(json.dumps(report, indent=2))
    (RESULTS / f"{args.sensor}_report.md").write_text(to_markdown(report))
    if not args.no_export and args.sensor == "thigh":
        EXPORT.parent.mkdir(parents=True, exist_ok=True)
        EXPORT.write_text(json.dumps({
            "source": f"Daphnet nested-LOSO, sensor={args.sensor}, window={WINDOW_SEC}s hop={HOP_SEC}s",
            "model": final_model.to_dict(),
            "profiles": {n: c.to_dict() for n, c in final_cfgs.items()},
        }, indent=2))
        print(f"exported -> {EXPORT}")


def to_markdown(report: dict) -> str:
    lines = [f"# Detector evaluation: {report['dataset']}, sensor = {report['sensor']}", "",
             f"Protocol: {report['protocol']}.", "",
             "| Profile | FA budget/h | Mode | Episodes cued (all) | Episodes cued (>=5 s) | False alarms/h | Median latency (s) |",
             "|---|---|---|---|---|---|---|"]
    for name, p in report["profiles"].items():
        for mode, key in [("population", "loso_population"), ("+ personal calibration", "loso_with_personal_calibration")]:
            s = p[key]
            lines.append(f"| {name} | {p['false_alarm_budget_per_hour']} | {mode} | {s['sensitivity']:.1%} | "
                         f"{s['sensitivity_ge_5s']:.1%} | {s['false_alarms_per_hour']} | {s['median_latency_s']} |")
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    main()
