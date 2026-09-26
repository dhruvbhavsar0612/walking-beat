import numpy as np
import pytest

from fogdetect.calibration import calibrate
from fogdetect.detector import DetectorConfig, EndReason, FoGDetector, run
from fogdetect.detector import FoGEvent
from fogdetect.features import sliding_features, window_features
from fogdetect.metrics import evaluate

FS = 64.0


def sine(hz, sec, amp=0.3):
    t = np.arange(int(sec * FS)) / FS
    s = amp * np.sin(2 * np.pi * hz * t)
    return np.stack([s, 1.0 + 0.5 * s, 0.3 * s], axis=1)


def rule_cfg(**kw):
    return DetectorConfig(use_model=False, fi_threshold=2.0, **kw)


def test_band_assignment():
    walk = window_features(sine(1.75, 3), FS, 3)
    tremble = window_features(sine(5.5, 3), FS, 3)
    assert walk.loco_power > 10 * walk.freeze_power
    assert tremble.freeze_power > 10 * tremble.loco_power
    assert walk.dominant_freq == pytest.approx(1.67, abs=0.34)


def test_rotation_invariance():
    x = sine(1.75, 3) + sine(5.0, 3, amp=0.1)
    theta = 0.7
    rot = np.array([[np.cos(theta), -np.sin(theta), 0], [np.sin(theta), np.cos(theta), 0], [0, 0, 1]])
    a, b = window_features(x, FS, 3), window_features(x @ rot.T, FS, 3)
    assert a.loco_power == pytest.approx(b.loco_power, rel=1e-9)
    assert a.freeze_index == pytest.approx(b.freeze_index, rel=1e-9)


def test_no_cue_when_walking_or_still():
    still = np.tile([0.0, 1.0, 0.0], (int(120 * FS), 1))
    assert run(sliding_features(still, FS, 3, 0.5), rule_cfg(require_prior_walking=False)) == []
    assert run(sliding_features(sine(1.8, 180), FS, 3, 0.5), rule_cfg()) == []


def test_freeze_after_walk_is_cued_and_ends_on_resume():
    x = np.vstack([sine(1.8, 20), sine(5.5, 8, 0.25), sine(1.8, 20)])
    events = run(sliding_features(x, FS, 3, 0.5), rule_cfg())
    assert len(events) == 1
    assert 20 < events[0].confirmed_t < 25
    assert events[0].end_reason == EndReason.WALKING_RESUMED


def test_tremble_without_walking_blocked_by_gate():
    x = np.vstack([np.tile([0.0, 1.0, 0.0], (int(10 * FS), 1)), sine(5.5, 10, 0.25)])
    assert run(sliding_features(x, FS, 3, 0.5), rule_cfg()) == []
    assert len(run(sliding_features(x, FS, 3, 0.5), rule_cfg(require_prior_walking=False))) == 1


def test_model_required():
    det = FoGDetector(cfg=DetectorConfig(use_model=True))
    with pytest.raises(ValueError):
        det.update(window_features(sine(1.8, 3), FS, 3))


def test_metrics_counts():
    events = [FoGEvent(onset_t=9, confirmed_t=11, end_t=15), FoGEvent(onset_t=99, confirmed_t=100, end_t=101)]
    res = evaluate(events, [(10, 14), (50, 55)], non_fog_hours=1.0)
    assert (res.detected, res.false_alarms) == (1, 1)
    assert res.fa_per_hour == 1.0
    assert res.latencies == [1.0]


def test_calibration_never_lowers_threshold():
    feats = sliding_features(sine(1.8, 150), FS, 3, 0.5)
    cfg, info = calibrate(feats, rule_cfg())
    assert info["ok"]
    assert cfg.fi_threshold >= 2.0
