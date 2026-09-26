# Detector evaluation: Daphnet Freezing of Gait (UCI #245), sensor = thigh

Protocol: nested leave-one-subject-out; model and thresholds never see the evaluated patient.

| Profile | FA budget/h | Mode | Episodes cued (all) | Episodes cued (>=5 s) | False alarms/h | Median latency (s) |
|---|---|---|---|---|---|---|
| conservative | 0.5 | population | 8.9% | 11.4% | 2.46 | 1.84 |
| conservative | 0.5 | + personal calibration | 7.6% | 10.6% | 2.01 | 2.16 |
| balanced | 1.0 | population | 9.3% | 12.2% | 3.13 | 1.55 |
| balanced | 1.0 | + personal calibration | 8.0% | 11.4% | 2.01 | 2.48 |
| responsive | 2.0 | population | 22.4% | 30.9% | 2.24 | 1.84 |
| responsive | 2.0 | + personal calibration | 18.6% | 27.6% | 1.79 | 3.29 |
