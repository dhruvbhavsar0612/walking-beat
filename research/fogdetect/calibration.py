"""Personal calibration from a short guided walk (mirrors FoGCore `Calibration.swift`).

Moore et al. (2008) showed per-patient freeze thresholds raised sensitivity from 78% to 89% while
lowering false positives. The app records a ~2 minute normal walk and derives:
  - walk_power_min: a fraction of the patient's own median locomotor power, so slow shufflers
    still register as walking.
  - the evidence threshold: above the highest score the patient's own normal walking produced,
    so their everyday gait cannot trigger a cue. It is never lowered below the population value.
"""

from __future__ import annotations

from dataclasses import replace

import numpy as np

from .detector import DetectorConfig
from .features import WindowFeatures
from .model import ContextFeaturizer, LogisticModel

MIN_WALK_WINDOWS = 20
PROB_CAP = 0.97


def gait_like(f: WindowFeatures, cfg: DetectorConfig) -> bool:
    return cfg.walk_freq_min <= f.dominant_freq <= cfg.walk_freq_max and f.loco_power >= cfg.walk_power_min * 0.25


def calibrate(walk: list[WindowFeatures], base: DetectorConfig, model: LogisticModel | None = None,
              score_percentile: float = 99.0, prob_margin: float = 0.05, fi_margin: float = 1.25,
              power_fraction: float = 0.3) -> tuple[DetectorConfig, dict]:
    fz = ContextFeaturizer()
    scored = []
    for f in walk:
        ctx = fz.push(f)
        if gait_like(f, base):
            scored.append((f, model.prob(ctx) if base.use_model and model is not None else f.freeze_index))
    if len(scored) < MIN_WALK_WINDOWS:
        return base, {"ok": False, "reason": "not_enough_walking", "windows": len(scored)}
    loco = np.array([f.loco_power for f, _ in scored])
    s = np.array([v for _, v in scored])
    walk_power_min = float(max(base.walk_power_min * 0.25, power_fraction * np.median(loco)))
    top = float(np.percentile(s, score_percentile))
    if base.use_model:
        cfg = replace(base, walk_power_min=walk_power_min,
                      prob_threshold=float(min(PROB_CAP, max(base.prob_threshold, top + prob_margin))))
    else:
        cfg = replace(base, walk_power_min=walk_power_min, fi_threshold=float(max(base.fi_threshold, fi_margin * top)))
    return cfg, {"ok": True, "windows": len(scored), "walk_power_min": cfg.walk_power_min,
                 "prob_threshold": cfg.prob_threshold, "fi_threshold": cfg.fi_threshold}
