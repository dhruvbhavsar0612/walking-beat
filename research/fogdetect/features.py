"""Window-level spectral features for FoG detection.

This module is the reference implementation. `Packages/FoGCore/Sources/FoGCore/FeatureExtractor.swift`
must produce the same numbers (verified via `research/export_fixtures.py` + Swift tests).

Band power is summed over the three accelerometer axes. By Parseval's theorem this sum is
invariant to any fixed rotation of the sensor within a window, so the result does not depend on
how the watch sits on the wrist or how the phone sits in a pocket (unlike single-axis features
from the ankle-mounted, axis-aligned sensors used in the original studies).
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

LOCO_BAND = (0.5, 3.0)
FREEZE_BAND = (3.0, 8.0)
EPS = 1e-9


@dataclass(frozen=True)
class WindowFeatures:
    t_end: float
    loco_power: float
    freeze_power: float
    freeze_index: float
    dominant_freq: float

    @property
    def total_power(self) -> float:
        return self.loco_power + self.freeze_power


def hann(n: int) -> np.ndarray:
    k = np.arange(n)
    return 0.5 - 0.5 * np.cos(2.0 * np.pi * k / n)


def band_bins(n: int, fs: float) -> np.ndarray:
    df = fs / n
    k_min = int(np.ceil(LOCO_BAND[0] / df - 1e-9))
    k_max = int(np.floor(FREEZE_BAND[1] / df + 1e-9))
    return np.arange(k_min, k_max + 1)


def window_features(xyz: np.ndarray, fs: float, t_end: float) -> WindowFeatures:
    """Band powers over one (n, 3) window via a direct DFT on only the 0.5-8 Hz bins.

    A direct DFT on ~30 bins is cheap enough for a watch and trivially portable, so the Swift
    port does not depend on Accelerate/vDSP and can be tested on Linux.
    """
    xyz = np.asarray(xyz, dtype=np.float64)
    if xyz.ndim == 1:
        xyz = xyz[:, None]
    n = xyz.shape[0]
    x = (xyz - xyz.mean(axis=0)) * hann(n)[:, None]
    ks = band_bins(n, fs)
    angles = 2.0 * np.pi * np.outer(ks, np.arange(n)) / n
    re = np.cos(angles) @ x
    im = np.sin(angles) @ x
    power = ((re * re + im * im) / (n * n)).sum(axis=1)
    freqs = ks * (fs / n)

    loco_mask = (freqs >= LOCO_BAND[0] - 1e-9) & (freqs < LOCO_BAND[1] - 1e-9)
    freeze_mask = (freqs >= FREEZE_BAND[0] - 1e-9) & (freqs <= FREEZE_BAND[1] + 1e-9)
    loco = float(power[loco_mask].sum())
    freeze = float(power[freeze_mask].sum())
    dom = float(freqs[loco_mask][int(np.argmax(power[loco_mask]))]) if loco_mask.any() else 0.0
    return WindowFeatures(
        t_end=t_end,
        loco_power=loco,
        freeze_power=freeze,
        freeze_index=freeze / (loco + EPS),
        dominant_freq=dom,
    )


def sliding_features(xyz: np.ndarray, fs: float, window_sec: float, hop_sec: float) -> list[WindowFeatures]:
    n = int(round(window_sec * fs))
    hop = int(round(hop_sec * fs))
    return [window_features(xyz[end - n : end], fs, t_end=end / fs) for end in range(n, len(xyz) + 1, hop)]
