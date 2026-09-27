# Evidence log: what we claim and what proves it

Citations [n] refer to [REFERENCES.md](REFERENCES.md). This file maps **product decisions and
marketing-safe claims** to their evidence, with an honest strength rating. Update it whenever a
new claim enters the UI, the README, or fundraising material. Rule: **a claim with no row here
does not ship.**

Claim strength scale: **Strong** (RCT / meta-analysis), **Moderate** (repeated controlled
studies, smaller n), **Weak/Indirect** (proxy data, lab studies, expert consensus),
**Our data** (we measured it; see the linked artifact).

| # | Claim / decision Where it appears | Evidence | Strength |
|---|---|---|---|
| E1 | Freezing of gait affects ~40% of people with PD (rises ~70% after 10 y) → market framing "4–5 M people" | [2] pooled prevalence meta-analysis (5,361 patients); [15] | Strong |
| E2 | FoG is a major fall driver and lowers quality of life | [1], [3] | Strong |
| E3 | A steady rhythmic beat (auditory or tactile) helps patients re-start walking — the intervention works | [6] RESCUE RCT (n=153); meta-analyses [7, 8]; haptic cueing [10] | Strong |
| E4 | Benefit fades when cueing stops → a *permanent, always-available* cueing device is the unmet need we fill | [6] (authors' own conclusion) | Strong |
| E5 | Cuing on demand (closed-loop) is preferable to continuous cueing (habituation/annoyance) | [12] Bächlin 2010; review [9] | Moderate |
| E6 | Wrist taps are a valid, discreet cue channel (not just audio) | [10] wrist vibrotactile reduced frozen time while turning | Moderate |
| E7 | Cue tempo should be individualized, near the patient's own cadence; **110% of preferred cadence showed the strongest effects incl. fewer freezes** (vs 100%: weaker/none) — basis for the app's 90/100/110% tempo chips and auto-suggested 110% | Arias & Cudeiro 2010 [PLoS One, PD+FOG, 110% significantly reduced FOG where 100% study found none]; 2019 Clin Neurophysiol (RAS 110% best ON and OFF); Physiopedia RAS protocol synthesis | Moderate (consistent across independent studies; n≈30 each) |
| E18 | **Phone-in-pocket detection uses our best-validated sensor placement** — the model was trained/evaluated on thigh-worn Daphnet data; a trouser-pocketed phone is the closest consumer analog. Phone walk mode (v4) is therefore not a degraded fallback but the configuration with the strongest published + our-data evidence | [11][12][13] all leg-worn; our thigh numbers in `research/results/thigh_report.json` | Moderate + Our data |
| E8 | Cadence can be measured by the lay user's wrist during a guided 2-minute walk (no physician needed for basic setup); a physiotherapist's assessment remains useful for complex cases — positioning is "bring the data to your clinician", not "diagnose" | [8] cue tempo matched to cadence is standard practice; physio protocol steps (measure → set → sync → adjust) | Moderate |
| E9 | Per-patient thresholds roughly halve false positives vs global thresholds — basis for the setup-walk personalization gate | [11] Moore 2008 (FP 20%→10%) | Moderate |
| E10 | Wrist-only detection works but produces **more false alarms** than leg-worn sensors — basis for conservative default + honest About screen | [14] Mazilu 2016 (wrist hit rate 0.9, specificity 0.66–0.80) | Moderate |
| E11 | Closed-loop auto-metronome cueing on real patients reduced freeze duration — basis for the automatic-detection feature existing at all | [12] Bächlin 2010 (73% sens, 82% spec, online) | Moderate |
| E12 | Our detector on Daphnet (nested LOSO): best honest configs trade sensitivity vs FP/hr (e.g., trunk 16% cued @ 0.45 FP/h conservative; 25–30% cued responsive after calibration; thigh 8–22% @ ~2 FP/h). **No new-patient config meets both product targets** → detection is gated conservative and the manual Help button is the floor | Our data: `research/results/*.json`, `docs/RESEARCH.md §4` | Our data |
| E13 | Personal adaptation is the main lever to improve wrist detection; labeled wrist data is the missing dataset — basis for study-recording mode + Yes/No labels (phase 2) | [11], [14] + Our data (within-patient test, small n) | Moderate + Our data |
| E14 | Elderly/PD users need guided configuration, plain language, large text; "no guidelines/tutorials" was the worst usability violation found in a 63-participant PD-app evaluation; caregivers are the second-most-interested user group — basis for role-based app (patient vs caregiver), wizard setup, Dynamic Type | Usability study "Vivendo com Parkinson" (Heliyon/PMC 2023); elder-UX checklist (UX Collective 2024); systematic review of age-friendly design (PMC 2025) | Moderate |
| E15 | Apple Watch background high-rate sensing requires an active HKWorkoutSession — basis for walk-mode design | Apple docs (watchOS background), [16] in README context | Platform fact |
| E16 | Disease-claim apps → SaMD: FDA 510(k)/De Novo path (Apple-Watch PD software precedent NeuroRPM [19]); EU MDR Rule 11 → likely Class IIa; general-wellness exclusion [20] → no disease claims in marketing until regulated | [19], [20], PRODUCT_PLAN §7 + regulatory counsel TBD | Regulatory analysis (not legal advice) |
| E17 | Competitors need dedicated hardware (CUE1+ sternum device [17], Path Finder laser shoes [18]); NeuroRPM monitors but does not cue [19] — basis for differentiation "runs on the watch people already wear" | [17-19] product/registry sources | Moderate |

## Gaps we must not paper over

- No public **wrist-labeled** FoG dataset exists (T1 study exists to create one). Any wrist
  detection accuracy claim before T1 = fabrication.
- Daphnet does not contain daily-life negatives; FP/hour during sitting/eating is extrapolated,
  mitigated by the hard just-walking gate (default profile).
- Long-term carry-over of cue benefit is weak [6, 9] → we do not claim lasting unaided
  improvement, only in-the-moment help.
