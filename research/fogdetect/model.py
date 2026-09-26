"""Streaming context features + logistic regression FoG probability (mirrors FoGCore `FoGModel.swift`).

Logistic regression was chosen over gradient boosting because leave-one-subject-out window AUC
on Daphnet was close (thigh 0.825 vs 0.851) while LR ports to the watch as one dot product,
is fully inspectable, and cannot silently diverge between Python and Swift.
"""

from __future__ import annotations

from collections import deque
from dataclasses import dataclass, field

import numpy as np

from .features import WindowFeatures

LOG_EPS = 1e-6
BASELINE_WINDOWS = 20
LAGS = (2, 4, 8)
FEATURE_NAMES = ["log_loco", "log_freeze", "log_fi", "dominant_freq", "loco_vs_recent_max"] + [
    f"{name}_lag{lag}" for lag in LAGS for name in ("log_loco", "log_fi")
]


@dataclass
class ContextFeaturizer:
    history: deque = field(default_factory=lambda: deque(maxlen=BASELINE_WINDOWS + 1))

    def reset(self) -> None:
        self.history.clear()

    def push(self, f: WindowFeatures) -> np.ndarray:
        lp = float(np.log10(f.loco_power + LOG_EPS))
        fp = float(np.log10(f.freeze_power + LOG_EPS))
        fi = fp - lp
        self.history.append((lp, fi))
        recent_max = max(h[0] for h in self.history)
        vec = [lp, fp, fi, f.dominant_freq, lp - recent_max]
        n = len(self.history)
        for lag in LAGS:
            past = self.history[n - 1 - lag] if n > lag else self.history[0]
            vec += [past[0], past[1]]
        return np.array(vec, dtype=np.float64)


@dataclass
class LogisticModel:
    mean: np.ndarray
    std: np.ndarray
    weights: np.ndarray
    bias: float

    def prob(self, x: np.ndarray) -> float:
        z = float(((x - self.mean) / self.std) @ self.weights + self.bias)
        return 1.0 / (1.0 + np.exp(-z))

    def to_dict(self) -> dict:
        return {"feature_names": FEATURE_NAMES, "mean": self.mean.tolist(), "std": self.std.tolist(),
                "weights": self.weights.tolist(), "bias": self.bias}

    @staticmethod
    def from_dict(d: dict) -> "LogisticModel":
        return LogisticModel(np.array(d["mean"]), np.array(d["std"]), np.array(d["weights"]), float(d["bias"]))


def context_matrix(feats: list[WindowFeatures]) -> np.ndarray:
    fz = ContextFeaturizer()
    return np.stack([fz.push(f) for f in feats]) if feats else np.zeros((0, len(FEATURE_NAMES)))


def fit(X: np.ndarray, y: np.ndarray, C: float = 1.0) -> LogisticModel:
    from sklearn.linear_model import LogisticRegression

    mean = X.mean(axis=0)
    std = X.std(axis=0) + 1e-9
    lr = LogisticRegression(max_iter=3000, C=C, class_weight="balanced").fit((X - mean) / std, y)
    return LogisticModel(mean, std, lr.coef_[0].astype(np.float64), float(lr.intercept_[0]))
