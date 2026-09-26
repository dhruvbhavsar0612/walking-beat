# Detector evaluation: Daphnet Freezing of Gait (UCI #245), sensor = trunk

Protocol: nested leave-one-subject-out; model and thresholds never see the evaluated patient.

| Profile | FA budget/h | Mode | Episodes cued (all) | Episodes cued (>=5 s) | False alarms/h | Median latency (s) |
|---|---|---|---|---|---|---|
| conservative | 0.5 | population | 16.0% | 23.6% | 0.45 | 2.18 |
| conservative | 0.5 | + personal calibration | 14.8% | 21.1% | 0.22 | 2.14 |
| balanced | 1.0 | population | 16.9% | 25.2% | 0.45 | 2.18 |
| balanced | 1.0 | + personal calibration | 14.8% | 21.1% | 0.22 | 2.14 |
| responsive | 2.0 | population | 30.0% | 37.4% | 6.93 | 0.0 |
| responsive | 2.0 | + personal calibration | 25.3% | 35.0% | 2.01 | 1.14 |
