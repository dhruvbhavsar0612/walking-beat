# Detector evaluation: Daphnet Freezing of Gait (UCI #245), sensor = ankle

Protocol: nested leave-one-subject-out; model and thresholds never see the evaluated patient.

| Profile | FA budget/h | Mode | Episodes cued (all) | Episodes cued (>=5 s) | False alarms/h | Median latency (s) |
|---|---|---|---|---|---|---|
| conservative | 0.5 | population | 7.6% | 11.4% | 0.45 | 2.98 |
| conservative | 0.5 | + personal calibration | 6.8% | 11.4% | 0.22 | 2.98 |
| balanced | 1.0 | population | 9.3% | 14.6% | 2.46 | 3.67 |
| balanced | 1.0 | + personal calibration | 8.4% | 14.6% | 2.01 | 3.67 |
| responsive | 2.0 | population | 35.4% | 47.2% | 1.34 | 0.52 |
| responsive | 2.0 | + personal calibration | 35.4% | 48.0% | 1.34 | 0.87 |
