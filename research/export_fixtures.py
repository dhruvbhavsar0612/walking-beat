"""Export golden fixtures so the Swift port (FoGCore) can be verified against this reference.

Takes a real Daphnet thigh segment containing freezes, runs the Python feature extractor,
model and detector, and writes raw samples + expected outputs to
../Packages/FoGCore/Tests/FoGCoreTests/Fixtures/.
"""

from __future__ import annotations

import json
from dataclasses import replace
from pathlib import Path

import numpy as np

from fogdetect.calibration import calibrate
from fogdetect.data import load_all
from fogdetect.detector import DetectorConfig, EndReason, FoGDetector
from fogdetect.features import sliding_features
from fogdetect.model import LogisticModel
from evaluate import EXPORT

OUT = Path(__file__).resolve().parent.parent / "Packages" / "FoGCore" / "Tests" / "FoGCoreTests" / "Fixtures"
RECORDING = "S02R02"
SEGMENT_SEC = (200.0, 560.0)


def main() -> None:
    profiles = json.loads(EXPORT.read_text())
    model = LogisticModel.from_dict(profiles["model"])
    rec = next(r for r in load_all() if r.name == RECORDING)
    a, b = (int(s * rec.fs) for s in SEGMENT_SEC)
    xyz = rec.acc_g["thigh"][a:b]
    OUT.mkdir(parents=True, exist_ok=True)
    np.savetxt(OUT / "samples.csv", xyz, fmt="%.6f", delimiter=",")
    xyz = np.loadtxt(OUT / "samples.csv", delimiter=",")

    base_cfg = replace(_cfg(profiles["profiles"]["responsive"]), require_prior_walking=False, prob_threshold=0.6)
    feats = sliding_features(xyz, rec.fs, base_cfg.window_sec, base_cfg.hop_sec)

    def detect(cfg, mdl):
        det = FoGDetector(cfg=cfg, model=mdl)
        scores = []
        for f in feats:
            det.update(f)
            scores.append(det.last_score)
        if det.active is not None:
            det._end(feats[-1].t_end, EndReason.TIMEOUT)
        return scores, [{"onset_t": e.onset_t, "confirmed_t": e.confirmed_t, "end_t": e.end_t,
                         "end_reason": e.end_reason.value if e.end_reason else None} for e in det.events]

    model_scores, model_events = detect(base_cfg, model)
    rule_cfg = replace(base_cfg, use_model=False, fi_threshold=2.0)
    _, rule_events = detect(rule_cfg, None)
    cal_cfg, cal_info = calibrate(feats[:240], base_cfg, model)

    expected = {
        "recording": RECORDING,
        "segment_sec": SEGMENT_SEC,
        "sample_rate": rec.fs,
        "model_config": base_cfg.to_dict(),
        "rule_config": rule_cfg.to_dict(),
        "features": [[f.t_end, f.loco_power, f.freeze_power, f.freeze_index, f.dominant_freq] for f in feats],
        "model_scores": model_scores,
        "model_events": model_events,
        "rule_events": rule_events,
        "calibration": {"windows": 240, "ok": cal_info["ok"], "prob_threshold": cal_cfg.prob_threshold,
                        "walk_power_min": cal_cfg.walk_power_min},
    }
    (OUT / "expected.json").write_text(json.dumps(expected))
    print(f"{len(feats)} windows, {len(model_events)} model events, {len(rule_events)} rule events -> {OUT}")


def _cfg(d: dict) -> DetectorConfig:
    return DetectorConfig(**d)


if __name__ == "__main__":
    main()
