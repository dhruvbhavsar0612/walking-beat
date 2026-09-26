"""Loader for the Daphnet Freezing of Gait dataset (Bächlin et al., 2010; UCI ML Repository #245).

Format per line: time_ms, ankle(x,y,z), thigh(x,y,z), trunk(x,y,z), annotation
Acceleration unit: mg. Sampling rate: 64 Hz.
Annotation: 0 = not part of experiment, 1 = no freeze, 2 = freeze.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import numpy as np

FS = 64.0
SENSORS = {"ankle": slice(1, 4), "thigh": slice(4, 7), "trunk": slice(7, 10)}
DEFAULT_DIR = Path(__file__).resolve().parent.parent / "data" / "dataset_fog_release" / "dataset"


@dataclass
class Recording:
    name: str
    subject: str
    fs: float
    t: np.ndarray
    acc_g: dict[str, np.ndarray]
    label: np.ndarray

    def episodes(self) -> list[tuple[float, float]]:
        """Contiguous annotation==2 segments as (start_s, end_s)."""
        fog = (self.label == 2).astype(np.int8)
        edges = np.diff(np.concatenate([[0], fog, [0]]))
        starts = np.where(edges == 1)[0]
        ends = np.where(edges == -1)[0]
        return [(self.t[s], self.t[e - 1]) for s, e in zip(starts, ends)]

    def valid_seconds(self, exclude_fog: bool = False) -> float:
        mask = self.label != 0
        if exclude_fog:
            mask &= self.label != 2
        return float(mask.sum() / self.fs)


def load_recording(path: Path) -> Recording:
    raw = np.loadtxt(path)
    t = (raw[:, 0] - raw[0, 0]) / 1000.0
    acc = {name: raw[:, sl] / 1000.0 for name, sl in SENSORS.items()}
    return Recording(
        name=path.stem,
        subject=path.stem[:3],
        fs=FS,
        t=t,
        acc_g=acc,
        label=raw[:, 10].astype(np.int8),
    )


def load_all(data_dir: Path = DEFAULT_DIR) -> list[Recording]:
    files = sorted(data_dir.glob("S*R*.txt"))
    if not files:
        raise FileNotFoundError(f"No Daphnet files in {data_dir}. Run research/download_datasets.py first.")
    return [load_recording(f) for f in files]
