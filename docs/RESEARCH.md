# Research summary: freezing of gait and rhythmic cueing

Citations like [n] point to [REFERENCES.md](REFERENCES.md).

## 1. The problem

- **What it is.** Freezing of gait (FoG) is a sudden, brief inability to step, or steps that
  become extremely short, even though the person is trying to walk. Patients describe their feet
  as "glued to the floor". It usually happens when starting to walk or turning, and also in
  doorways, in tight spaces, and while multitasking. During a freeze the legs often tremble
  instead of stepping [1].
- **How common it is.** About 40% of people with Parkinson's disease (PD) have FoG (pooled 39.9%
  across 5,361 patients) [2]. The share rises to 70.8% after 10 years with the disease [2]. FoG
  lowers quality of life independently of other symptoms [3]. The Kaggle contest paper puts it
  at 38-65% of people with PD [15].
- **How many people.** 11.77 million people had PD worldwide in 2021 [4], and the WHO reports
  that prevalence doubled in 25 years [5]. So roughly 4-5 million people live with FoG
  (11.77 M x ~40%). This is an order-of-magnitude estimate, not a market size.
- **Why it matters.** FoG leads to falls and loss of independence, and it responds poorly to
  medication in advanced disease [1].

## 2. Why a rhythm helps (the intervention is evidence-based)

- **External cues.** A steady beat, heard or felt, gives the brain an outside timing signal that
  stands in for the impaired internal one.
- **RESCUE trial.** An RCT with 153 patients [6] found that home rhythmic cueing reduced freezing
  severity in freezers and improved gait speed and step length. The benefit faded once cueing
  stopped, which led the authors to call for "permanent cueing devices" [6]. That is the product
  gap this app targets.
- **Meta-analyses.** Auditory cueing improves gait speed and stride length [7, 8].
- **Cues can be felt, not only heard.** A metronome (open-loop) and wrist tactile cueing
  (closed-loop) both reduced the time spent frozen while turning [10]. Wrist haptics are
  therefore a valid cue, and a discreet one.
- **Caveats.** Results vary between patients and long-term carry-over is weak [9]. This supports
  (a) personal tuning of the cue and (b) cueing on demand instead of continuously.
- **Tempo.** Studies cue at or near the person's own comfortable cadence [6, 8]. The app
  measures cadence during a 2-minute setup walk and lets the caregiver adjust it.

## 3. Can a wearable detect a freeze?

| Study | Sensor | Result | Takeaway |
|---|---|---|---|
| Moore 2008 [11] | Ankle, 100 Hz | Freeze Index; 78% detected with a global threshold, 89% with a per-patient one; false positives 20% -> 10% | Personal calibration matters a lot |
| Bächlin 2010 [12] | Ankle/thigh/trunk | 73.1% sensitivity, 81.6% specificity online, with auto-metronome | Closed-loop cueing works; most patients found it helpful |
| Mazilu 2016 [14] | **Wrist** | FoG hit rate 0.9, specificity 0.66-0.80 | The wrist can work, but gives **more false alarms** than leg sensors |
| Salomon 2024 [15] | Lower back | 1,379 teams; strong specificity and precision | Larger data and ML help; still not wrist data |

An 81.6% specificity sounds high. But one analysis window every 0.5 s means hundreds of windows
per minute, so a small per-window error rate becomes several false cues per hour. **Window-level
accuracy is the wrong metric for this product.** We measure *false alarms per hour* at the
event level instead.

## 4. What we measured ourselves

We rebuilt a detector (`research/`) and evaluated it on Daphnet [13] with **nested
leave-one-subject-out** validation: the model and thresholds never see the patient being scored.
Full tables are in `research/results/*_report.md`.

Detector: spectral features that don't depend on how the sensor is oriented, plus temporal
context, feed a logistic regression. Its output then has to pass a stillness floor, a
persistence gate and an optional "was just walking" gate. For unseen patients it reaches a
window-level ROC AUC of 0.83 (thigh), 0.88 (ankle) and 0.81 (trunk).

Event-level results for a brand-new patient, before any personal data:

| Sensor | Profile | Freezes cued | False alarms per hour of lab walking |
|---|---|---|---|
| Thigh (phone-in-pocket proxy) | Fewest false alarms | 8.9% | 2.5 |
| Thigh | Catch more freezes | 22.4% | 2.2 |
| Trunk (belt clip) | Fewest false alarms | 16.0% | 0.45 |
| Ankle | Catch more freezes | 35.4% | 1.3 |

**Honest conclusions:**

1. **Near-zero false alarms combined with useful sensitivity is not achievable today** for a new
   patient with a generic accelerometer model on the best public data. This matches the
   published numbers above.
2. **Personal adaptation is the main lever.** Moore's per-patient thresholds roughly halved false
   positives [11]. In our small within-patient test (one labeled session to train, one held-out
   session to test), sensitivity rose to about 50% of freezes cued, but false alarms stayed near
   5 per hour. The patient-specific test set is too small (60 freezes, under 1 hour) to trust
   either number, which is why step 1 of the validation plan is a labeled wrist study.
3. **The wrist has not been validated.** No public labeled wrist dataset exists, and Mazilu [14]
   shows the wrist produces more false detections than leg sensors. The watch ships with a
   study-recording mode so the first pilot produces that dataset.
4. **Daphnet contains only supervised walking tasks.** It cannot measure false alarms from
   sitting, eating or gesturing. That is why the "just walking" gate is a hard rule in the
   default profile, not a tuned parameter.

## 5. Design decisions that follow

| Evidence | Decision |
|---|---|
| Cueing works but detection is imperfect [6-12] | The **"Help me walk" button** gives a cue with zero false positives, from day one. Automatic detection is an addition, not the product's foundation. |
| Wrist tactile cues work [10] | Default cue is **wrist taps first, sound only if the freeze continues** (after 4 s). A false alarm costs a few discreet taps. |
| Per-patient thresholds help [11] | 2-minute **setup walk** raises the threshold above that person's normal gait. **Yes/No labels** after each cue feed personal retraining. |
| False alarms are the adoption killer | **Fewest-false-alarms profile by default**, "just walking" gate always on, 3-4 s persistence, auto-stop when walking resumes, one-tap Stop. |
| Evidence varies by patient [9] | Tempo, cue type and sensitivity are all adjustable by the caregiver. |
| Background sensing on watchOS needs a workout session [16] | Detection runs only in **walk mode**, which the patient or caregiver starts. This also limits exposure to daily-life false alarms. |
